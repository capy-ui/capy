const std = @import("std");

pub fn install(step: *std.build.LibExeObjStep, comptime prefix: []const u8) !void {
    step.subsystem = .Native;
    
    switch (step.target.getOsTag()) {
        .linux => {
            step.linkLibC();
            step.linkSystemLibrary("gtk+-3.0");
        },
        .windows => {
            step.enable_wine = true;
            step.subsystem = .Windows;
        },
        else => {
            return error.UnsupportedOs;
        }
    }

    const zgt = std.build.Pkg {
        .name = "zgt",
        .path = prefix ++ "/src/main.zig",
        .dependencies = &[_]std.build.Pkg{}
    };

    step.addPackage(zgt);
}

pub fn build(b: *std.build.Builder) !void {
    const target = b.standardTargetOptions(.{});
    const mode = b.standardReleaseOptions();

    const exe = b.addExecutable("example", "examples/editor.zig");
    exe.setTarget(target);
    exe.setBuildMode(mode);
    try install(exe, ".");
    exe.single_threaded = true;
    exe.install();

    const run_cmd = exe.run();
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const run_step = b.step("run", "Run the example");
    run_step.dependOn(&run_cmd.step);
}
