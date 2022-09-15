const std = @import("std");
const testing = std.testing;
const Image = @import("../src/Image.zig");

pub const zigimg_test_allocator = std.testing.allocator;
pub const fixtures_path = "../test-suite/fixtures/";

pub const TestInput = struct {
    x: u32 = 0,
    y: u32 = 0,
    hex: u32 = 0,
};

pub fn expectEq(actual: anytype, expected: anytype) !void {
    try testing.expectEqual(@as(@TypeOf(actual), expected), actual);
}

pub fn expectEqSlice(comptime T: type, actual: []const T, expected: []const T) !void {
    try testing.expectEqualSlices(T, expected, actual);
}

pub fn expectError(actual: anytype, expected: anyerror) !void {
    try testing.expectError(expected, actual);
}

pub fn testOpenFile(file_path: []const u8) !std.fs.File {
    return std.fs.cwd().openFile(file_path, .{}) catch |err|
        if (err == error.FileNotFound) return error.SkipZigTest else return err;
}

pub fn testImageFromFile(image_path: []const u8) !Image {
    return Image.fromFilePath(zigimg_test_allocator, image_path) catch |err|
        if (err == error.FileNotFound) return error.SkipZigTest else return err;
}

pub fn testReadFile(file_path: []const u8, buffer: []u8) ![]u8 {
    return std.fs.cwd().readFile(file_path, buffer) catch |err|
        if (err == error.FileNotFound) return error.SkipZigTest else return err;
}
