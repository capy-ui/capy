const Build = @import("std").Build;

pub fn build(b: *Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    _ = b.addModule("zigimg", .{
        .source_file = .{ .path = "zigimg.zig" },
    });

    const zigimg_build_test = b.addTest(.{
        .name = "zigimgtest",
        .root_source_file = .{ .path = "zigimg.zig" },
        .target = target,
        .optimize = optimize,
    });

    b.installArtifact(zigimg_build_test);

    const run_test_cmd = b.addRunArtifact(zigimg_build_test);
    // Force running of the test command even if you don't have changes
    run_test_cmd.has_side_effects = true;
    run_test_cmd.step.dependOn(b.getInstallStep());

    const test_step = b.step("test", "Run library tests");
    test_step.dependOn(&run_test_cmd.step);

    const build_only_test_step = b.step("test_build_only", "Build the tests but does not run it");
    build_only_test_step.dependOn(&zigimg_build_test.step);
    build_only_test_step.dependOn(b.getInstallStep());
}
