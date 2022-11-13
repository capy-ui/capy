const std = @import("std");
pub const zig_libressl = @import("zig-libressl/build.zig");
const Pkg = std.build.Pkg;

fn relativeToThis(comptime path: []const u8) []const u8 {
    comptime {
        return std.fs.path.dirname(@src().file).? ++ std.fs.path.sep_str ++ path;
    }
}

pub const pkgs = struct {
    pub const hzzp = Pkg{
        .name = "hzzp",
        .source = std.build.FileSource{ .path = relativeToThis("hzzp/src/main.zig") },
    };

    pub const zuri = Pkg{
        .name = "zuri",
        .source = std.build.FileSource{ .path = relativeToThis("zuri/src/zuri.zig") },
    };

    pub const libressl = Pkg{
        .name = "zig-libressl",
        .source = std.build.FileSource{ .path = relativeToThis("zig-libressl/src/main.zig") },
    };

    pub const zelda = Pkg{
        .name = "zelda",
        .source = .{ .path = relativeToThis("src/main.zig") },
        .dependencies = &[_]Pkg{
            hzzp, zuri, libressl,
        },
    };
};

pub fn link(
    b: *std.build.Builder,
    exe: *std.build.LibExeObjStep,
    target: std.zig.CrossTarget,
    mode: std.builtin.Mode,
    use_system_libressl: bool,
) !void {
    exe.addPackage(pkgs.zelda);
    try zig_libressl.useLibreSslForStep(b, target, mode, relativeToThis("zig-libressl/libressl"), exe, use_system_libressl);
}

pub fn build(b: *std.build.Builder) !void {
    const use_system_libressl = b.option(bool, "use-system-libressl", "Link and build from the system installed copy of LibreSSL instead of building it from source") orelse false;

    const mode = b.standardReleaseOptions();
    const target = b.standardTargetOptions(.{});

    const test_step = b.step("test", "Run library tests.");
    const maybe_test_filter = b.option([]const u8, "test-filter", "Test filter");
    const sanitize_thread = b.option(bool, "sanitize-thread", "Enable ThreadSanitizer") orelse false;

    const create_test_step = b.addTest("src/tests.zig");
    create_test_step.linkLibC();
    create_test_step.sanitize_thread = sanitize_thread;
    create_test_step.setTarget(target);
    create_test_step.setBuildMode(mode);
    try link(b, create_test_step, target, .ReleaseFast, use_system_libressl);

    if (maybe_test_filter) |test_filter| {
        create_test_step.setFilter(test_filter);
    }

    test_step.dependOn(&create_test_step.step);
}
