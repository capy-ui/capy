const std = @import("std");
const helpers = @import("../helpers.zig");

const jpeg = @import("../../src/formats/jpeg.zig");
const color = @import("../../src/color.zig");
const Image = @import("../../src/Image.zig");
const ImageReadError = Image.ReadError;
const testing = std.testing;

test "Should error on non JPEG images" {
    const file = try helpers.testOpenFile(helpers.fixtures_path ++ "bmp/simple_v4.bmp");
    defer file.close();

    var stream_source = std.io.StreamSource{ .file = file };

    var jpeg_file = jpeg.JPEG.init(helpers.zigimg_test_allocator);
    defer jpeg_file.deinit();

    var pixelsOpt: ?color.PixelStorage = null;
    const invalidFile = jpeg_file.read(&stream_source, &pixelsOpt);
    defer {
        if (pixelsOpt) |pixels| {
            pixels.deinit(helpers.zigimg_test_allocator);
        }
    }

    try helpers.expectError(invalidFile, ImageReadError.InvalidData);
}

test "Read JFIF header properly and decode simple Huffman stream" {
    const file = try helpers.testOpenFile(helpers.fixtures_path ++ "jpeg/huff_simple0.jpg");
    defer file.close();

    var stream_source = std.io.StreamSource{ .file = file };

    var jpeg_file = jpeg.JPEG.init(helpers.zigimg_test_allocator);
    defer jpeg_file.deinit();

    var pixelsOpt: ?color.PixelStorage = null;
    const frame = try jpeg_file.read(&stream_source, &pixelsOpt);

    defer {
        if (pixelsOpt) |pixels| {
            pixels.deinit(helpers.zigimg_test_allocator);
        }
    }

    try helpers.expectEq(frame.frame_header.row_count, 8);
    try helpers.expectEq(frame.frame_header.samples_per_row, 16);
    try helpers.expectEq(frame.frame_header.sample_precision, 8);
    try helpers.expectEq(frame.frame_header.components.len, 3);

    try testing.expect(pixelsOpt != null);

    if (pixelsOpt) |pixels| {
        try testing.expect(pixels == .rgb24);
    }
}

test "Read the tuba properly" {
    const file = try helpers.testOpenFile(helpers.fixtures_path ++ "jpeg/tuba.jpg");
    defer file.close();

    var stream_source = std.io.StreamSource{ .file = file };

    var jpeg_file = jpeg.JPEG.init(helpers.zigimg_test_allocator);
    defer jpeg_file.deinit();

    var pixelsOpt: ?color.PixelStorage = null;
    const frame = try jpeg_file.read(&stream_source, &pixelsOpt);

    defer {
        if (pixelsOpt) |pixels| {
            pixels.deinit(helpers.zigimg_test_allocator);
        }
    }

    try helpers.expectEq(frame.frame_header.row_count, 512);
    try helpers.expectEq(frame.frame_header.samples_per_row, 512);
    try helpers.expectEq(frame.frame_header.sample_precision, 8);
    try helpers.expectEq(frame.frame_header.components.len, 3);

    try testing.expect(pixelsOpt != null);

    if (pixelsOpt) |pixels| {
        try testing.expect(pixels == .rgb24);

        // Just for fun, let's sample a few pixels. :^)
        try helpers.expectEq(pixels.rgb24[(126 * 512 + 163)], color.Rgb24.initRgb(0xAC, 0x78, 0x54));
        try helpers.expectEq(pixels.rgb24[(265 * 512 + 284)], color.Rgb24.initRgb(0x37, 0x30, 0x33));
        try helpers.expectEq(pixels.rgb24[(431 * 512 + 300)], color.Rgb24.initRgb(0xFE, 0xE7, 0xC9));
    }
}
