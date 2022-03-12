const std = @import("std");
const http = @import("deps.zig").imports.apple_pie;

pub fn install(step: *std.build.LibExeObjStep, comptime prefix: []const u8) !void {
    step.subsystem = .Native;
    // step.linkSystemLibrary("glfw");
    // step.linkSystemLibrary("GLESv2");

    switch (step.target.getOsTag()) {
        .linux, .freebsd => {
            step.linkLibC();
            step.linkSystemLibrary("gtk+-3.0");
        },
        .windows => {
            // There doesn't seem to be a way to link to a .def file so we temporarily put it in the Zig installation folder
            const libcommon = step.builder.pathJoin(&.{ std.fs.path.dirname(step.builder.zig_exe).?, "lib", "libc", "mingw", "lib-common", "gdiplus.def" });
            defer step.builder.allocator.free(libcommon);
            std.fs.accessAbsolute(libcommon, .{}) catch |err| switch (err) {
                error.FileNotFound => {
                    try std.fs.copyFileAbsolute(
                        step.builder.pathFromRoot(prefix ++ "/src/backends/win32/gdiplus.def"), libcommon, .{});
                },
                else => {}
            };

            step.subsystem = .Windows;
            step.linkSystemLibrary("comctl32");
            step.linkSystemLibrary("gdi32");
            step.linkSystemLibrary("gdiplus");
            switch (step.target.toTarget().cpu.arch) {
                .x86_64 => step.addObjectFile(prefix ++ "/src/backends/win32/res/x86_64.o"),
                //.i386 => step.addObjectFile(prefix ++ "/src/backends/win32/res/i386.o"), // currently disabled due to problems with safe SEH
                else => {}, // not much of a problem as it'll just lack styling
            }
        },
        .freestanding => {
            if (step.target.toTarget().isWasm()) {
                // supported
            } else {
                return error.UnsupportedOs;
            }
        },
        else => {
            // TODO: use the GLES backend as long as the windowing system is supported
            // but the UI library isn't
            return error.UnsupportedOs;
        },
    }

    const zgt = std.build.Pkg{ .name = "zgt", .path = std.build.FileSource.relative(prefix ++ "/src/main.zig"), .dependencies = &[_]std.build.Pkg{} };

    step.addPackage(zgt);
}

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

        var context = Context { .builder = self.builder, .exe = self.exe };
        const builder = http.router.Builder(*Context);
        std.debug.print("Web server opened at http://localhost:8080/\n", .{});
        try http.listenAndServe(
            allocator,
            try std.net.Address.parseIp("127.0.0.1", 8080),
            &context,
            comptime http.router.Router(*Context, &.{
                builder.get("/", null, index),
                builder.get("/zig-out/lib/example.wasm", null, wasmFile),
            }),
        );
    }

    fn index(context: *Context, response: *http.Response, request: http.Request, _: ?*const anyopaque) !void {
        const allocator = request.arena;
        const buildRoot = context.builder.build_root;
        const file = try std.fs.cwd().openFile(
            try std.fs.path.join(allocator, &.{ buildRoot, "page.html" }), .{});
        defer file.close();
        const text = try file.readToEndAlloc(allocator, std.math.maxInt(usize));
        
        try response.headers.put("Content-Type", "text/html");
        try response.writer().writeAll(text);
    }

    fn wasmFile(context: *Context, response: *http.Response, request: http.Request, _: ?*const anyopaque) !void {
        const allocator = request.arena;
        const path = context.exe.getOutputSource().getPath(context.builder);
        const file = try std.fs.cwd().openFile(path, .{});
        defer file.close();
        const text = try file.readToEndAlloc(allocator, std.math.maxInt(usize));
        
        try response.headers.put("Content-Type", "application/wasm");
        try response.writer().writeAll(text);
    }
};

pub fn build(b: *std.build.Builder) !void {
    const target = b.standardTargetOptions(.{});
    const mode = b.standardReleaseOptions();

    var examplesDir = try std.fs.cwd().openDir("examples", .{ .iterate = true });
    defer examplesDir.close();

    const broken = switch (target.getOsTag()) {
        .windows => &[_][]const u8{ "fade" },
        else => &[_][]const u8{},
    };

    var walker = try examplesDir.walk(b.allocator);
    defer walker.deinit();
    while (try walker.next()) |entry| {
        if (entry.kind == .File and std.mem.eql(u8, std.fs.path.extension(entry.path), ".zig")) {
            const name = try std.mem.replaceOwned(u8, b.allocator, entry.path[0 .. entry.path.len - 4], "/", "-");
            defer b.allocator.free(name);

            // it is not freed as the path is used later for building
            const programPath = b.pathJoin(&.{ "examples", entry.path });

            const exe: *std.build.LibExeObjStep = if (target.toTarget().isWasm())
                b.addSharedLibrary(name, programPath, .unversioned)
            else
                b.addExecutable(name, programPath);
            exe.setTarget(target);
            exe.setBuildMode(mode);
            try install(exe, ".");

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
                const serve = WebServerStep.create(b, exe);
                serve.step.dependOn(&exe.install_step.?.step);
                const serve_step = b.step(name, "Start a web server to run this example");
                serve_step.dependOn(&serve.step);
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

    const tests = b.addTest("src/main.zig");
    tests.setTarget(target);
    tests.setBuildMode(mode);
    // tests.emit_docs = .emit;
    try install(tests, ".");

    const test_step = b.step("test", "Run unit tests and also generate the documentation");
    test_step.dependOn(&tests.step);
}
