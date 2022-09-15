const PixelFormat = @import("../../src/pixel_format.zig").PixelFormat;
const assert = std.debug.assert;
const qoi = @import("../../src/formats/qoi.zig");
const color = @import("../../src/color.zig");
const ImageReadError = Image.ReadError;
const std = @import("std");
const testing = std.testing;
const Image = @import("../../src/Image.zig");
const helpers = @import("../helpers.zig");

const zero_raw_file = helpers.fixtures_path ++ "qoi/zero.raw";
const zero_qoi_file = helpers.fixtures_path ++ "qoi/zero.qoi";

test "Should error on non QOI images" {
    const file = try helpers.testOpenFile(helpers.fixtures_path ++ "bmp/simple_v4.bmp");
    defer file.close();

    var stream_source = std.io.StreamSource{ .file = file };

    var qoi_file = qoi.QOI{};

    const invalid_file = qoi_file.read(helpers.zigimg_test_allocator, &stream_source);

    try helpers.expectError(invalid_file, ImageReadError.InvalidData);
}

test "Read zero.qoi file" {
    const file = try helpers.testOpenFile(zero_qoi_file);
    defer file.close();

    var stream_source = std.io.StreamSource{ .file = file };

    var qoi_file = qoi.QOI{};

    const pixels = try qoi_file.read(helpers.zigimg_test_allocator, &stream_source);
    defer pixels.deinit(helpers.zigimg_test_allocator);

    try helpers.expectEq(qoi_file.width(), 512);
    try helpers.expectEq(qoi_file.height(), 512);
    try helpers.expectEq(try qoi_file.pixelFormat(), .rgba32);
    try testing.expect(qoi_file.header.colorspace == .srgb);

    try testing.expect(pixels == .rgba32);

    var buffer: [1025 * 1024]u8 = undefined;
    var zero_raw_pixels = try helpers.testReadFile(zero_raw_file, buffer[0..]);
    try testing.expectEqualSlices(u8, zero_raw_pixels, std.mem.sliceAsBytes(pixels.rgba32));
}

test "Write qoi file" {
    var source_image = try Image.create(helpers.zigimg_test_allocator, 512, 512, PixelFormat.rgba32);
    defer source_image.deinit();

    var buffer: [1025 * 1024]u8 = undefined;
    var zero_raw_pixels = try helpers.testReadFile(zero_raw_file, buffer[0..]);
    std.mem.copy(u8, std.mem.sliceAsBytes(source_image.pixels.rgba32), std.mem.bytesAsSlice(u8, zero_raw_pixels));

    var image_buffer: [100 * 1024]u8 = undefined;
    var zero_qoi = try helpers.testReadFile(zero_qoi_file, buffer[0..]);

    const result_image = try source_image.writeToMemory(image_buffer[0..], Image.EncoderOptions{ .qoi = .{} });

    try testing.expectEqualSlices(u8, zero_qoi[0..], result_image);
}
