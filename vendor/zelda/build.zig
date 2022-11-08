const std = @import("std");
const zig_libressl = @import("zig-libressl/build.zig");
const Pkg = std.build.Pkg;

fn relativeToThis(comptime path: []const u8) []const u8 {
    comptime {
        return std.fs.path.dirname(@src().file).? ++ "/" ++ path;
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
        .source = .{ .path = "src/main.zig" },
        .dependencies = &[_]Pkg{
            hzzp, zuri, libressl,
        },
    };
};

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
    create_test_step.addPackage(pkgs.zelda);
    try zig_libressl.useLibreSslForStep(b, target, mode, "zig-libressl/libressl", create_test_step, use_system_libressl);

    if (maybe_test_filter) |test_filter| {
        create_test_step.setFilter(test_filter);
    }

    test_step.dependOn(&create_test_step.step);
}
