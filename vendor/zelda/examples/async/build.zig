const std = @import("std");
const zig_libressl = @import("zig-libressl-build.zig");
const Pkg = std.build.Pkg;

pub const pkgs = struct {
    pub const hzzp = Pkg{
        .name = "hzzp",
        .source = std.build.FileSource.relative("../../hzzp/src/main.zig"),
    };

    pub const zuri = Pkg{
        .name = "zuri",
        .source = std.build.FileSource.relative("../../zuri/src/zuri.zig"),
    };

    pub const libressl = Pkg{
        .name = "zig-libressl",
        .source = std.build.FileSource.relative("../../zig-libressl/src/main.zig"),
    };

    pub const zelda = Pkg{
        .name = "zelda",
        .source = .{ .path = "../../src/main.zig" },
        .dependencies = &[_]Pkg{
            hzzp, zuri, libressl,
        },
    };
};

pub fn build(b: *std.build.Builder) !void {
    const use_system_libressl = b.option(bool, "use-system-libressl", "Link and build from the system installed copy of LibreSSL instead of building it from source") orelse false;

    // Standard target options allows the person running `zig build` to choose
    // what target to build for. Here we do not override the defaults, which
    // means any target is allowed, and the default is native. Other options
    // for restricting supported target set are available.
    const target = b.standardTargetOptions(.{});

    // Standard release options allow the person running `zig build` to select
    // between Debug, ReleaseSafe, ReleaseFast, and ReleaseSmall.
    const mode = b.standardReleaseOptions();

    const exe = b.addExecutable("async_zelda", "src/main.zig");
    exe.linkLibC();
    exe.addPackage(pkgs.zelda);
    exe.setTarget(target);
    exe.setBuildMode(mode);
    exe.install();
    try zig_libressl.useLibreSslForStep(b, target, mode, "libressl", exe, use_system_libressl);

    const run_cmd = exe.run();
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);
}
