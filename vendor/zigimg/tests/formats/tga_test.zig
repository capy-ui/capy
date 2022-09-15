const PixelFormat = @import("../../src/pixel_format.zig").PixelFormat;
const assert = std.debug.assert;
const tga = @import("../../src/formats/tga.zig");
const color = @import("../../src/color.zig");
const ImageReadError = Image.ReadError;
const std = @import("std");
const testing = std.testing;
const Image = @import("../../src/Image.zig");
const helpers = @import("../helpers.zig");

test "Should error on non TGA images" {
    const file = try helpers.testOpenFile(helpers.fixtures_path ++ "bmp/simple_v4.bmp");
    defer file.close();

    var stream_source = std.io.StreamSource{ .file = file };

    var tga_file = tga.TGA{};

    const invalidFile = tga_file.read(helpers.zigimg_test_allocator, &stream_source);

    try helpers.expectError(invalidFile, ImageReadError.InvalidData);
}

test "Read ubw8 TGA file" {
    const file = try helpers.testOpenFile(helpers.fixtures_path ++ "tga/ubw8.tga");
    defer file.close();

    var stream_source = std.io.StreamSource{ .file = file };

    var tga_file = tga.TGA{};

    const pixels = try tga_file.read(helpers.zigimg_test_allocator, &stream_source);
    defer pixels.deinit(helpers.zigimg_test_allocator);

    try helpers.expectEq(tga_file.width(), 128);
    try helpers.expectEq(tga_file.height(), 128);
    try helpers.expectEq(try tga_file.pixelFormat(), .grayscale8);

    const expected_strip = [_]u8{ 76, 149, 178, 0, 76, 149, 178, 254, 76, 149, 178, 0, 76, 149, 178, 254 };

    try testing.expect(pixels == .grayscale8);

    const width = tga_file.width();
    const height = tga_file.height();

    var y: usize = 0;
    while (y < height) : (y += 1) {
        var x: usize = 0;

        const stride = y * width;

        while (x < width) : (x += 1) {
            const strip_index = x / 8;

            try helpers.expectEq(pixels.grayscale8[stride + x].value, expected_strip[strip_index]);
        }
    }
}

test "Read ucm8 TGA file" {
    const file = try helpers.testOpenFile(helpers.fixtures_path ++ "tga/ucm8.tga");
    defer file.close();

    var stream_source = std.io.StreamSource{ .file = file };

    var tga_file = tga.TGA{};

    const pixels = try tga_file.read(helpers.zigimg_test_allocator, &stream_source);
    defer pixels.deinit(helpers.zigimg_test_allocator);

    try helpers.expectEq(tga_file.width(), 128);
    try helpers.expectEq(tga_file.height(), 128);
    try helpers.expectEq(try tga_file.pixelFormat(), .indexed8);

    const expected_strip = [_]u8{ 64, 128, 192, 0, 64, 128, 192, 255, 64, 128, 192, 0, 64, 128, 192, 255 };

    try testing.expect(pixels == .indexed8);

    try helpers.expectEq(pixels.indexed8.indices.len, 128 * 128);

    try helpers.expectEq(pixels.indexed8.palette[0].toU32Rgba(), 0x000000ff);
    try helpers.expectEq(pixels.indexed8.palette[64].toU32Rgba(), 0xff0000ff);
    try helpers.expectEq(pixels.indexed8.palette[128].toU32Rgba(), 0x00ff00ff);
    try helpers.expectEq(pixels.indexed8.palette[192].toU32Rgba(), 0x0000ffff);
    try helpers.expectEq(pixels.indexed8.palette[255].toU32Rgba(), 0xffffffff);

    const width = tga_file.width();
    const height = tga_file.height();

    var y: usize = 0;
    while (y < height) : (y += 1) {
        var x: usize = 0;

        const stride = y * width;

        while (x < width) : (x += 1) {
            const strip_index = x / 8;

            try helpers.expectEq(pixels.indexed8.indices[stride + x], expected_strip[strip_index]);
        }
    }
}

test "Read utc16 TGA file" {
    const file = try helpers.testOpenFile(helpers.fixtures_path ++ "tga/utc16.tga");
    defer file.close();

    var stream_source = std.io.StreamSource{ .file = file };

    var tga_file = tga.TGA{};

    const pixels = try tga_file.read(helpers.zigimg_test_allocator, &stream_source);
    defer pixels.deinit(helpers.zigimg_test_allocator);

    try helpers.expectEq(tga_file.width(), 128);
    try helpers.expectEq(tga_file.height(), 128);
    try helpers.expectEq(try tga_file.pixelFormat(), .rgb555);

    const expected_strip = [_]u32{ 0xff0000, 0x00ff00, 0x0000ff, 0x000000, 0xff0000, 0x00ff00, 0x0000ff, 0xffffff, 0xff0000, 0x00ff00, 0x0000ff, 0x000000, 0xff0000, 0x00ff00, 0x0000ff, 0xffffff };

    try testing.expect(pixels == .rgb555);

    try helpers.expectEq(pixels.rgb555.len, 128 * 128);

    const width = tga_file.width();
    const height = tga_file.height();

    var y: usize = 0;
    while (y < height) : (y += 1) {
        var x: usize = 0;

        const stride = y * width;

        while (x < width) : (x += 1) {
            const strip_index = x / 8;

            try helpers.expectEq(pixels.rgb555[stride + x].toU32Rgb(), expected_strip[strip_index]);
        }
    }
}

test "Read utc24 TGA file" {
    const file = try helpers.testOpenFile(helpers.fixtures_path ++ "tga/utc24.tga");
    defer file.close();

    var stream_source = std.io.StreamSource{ .file = file };

    var tga_file = tga.TGA{};

    const pixels = try tga_file.read(helpers.zigimg_test_allocator, &stream_source);
    defer pixels.deinit(helpers.zigimg_test_allocator);

    try helpers.expectEq(tga_file.width(), 128);
    try helpers.expectEq(tga_file.height(), 128);
    try helpers.expectEq(try tga_file.pixelFormat(), .rgb24);

    const expected_strip = [_]u32{ 0xff0000, 0x00ff00, 0x0000ff, 0x000000, 0xff0000, 0x00ff00, 0x0000ff, 0xffffff, 0xff0000, 0x00ff00, 0x0000ff, 0x000000, 0xff0000, 0x00ff00, 0x0000ff, 0xffffff };

    try testing.expect(pixels == .rgb24);

    try helpers.expectEq(pixels.rgb24.len, 128 * 128);

    const width = tga_file.width();
    const height = tga_file.height();

    var y: usize = 0;
    while (y < height) : (y += 1) {
        var x: usize = 0;

        const stride = y * width;

        while (x < width) : (x += 1) {
            const strip_index = x / 8;

            try helpers.expectEq(pixels.rgb24[stride + x].toU32Rgb(), expected_strip[strip_index]);
        }
    }
}

test "Read utc32 TGA file" {
    const file = try helpers.testOpenFile(helpers.fixtures_path ++ "tga/utc32.tga");
    defer file.close();

    var stream_source = std.io.StreamSource{ .file = file };

    var tga_file = tga.TGA{};

    const pixels = try tga_file.read(helpers.zigimg_test_allocator, &stream_source);
    defer pixels.deinit(helpers.zigimg_test_allocator);

    try helpers.expectEq(tga_file.width(), 128);
    try helpers.expectEq(tga_file.height(), 128);
    try helpers.expectEq(try tga_file.pixelFormat(), .rgba32);

    const expected_strip = [_]u32{ 0xff0000, 0x00ff00, 0x0000ff, 0x000000, 0xff0000, 0x00ff00, 0x0000ff, 0xffffff, 0xff0000, 0x00ff00, 0x0000ff, 0x000000, 0xff0000, 0x00ff00, 0x0000ff, 0xffffff };

    try testing.expect(pixels == .rgba32);

    try helpers.expectEq(pixels.rgba32.len, 128 * 128);

    const width = tga_file.width();
    const height = tga_file.height();

    var y: usize = 0;
    while (y < height) : (y += 1) {
        var x: usize = 0;

        const stride = y * width;

        while (x < width) : (x += 1) {
            const strip_index = x / 8;

            try helpers.expectEq(pixels.rgba32[stride + x].toU32Rgba(), expected_strip[strip_index] << 8 | 0xff);
        }
    }
}

test "Read cbw8 TGA file" {
    const file = try helpers.testOpenFile(helpers.fixtures_path ++ "tga/cbw8.tga");
    defer file.close();

    var stream_source = std.io.StreamSource{ .file = file };

    var tga_file = tga.TGA{};

    const pixels = try tga_file.read(helpers.zigimg_test_allocator, &stream_source);
    defer pixels.deinit(helpers.zigimg_test_allocator);

    try helpers.expectEq(tga_file.width(), 128);
    try helpers.expectEq(tga_file.height(), 128);
    try helpers.expectEq(try tga_file.pixelFormat(), .grayscale8);

    const expected_strip = [_]u8{ 76, 149, 178, 0, 76, 149, 178, 254, 76, 149, 178, 0, 76, 149, 178, 254 };

    try testing.expect(pixels == .grayscale8);

    const width = tga_file.width();
    const height = tga_file.height();

    var y: usize = 0;
    while (y < height) : (y += 1) {
        var x: usize = 0;

        const stride = y * width;

        while (x < width) : (x += 1) {
            const strip_index = x / 8;

            try helpers.expectEq(pixels.grayscale8[stride + x].value, expected_strip[strip_index]);
        }
    }
}

test "Read ccm8 TGA file" {
    const file = try helpers.testOpenFile(helpers.fixtures_path ++ "tga/ccm8.tga");
    defer file.close();

    var stream_source = std.io.StreamSource{ .file = file };

    var tga_file = tga.TGA{};

    const pixels = try tga_file.read(helpers.zigimg_test_allocator, &stream_source);
    defer pixels.deinit(helpers.zigimg_test_allocator);

    try helpers.expectEq(tga_file.width(), 128);
    try helpers.expectEq(tga_file.height(), 128);
    try helpers.expectEq(try tga_file.pixelFormat(), .indexed8);

    const expected_strip = [_]u8{ 64, 128, 192, 0, 64, 128, 192, 255, 64, 128, 192, 0, 64, 128, 192, 255 };

    try testing.expect(pixels == .indexed8);

    try helpers.expectEq(pixels.indexed8.indices.len, 128 * 128);

    try helpers.expectEq(pixels.indexed8.palette[0].toU32Rgba(), 0x000000ff);
    try helpers.expectEq(pixels.indexed8.palette[64].toU32Rgba(), 0xff0000ff);
    try helpers.expectEq(pixels.indexed8.palette[128].toU32Rgba(), 0x00ff00ff);
    try helpers.expectEq(pixels.indexed8.palette[192].toU32Rgba(), 0x0000ffff);
    try helpers.expectEq(pixels.indexed8.palette[255].toU32Rgba(), 0xffffffff);

    const width = tga_file.width();
    const height = tga_file.height();

    var y: usize = 0;
    while (y < height) : (y += 1) {
        var x: usize = 0;

        const stride = y * width;

        while (x < width) : (x += 1) {
            const strip_index = x / 8;

            try helpers.expectEq(pixels.indexed8.indices[stride + x], expected_strip[strip_index]);
        }
    }
}

test "Read ctc24 TGA file" {
    const file = try helpers.testOpenFile(helpers.fixtures_path ++ "tga/ctc24.tga");
    defer file.close();

    var stream_source = std.io.StreamSource{ .file = file };

    var tga_file = tga.TGA{};

    const pixels = try tga_file.read(helpers.zigimg_test_allocator, &stream_source);
    defer pixels.deinit(helpers.zigimg_test_allocator);

    try helpers.expectEq(tga_file.width(), 128);
    try helpers.expectEq(tga_file.height(), 128);
    try helpers.expectEq(try tga_file.pixelFormat(), .rgb24);

    const expected_strip = [_]u32{ 0xff0000, 0x00ff00, 0x0000ff, 0x000000, 0xff0000, 0x00ff00, 0x0000ff, 0xffffff, 0xff0000, 0x00ff00, 0x0000ff, 0x000000, 0xff0000, 0x00ff00, 0x0000ff, 0xffffff };

    try testing.expect(pixels == .rgb24);

    try helpers.expectEq(pixels.rgb24.len, 128 * 128);

    const width = tga_file.width();
    const height = tga_file.height();

    var y: usize = 0;
    while (y < height) : (y += 1) {
        var x: usize = 0;

        const stride = y * width;

        while (x < width) : (x += 1) {
            const strip_index = x / 8;

            try helpers.expectEq(pixels.rgb24[stride + x].toU32Rgb(), expected_strip[strip_index]);
        }
    }
}

test "Read matte-01 TGA file" {
    const file = try helpers.testOpenFile(helpers.fixtures_path ++ "tga/matte-01.tga");
    defer file.close();

    var stream_source = std.io.StreamSource{ .file = file };

    var tga_file = tga.TGA{};

    const pixels = try tga_file.read(helpers.zigimg_test_allocator, &stream_source);
    defer pixels.deinit(helpers.zigimg_test_allocator);

    try helpers.expectEq(tga_file.width(), 1280);
    try helpers.expectEq(tga_file.height(), 720);
    try helpers.expectEq(try tga_file.pixelFormat(), .rgba32);

    try testing.expect(pixels == .rgba32);

    try helpers.expectEq(pixels.rgba32.len, 1280 * 720);

    const test_inputs = [_]helpers.TestInput{
        .{
            .x = 0,
            .y = 0,
            .hex = 0x3b5f38ff,
        },
        .{
            .x = 608,
            .y = 357,
            .hex = 0x8e6c57ff,
        },
        .{
            .x = 972,
            .y = 679,
            .hex = 0xa46c41ff,
        },
    };

    for (test_inputs) |input| {
        const index = tga_file.header.width * input.y + input.x;

        try helpers.expectEq(pixels.rgba32[index].toU32Rgba(), input.hex);
    }
}

test "Read font TGA file" {
    const file = try helpers.testOpenFile(helpers.fixtures_path ++ "tga/font.tga");
    defer file.close();

    var stream_source = std.io.StreamSource{ .file = file };

    var tga_file = tga.TGA{};

    const pixels = try tga_file.read(helpers.zigimg_test_allocator, &stream_source);
    defer pixels.deinit(helpers.zigimg_test_allocator);

    try helpers.expectEq(tga_file.width(), 192);
    try helpers.expectEq(tga_file.height(), 256);
    try helpers.expectEq(try tga_file.pixelFormat(), .rgba32);

    try testing.expect(pixels == .rgba32);

    try helpers.expectEq(pixels.rgba32.len, 192 * 256);

    const width = tga_file.width();

    try helpers.expectEq(pixels.rgba32[64 * width + 16].toColorf32().toRgba32(), color.Rgba32.initRgba(0, 0, 0, 0));
    try helpers.expectEq(pixels.rgba32[64 * width + 17].toColorf32().toRgba32(), color.Rgba32.initRgba(209, 209, 209, 255));
    try helpers.expectEq(pixels.rgba32[65 * width + 17].toColorf32().toRgba32(), color.Rgba32.initRgba(255, 255, 255, 255));
}
