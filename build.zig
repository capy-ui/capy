const std = @import("std");
const http = @import("deps.zig").imports.apple_pie;
const install = @import("build_capy.zig").install;
const FileSource = std.build.FileSource;

/// Step used to run a web server
const WebServerStep = struct {
    step: std.build.Step,
    exe: *std.build.LibExeObjStep,
    builder: *std.build.Builder,

    pub fn create(builder: *std.build.Builder, exe: *std.build.LibExeObjStep) *WebServerStep {
        const self = builder.allocator.create(WebServerStep) catch unreachable;
        self.* = .{
            .step = std.build.Step.init(.custom, "webserver", builder.allocator, WebServerStep.make),
            .exe = exe,
            .builder = builder,
        };
        return self;
    }

    const Context = struct {
        exe: *std.build.LibExeObjStep,
        builder: *std.build.Builder,
    };

    pub fn make(step: *std.build.Step) !void {
        const self = @fieldParentPtr(WebServerStep, "step", step);
        const allocator = self.builder.allocator;

        var context = Context{ .builder = self.builder, .exe = self.exe };
        const builder = http.router.Builder(*Context);
        std.debug.print("Web server opened at http://localhost:8080/\n", .{});
        try http.listenAndServe(
            allocator,
            try std.net.Address.parseIp("127.0.0.1", 8080),
            &context,
            comptime http.router.Router(*Context, &.{
                builder.get("/", index),
                builder.get("/capy.js", indexJs),
                builder.get("/zig-app.wasm", wasmFile),
            }),
        );
    }

    fn index(context: *Context, response: *http.Response, request: http.Request) !void {
        const allocator = request.arena;
        const buildRoot = context.builder.build_root;
        const file = try std.fs.cwd().openFile(try std.fs.path.join(allocator, &.{ buildRoot, "src/backends/wasm/index.html" }), .{});
        defer file.close();
        const text = try file.readToEndAlloc(allocator, std.math.maxInt(usize));

        try response.headers.put("Content-Type", "text/html");
        try response.writer().writeAll(text);
    }

    fn indexJs(context: *Context, response: *http.Response, request: http.Request) !void {
        const allocator = request.arena;
        const buildRoot = context.builder.build_root;
        const file = try std.fs.cwd().openFile(try std.fs.path.join(allocator, &.{ buildRoot, "src/backends/wasm/capy.js" }), .{});
        defer file.close();
        const text = try file.readToEndAlloc(allocator, std.math.maxInt(usize));

        try response.headers.put("Content-Type", "application/javascript");
        try response.writer().writeAll(text);
    }

    fn wasmFile(context: *Context, response: *http.Response, request: http.Request) !void {
        const allocator = request.arena;
        const path = context.exe.getOutputSource().getPath(context.builder);
        const file = try std.fs.cwd().openFile(path, .{});
        defer file.close();
        const text = try file.readToEndAlloc(allocator, std.math.maxInt(usize));

        try response.headers.put("Content-Type", "application/wasm");
        try response.writer().writeAll(text);
    }
};

pub fn build(b: *std.Build) !void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    var examplesDir = try std.fs.cwd().openIterableDir("examples", .{});
    defer examplesDir.close();

    const broken = switch (target.getOsTag()) {
        .windows => &[_][]const u8{ "osm-viewer", "fade" },
        else => &[_][]const u8{"osm-viewer"},
    };

    var walker = try examplesDir.walk(b.allocator);
    defer walker.deinit();
    while (try walker.next()) |entry| {
        if (entry.kind == .File and std.mem.eql(u8, std.fs.path.extension(entry.path), ".zig")) {
            const name = try std.mem.replaceOwned(u8, b.allocator, entry.path[0 .. entry.path.len - 4], std.fs.path.sep_str, "-");
            defer b.allocator.free(name);

            // it is not freed as the path is used later for building
            const programPath = FileSource.relative(b.pathJoin(&.{ "examples", entry.path }));

            const exe: *std.build.LibExeObjStep = if (target.toTarget().isWasm())
                b.addSharedLibrary(.{ .name = name, .root_source_file = programPath, .target = target, .optimize = optimize })
            else
                b.addExecutable(.{ .name = name, .root_source_file = programPath, .target = target, .optimize = optimize });
            try install(exe, .{});

            const install_step = b.addInstallArtifact(exe);
            const working = blk: {
                for (broken) |broken_name| {
                    if (std.mem.eql(u8, name, broken_name))
                        break :blk false;
                }
                break :blk true;
            };
            if (working) {
                b.getInstallStep().dependOn(&install_step.step);
            } else {
                std.log.warn("'{s}' is broken (disabled by default)", .{name});
            }

            if (target.toTarget().isWasm()) {
                if (@import("builtin").zig_backend != .stage2_llvm) {
                    const serve = WebServerStep.create(b, exe);
                    serve.step.dependOn(&exe.install_step.?.step);
                    const serve_step = b.step(name, "Start a web server to run this example");
                    serve_step.dependOn(&serve.step);
                }
            } else {
                const run_cmd = exe.run();
                run_cmd.step.dependOn(&exe.install_step.?.step);
                if (b.args) |args| {
                    run_cmd.addArgs(args);
                }

                const run_step = b.step(name, "Run this example");
                run_step.dependOn(&run_cmd.step);
            }
        }
    }

    const lib = b.addSharedLibrary(.{
        .name = "capy",
        .root_source_file = FileSource.relative("src/c_api.zig"),
        .version = std.builtin.Version{ .major = 0, .minor = 3, .patch = 0 },
        .target = target,
        .optimize = optimize,
    });
    lib.linkLibC();
    try install(lib, .{});
    // lib.emit_h = true;
    lib.install();

    const sharedlib_install_step = b.addInstallArtifact(lib);
    b.getInstallStep().dependOn(&sharedlib_install_step.step);

    const buildc_step = b.step("shared", "Build capy as a shared library (with C ABI)");
    buildc_step.dependOn(&lib.install_step.?.step);

    const tests = b.addTest(.{
        .root_source_file = FileSource.relative("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });
    // tests.emit_docs = .emit;
    try install(tests, .{});

    const test_step = b.step("test", "Run unit tests and also generate the documentation");
    test_step.dependOn(&tests.step);

    // const coverage_tests = b.addTest("src/main.zig");
    // coverage_tests.setTarget(target);
    // coverage_tests.setBuildMode(mode);
    // coverage_tests.exec_cmd_args = &.{ "kcov", "--clean", "--include-pattern=src/", "kcov-output", null };
    // try install(coverage_tests, .{});

    // const cov_step = b.step("coverage", "Perform code coverage of unit tests. This requires 'kcov' to be installed.");
    // cov_step.dependOn(&coverage_tests.step);
}
