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
            step.linkSystemLibrary("comctl32");
            switch (step.target.toTarget().cpu.arch) {
                .x86_64 => step.addObjectFile("src/backends/win32/res/x86_64.o"),
                //.i386 => step.addObjectFile("src/backends/win32/res/i386.o"), // currently disabled due to problems with safe SEH
                else => {} // not much of a problem as it'll just lack styling
            }
        },
        else => {
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

    const exe = b.addExecutable("example", "examples/7gui/counter.zig");
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
