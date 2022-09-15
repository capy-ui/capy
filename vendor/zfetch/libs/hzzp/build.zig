const std = @import("std");

const Builder = std.build.Builder;

pub fn build(b: *Builder) void {
    const mode = b.standardReleaseOptions();

    const lib_tests = b.addTest("src/main.zig");
    lib_tests.setBuildMode(mode);

    const tests = b.step("test", "Run all library tests");
    tests.dependOn(&lib_tests.step);
}
