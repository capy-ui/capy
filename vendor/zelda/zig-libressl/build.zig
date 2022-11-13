const std = @import("std");
const out = std.log.scoped(.libressl);
const builtin = @import("builtin");

fn isProgramAvailable(builder: *std.build.Builder, program_name: []const u8) !bool {
    const env_map = try std.process.getEnvMap(builder.allocator);
    const path_var = env_map.get("PATH") orelse return false;
    var path_iter = std.mem.tokenize(u8, path_var, if (builtin.os.tag == .windows) ";" else ":");
    while (path_iter.next()) |path| {
        var dir = std.fs.cwd().openIterableDir(path, .{}) catch continue;
        defer dir.close();

        var dir_iterator = dir.iterate();
        while (try dir_iterator.next()) |dir_item| {
            if (std.mem.eql(u8, dir_item.name, program_name)) return true;
        }
    }
    return false;
}

pub fn useLibreSslForStep(
    builder: *std.build.Builder,
    target: std.zig.CrossTarget,
    mode: std.builtin.Mode,
    libressl_source_root: []const u8,
    rich_step: *std.build.LibExeObjStep,
    use_system_libressl: bool,
) !void {
    if (use_system_libressl) {
        rich_step.linkSystemLibrary("crypto");
        rich_step.linkSystemLibrary("ssl");
        rich_step.linkSystemLibrary("tls");
    } else {
        try @import("libressl/build.zig").linkStepWithLibreSsl(builder, target, mode, libressl_source_root, rich_step);
    }
}

pub fn build(b: *std.build.Builder) !void {
    const target = b.standardTargetOptions(.{});
    const mode = b.standardReleaseOptions();

    var lib = b.addStaticLibrary("zig-libressl", "src/main.zig");
    lib.linkLibC();
    lib.setBuildMode(mode);
    lib.install();

    const use_system_libressl = b.option(bool, "use-system-libressl", "Link and build from the system installed copy of LibreSSL instead of building it from source") orelse false;

    var main_tests = b.addTest("src/normal_test.zig");
    main_tests.setBuildMode(mode);
    try useLibreSslForStep(b, target, mode, "./libressl", main_tests, use_system_libressl);

    var async_tests = b.addTest("src/async_test.zig");
    async_tests.use_stage1 = true;
    async_tests.test_evented_io = true;
    async_tests.setBuildMode(mode);
    try useLibreSslForStep(b, target, mode, "./libressl", async_tests, use_system_libressl);

    const test_step = b.step("test", "Run library tests");
    test_step.dependOn(&main_tests.step);
    test_step.dependOn(&async_tests.step);
}
