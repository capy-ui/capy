const std = @import("std");

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
            step.subsystem = .Windows;
            step.linkSystemLibrary("comctl32");
            step.linkSystemLibrary("gdi32");
            switch (step.target.toTarget().cpu.arch) {
                .x86_64 => step.addObjectFile(prefix ++ "/src/backends/win32/res/x86_64.o"),
                //.i386 => step.addObjectFile(prefix ++ "/src/backends/win32/res/i386.o"), // currently disabled due to problems with safe SEH
                else => {}, // not much of a problem as it'll just lack styling
            }
        },
        .freestanding => {
            if (step.target.toTarget().cpu.arch == .wasm32) {
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

pub fn build(b: *std.build.Builder) !void {
    const target = b.standardTargetOptions(.{});
    const mode = b.standardReleaseOptions();

    var examplesDir = try std.fs.cwd().openDir("examples", .{ .iterate = true });
    defer examplesDir.close();

    var walker = try examplesDir.walk(b.allocator);
    defer walker.deinit();
    while (try walker.next()) |entry| {
        if (entry.kind == .File and std.mem.eql(u8, std.fs.path.extension(entry.path), ".zig")) {
            const name = try std.mem.replaceOwned(u8, b.allocator, entry.path[0 .. entry.path.len - 4], "/", "-");
            defer b.allocator.free(name);

            // it is not freed as the path is used later for building
            const programPath = try std.mem.concat(b.allocator, u8, &.{ "examples/", entry.path });

            const exe: *std.build.LibExeObjStep = if (target.toTarget().isWasm())
                b.addSharedLibrary(name, programPath, .unversioned)
            else
                b.addExecutable(name, programPath);
            exe.setTarget(target);
            exe.setBuildMode(mode);
            try install(exe, ".");
            exe.install();

            const run_cmd = exe.run();
            run_cmd.step.dependOn(&exe.install_step.?.step);
            if (b.args) |args| {
                run_cmd.addArgs(args);
            }

            const run_step = b.step(name, "Run this example");
            run_step.dependOn(&run_cmd.step);
        }
    }

    const tests = b.addTest("src/main.zig");
    tests.setBuildMode(mode);
    tests.emit_docs = .emit;
    try install(tests, ".");

    const test_step = b.step("test", "Run unit tests and also generate the documentation");
    test_step.dependOn(&tests.step);
}
