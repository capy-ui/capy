const std = @import("std");

pub fn install(step: *std.build.LibExeObjStep, comptime prefix: []const u8) !void {
    step.subsystem = .Native;
    // step.linkSystemLibrary("glfw");
    // step.linkSystemLibrary("GLESv2");
    
    switch (step.target.getOsTag()) {
        .linux => {
            step.linkLibC();
            step.linkSystemLibrary("gtk+-3.0");
        },
        .windows => {
            step.enable_wine = true;
            step.subsystem = .Windows;
            step.linkSystemLibrary("comctl32");
            step.linkSystemLibrary("gdi32");
            switch (step.target.toTarget().cpu.arch) {
                .x86_64 => step.addObjectFile(prefix ++ "/src/backends/win32/res/x86_64.o"),
                //.i386 => step.addObjectFile(prefix ++ "/src/backends/win32/res/i386.o"), // currently disabled due to problems with safe SEH
                else => {} // not much of a problem as it'll just lack styling
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
        }
    }

    const zgt = std.build.Pkg {
        .name = "zgt",
        .path = std.build.FileSource.relative(prefix ++ "/src/main.zig"),
        .dependencies = &[_]std.build.Pkg{}
    };

    step.addPackage(zgt);
}

pub fn build(b: *std.build.Builder) !void {
    const target = b.standardTargetOptions(.{});
    const mode = b.standardReleaseOptions();

    const examplePath = "examples/calculator.zig";
    if (target.toTarget().isWasm()) {
        const obj = b.addSharedLibrary("example", examplePath, .unversioned);
        obj.setTarget(target);
        obj.setBuildMode(mode);
        try install(obj, ".");
        obj.install();
    } else {
        const exe = b.addExecutable("example", examplePath);
        exe.setTarget(target);
        exe.setBuildMode(mode);
        try install(exe, ".");
        exe.install();

        const run_cmd = exe.run();
        run_cmd.step.dependOn(b.getInstallStep());
        if (b.args) |args| {
            run_cmd.addArgs(args);
        }

        const run_step = b.step("run", "Run the example");
        run_step.dependOn(&run_cmd.step);
    }

    const tests = b.addTest("src/main.zig");
    tests.setBuildMode(mode);
    try install(tests, ".");

    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&tests.step);
}
