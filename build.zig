const std = @import("std");
pub const install = @import("build_capy.zig").install;
pub const CapyBuildOptions = @import("build_capy.zig").CapyBuildOptions;
const FileSource = std.build.FileSource;

pub fn build(b: *std.Build) !void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    var examplesDir = try if (@hasField(std.fs.Dir.OpenDirOptions,"iterate")) std.fs.cwd().openDir("examples",.{ .iterate = true }) else std.fs.cwd().openIterableDir("examples",.{}); // support zig 0.11 as well as current master
    defer examplesDir.close();

    const broken = switch (target.getOsTag()) {
        .windows => &[_][]const u8{ "osm-viewer", "fade", "slide-viewer", "demo", "notepad", "dev-tools", "many-counters" },
        else => &[_][]const u8{"many-counters"},
    };

    var walker = try examplesDir.walk(b.allocator);
    defer walker.deinit();
    while (try walker.next()) |entry| {
        if (entry.kind == .file and std.mem.eql(u8, std.fs.path.extension(entry.path), ".zig")) {
            const name = try std.mem.replaceOwned(u8, b.allocator, entry.path[0 .. entry.path.len - 4], std.fs.path.sep_str, "-");
            defer b.allocator.free(name);

            // it is not freed as the path is used later for building
            const programPath = FileSource.relative(b.pathJoin(&.{ "examples", entry.path }));

            const exe: *std.build.LibExeObjStep = if (target.toTarget().isWasm())
                b.addSharedLibrary(.{ .name = name, .root_source_file = programPath, .target = target, .optimize = optimize })
            else
                b.addExecutable(.{ .name = name, .root_source_file = programPath, .target = target, .optimize = optimize });

            const install_step = b.addInstallArtifact(exe, .{});
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

            const run_cmd = try install(exe, .{});

            const run_step = b.step(name, "Run this example");
            run_step.dependOn(run_cmd);
        }
    }

    const lib = b.addSharedLibrary(.{
        .name = "capy",
        .root_source_file = FileSource.relative("src/c_api.zig"),
        .version = std.SemanticVersion{ .major = 0, .minor = 3, .patch = 0 },
        .target = target,
        .optimize = optimize,
    });
    lib.linkLibC();
    _ = try install(lib, .{});
    // lib.emit_h = true;
    const lib_install = b.addInstallArtifact(lib, .{});
    b.getInstallStep().dependOn(&lib_install.step);

    const buildc_step = b.step("shared", "Build capy as a shared library (with C ABI)");
    buildc_step.dependOn(&lib_install.step);

    const tests = b.addTest(.{
        .root_source_file = FileSource.relative("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });
    const run_tests = try install(tests, .{});

    const test_step = b.step("test", "Run unit tests and also generate the documentation");
    test_step.dependOn(run_tests);

    const docs = b.addTest(.{
        .root_source_file = FileSource.relative("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });
    // b.installDirectory(.{ .source_dir = docs.getEmittedDocs(), .install_dir = .{ .custom = "docs/" }, .install_subdir = "" });
    const run_docs = try install(docs, .{});

    const docs_step = b.step("docs", "Generate documentation and run unit tests");
    docs_step.dependOn(run_docs);

    const coverage_tests = b.addTest(.{
        .root_source_file = FileSource.relative("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });
    coverage_tests.setExecCmd(&.{ "kcov", "--clean", "--include-pattern=src/", "kcov-output", null });
    _ = try install(coverage_tests, .{});

    const run_coverage_tests = b.addSystemCommand(&.{ "kcov", "--clean", "--include-pattern=src/", "kcov-output" });
    run_coverage_tests.addArtifactArg(coverage_tests);

    // const run_coverage_tests = b.addRunArtifact(coverage_tests);
    // run_coverage_tests.has_side_effects = true;

    const cov_step = b.step("coverage", "Perform code coverage of unit tests. This requires 'kcov' to be installed.");
    cov_step.dependOn(&run_coverage_tests.step);
}
