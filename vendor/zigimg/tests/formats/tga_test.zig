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
    try helpers.expectEq(try tga_file.pixelFormat(), .bgr24);

    const expected_strip = [_]u32{ 0xff0000, 0x00ff00, 0x0000ff, 0x000000, 0xff0000, 0x00ff00, 0x0000ff, 0xffffff, 0xff0000, 0x00ff00, 0x0000ff, 0x000000, 0xff0000, 0x00ff00, 0x0000ff, 0xffffff };

    try testing.expect(pixels == .bgr24);

    try helpers.expectEq(pixels.bgr24.len, 128 * 128);

    const width = tga_file.width();
    const height = tga_file.height();

    var y: usize = 0;
    while (y < height) : (y += 1) {
        var x: usize = 0;

        const stride = y * width;

        while (x < width) : (x += 1) {
            const strip_index = x / 8;

            try helpers.expectEq(pixels.bgr24[stride + x].toU32Rgb(), expected_strip[strip_index]);
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
    try helpers.expectEq(try tga_file.pixelFormat(), .bgra32);

    const expected_strip = [_]u32{ 0xff0000, 0x00ff00, 0x0000ff, 0x000000, 0xff0000, 0x00ff00, 0x0000ff, 0xffffff, 0xff0000, 0x00ff00, 0x0000ff, 0x000000, 0xff0000, 0x00ff00, 0x0000ff, 0xffffff };

    try testing.expect(pixels == .bgra32);

    try helpers.expectEq(pixels.bgra32.len, 128 * 128);

    const width = tga_file.width();
    const height = tga_file.height();

    var y: usize = 0;
    while (y < height) : (y += 1) {
        var x: usize = 0;

        const stride = y * width;

        while (x < width) : (x += 1) {
            const strip_index = x / 8;

            try helpers.expectEq(pixels.bgra32[stride + x].toU32Rgba(), expected_strip[strip_index] << 8 | 0xff);
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
    try helpers.expectEq(try tga_file.pixelFormat(), .bgr24);

    const expected_strip = [_]u32{ 0xff0000, 0x00ff00, 0x0000ff, 0x000000, 0xff0000, 0x00ff00, 0x0000ff, 0xffffff, 0xff0000, 0x00ff00, 0x0000ff, 0x000000, 0xff0000, 0x00ff00, 0x0000ff, 0xffffff };

    try testing.expect(pixels == .bgr24);

    try helpers.expectEq(pixels.bgr24.len, 128 * 128);

    const width = tga_file.width();
    const height = tga_file.height();

    var y: usize = 0;
    while (y < height) : (y += 1) {
        var x: usize = 0;

        const stride = y * width;

        while (x < width) : (x += 1) {
            const strip_index = x / 8;

            try helpers.expectEq(pixels.bgr24[stride + x].toU32Rgb(), expected_strip[strip_index]);
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
    try helpers.expectEq(try tga_file.pixelFormat(), .bgra32);

    try testing.expect(pixels == .bgra32);

    try helpers.expectEq(pixels.bgra32.len, 1280 * 720);

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
        const index = tga_file.header.image_spec.width * input.y + input.x;

        try helpers.expectEq(pixels.bgra32[index].toU32Rgba(), input.hex);
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
    try helpers.expectEq(try tga_file.pixelFormat(), .bgra32);

    try testing.expect(pixels == .bgra32);

    try helpers.expectEq(pixels.bgra32.len, 192 * 256);

    const width = tga_file.width();

    try helpers.expectEq(pixels.bgra32[64 * width + 16].toColorf32().toRgba32(), color.Rgba32.initRgba(0, 0, 0, 0));
    try helpers.expectEq(pixels.bgra32[64 * width + 17].toColorf32().toRgba32(), color.Rgba32.initRgba(209, 209, 209, 255));
    try helpers.expectEq(pixels.bgra32[65 * width + 17].toColorf32().toRgba32(), color.Rgba32.initRgba(255, 255, 255, 255));
}

test "Read stopsignsmall TGA v1 file" {
    const file = try helpers.testOpenFile(helpers.fixtures_path ++ "tga/stopsignsmall.tga");
    defer file.close();

    var stream_source = std.io.StreamSource{ .file = file };

    var tga_file = tga.TGA{};

    const pixels = try tga_file.read(helpers.zigimg_test_allocator, &stream_source);
    defer pixels.deinit(helpers.zigimg_test_allocator);

    try helpers.expectEq(tga_file.width(), 216);
    try helpers.expectEq(tga_file.height(), 480);
    try helpers.expectEq(try tga_file.pixelFormat(), .bgr24);

    try testing.expect(pixels == .bgr24);
    try helpers.expectEq(pixels.bgr24.len, 216 * 480);

    const width = tga_file.width();

    try helpers.expectEq(pixels.bgr24[143 * width + 93], color.Bgr24.initRgb(188, 34, 24));
    try helpers.expectEq(pixels.bgr24[479 * width + 215], color.Bgr24.initRgb(33, 29, 17));
}

test "Read stopsignsmallcompressed TGA v1 file" {
    const file = try helpers.testOpenFile(helpers.fixtures_path ++ "tga/stopsignsmallcompressed.tga");
    defer file.close();

    var stream_source = std.io.StreamSource{ .file = file };

    var tga_file = tga.TGA{};

    const pixels = try tga_file.read(helpers.zigimg_test_allocator, &stream_source);
    defer pixels.deinit(helpers.zigimg_test_allocator);

    try helpers.expectEq(tga_file.width(), 216);
    try helpers.expectEq(tga_file.height(), 480);
    try helpers.expectEq(try tga_file.pixelFormat(), .bgr24);

    try testing.expect(pixels == .bgr24);
    try helpers.expectEq(pixels.bgr24.len, 216 * 480);

    const width = tga_file.width();

    try helpers.expectEq(pixels.bgr24[143 * width + 93], color.Bgr24.initRgb(188, 34, 24));
    try helpers.expectEq(pixels.bgr24[479 * width + 215], color.Bgr24.initRgb(33, 29, 17));
}

test "Write TGA uncompressed grayscale8" {
    const image_file_name = "zigimg_tga_uncompressed_grayscale8.tga";

    var source_file = try helpers.testOpenFile(helpers.fixtures_path ++ "tga/ubw8.tga");
    defer source_file.close();

    var source_image = try Image.fromFile(helpers.zigimg_test_allocator, &source_file);
    defer source_image.deinit();

    const encoder_options = Image.EncoderOptions{
        .tga = .{
            .rle_compressed = false,
            .color_map_depth = 16,
            .top_to_bottom_image = false,
            .image_id = "Truevision(R) Sample Image",
            .author_name = "Jean Tremblay",
            .job_id = "ubw8",
            .job_time = .{
                .hours = 2,
                .minutes = 42,
                .seconds = 24,
            },
            .software_id = "zigimg test suite",
            .software_version = .{
                .number = 101,
                .letter = 'b',
            },
            .timestamp = .{
                .year = 2023,
                .month = 11,
                .day = 23,
                .hour = 9,
                .minute = 20,
                .second = 23,
            },
        },
    };

    try source_image.writeToFilePath(image_file_name, encoder_options);
    defer {
        std.fs.cwd().deleteFile(image_file_name) catch {};
    }

    const read_file = try helpers.testOpenFile(image_file_name);
    defer read_file.close();

    var stream_source = std.io.StreamSource{ .file = read_file };

    var tga_file = tga.TGA{};

    const pixels = try tga_file.read(helpers.zigimg_test_allocator, &stream_source);
    defer pixels.deinit(helpers.zigimg_test_allocator);

    try helpers.expectEq(tga_file.width(), 128);
    try helpers.expectEq(tga_file.height(), 128);
    try helpers.expectEq(try tga_file.pixelFormat(), .grayscale8);

    const expected_strip = [_]u8{ 76, 149, 178, 0, 76, 149, 178, 254, 76, 149, 178, 0, 76, 149, 178, 254 };

    try testing.expect(pixels == .grayscale8);

    try testing.expect(tga_file.extension != null);

    if (tga_file.extension) |extension| {
        try testing.expectStringStartsWith(extension.author_name[0..], encoder_options.tga.author_name);

        try testing.expectStringStartsWith(extension.software_id[0..], encoder_options.tga.software_id);
        try helpers.expectEq(extension.software_version, encoder_options.tga.software_version);

        try testing.expectStringStartsWith(extension.job_id[0..], encoder_options.tga.job_id);
        try helpers.expectEq(extension.job_time, encoder_options.tga.job_time);

        try helpers.expectEq(extension.timestamp, encoder_options.tga.timestamp);
    }

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

test "Write TGA compressed grayscale8" {
    const image_file_name = "zigimg_tga_compressed_grayscale8.tga";

    var source_file = try helpers.testOpenFile(helpers.fixtures_path ++ "tga/cbw8.tga");
    defer source_file.close();

    var source_image = try Image.fromFile(helpers.zigimg_test_allocator, &source_file);
    defer source_image.deinit();

    try source_image.writeToFilePath(image_file_name, Image.EncoderOptions{
        .tga = .{
            .rle_compressed = true,
            .color_map_depth = 16,
            .top_to_bottom_image = false,
            .image_id = "Truevision(R) Sample Image",
        },
    });
    defer {
        std.fs.cwd().deleteFile(image_file_name) catch {};
    }

    const read_file = try helpers.testOpenFile(image_file_name);
    defer read_file.close();

    var stream_source = std.io.StreamSource{ .file = read_file };

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

test "Write uncompressed indexed8 (color map 16-bit)" {
    const image_file_name = "zigimg_tga_uncompressed_indexed8.tga";

    var source_file = try helpers.testOpenFile(helpers.fixtures_path ++ "tga/ucm8.tga");
    defer source_file.close();

    var source_image = try Image.fromFile(helpers.zigimg_test_allocator, &source_file);
    defer source_image.deinit();

    try source_image.writeToFilePath(image_file_name, Image.EncoderOptions{
        .tga = .{
            .rle_compressed = false,
            .color_map_depth = 16,
            .top_to_bottom_image = false,
            .image_id = "Truevision(R) Sample Image",
        },
    });
    defer {
        std.fs.cwd().deleteFile(image_file_name) catch {};
    }

    const read_file = try helpers.testOpenFile(image_file_name);
    defer read_file.close();

    var stream_source = std.io.StreamSource{ .file = read_file };

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

test "Write uncompressed indexed8 (color map 24-bit)" {
    const image_file_name = "zigimg_tga_uncompressed_indexed8.tga";

    var source_file = try helpers.testOpenFile(helpers.fixtures_path ++ "tga/ucm8.tga");
    defer source_file.close();

    var source_image = try Image.fromFile(helpers.zigimg_test_allocator, &source_file);
    defer source_image.deinit();

    try source_image.writeToFilePath(image_file_name, Image.EncoderOptions{
        .tga = .{
            .rle_compressed = false,
            .color_map_depth = 24,
            .top_to_bottom_image = false,
            .image_id = "Truevision(R) Sample Image",
        },
    });
    defer {
        std.fs.cwd().deleteFile(image_file_name) catch {};
    }

    const read_file = try helpers.testOpenFile(image_file_name);
    defer read_file.close();

    var stream_source = std.io.StreamSource{ .file = read_file };

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

test "Write compressed indexed8 (color map 16-bit)" {
    const image_file_name = "zigimg_tga_compressed_indexed8.tga";

    var source_file = try helpers.testOpenFile(helpers.fixtures_path ++ "tga/ccm8.tga");
    defer source_file.close();

    var source_image = try Image.fromFile(helpers.zigimg_test_allocator, &source_file);
    defer source_image.deinit();

    try source_image.writeToFilePath(image_file_name, Image.EncoderOptions{
        .tga = .{
            .rle_compressed = true,
            .color_map_depth = 16,
            .top_to_bottom_image = false,
            .image_id = "Truevision(R) Sample Image",
        },
    });
    defer {
        std.fs.cwd().deleteFile(image_file_name) catch {};
    }

    const read_file = try helpers.testOpenFile(image_file_name);
    defer read_file.close();

    var stream_source = std.io.StreamSource{ .file = read_file };

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

test "Write compressed indexed8 (color map 24-bit)" {
    const image_file_name = "zigimg_tga_compressed_indexed8.tga";

    var source_file = try helpers.testOpenFile(helpers.fixtures_path ++ "tga/ccm8.tga");
    defer source_file.close();

    var source_image = try Image.fromFile(helpers.zigimg_test_allocator, &source_file);
    defer source_image.deinit();

    try source_image.writeToFilePath(image_file_name, Image.EncoderOptions{
        .tga = .{
            .rle_compressed = true,
            .color_map_depth = 24,
            .top_to_bottom_image = true,
            .image_id = "Truevision(R) Sample Image",
        },
    });
    defer {
        std.fs.cwd().deleteFile(image_file_name) catch {};
    }

    const read_file = try helpers.testOpenFile(image_file_name);
    defer read_file.close();

    var stream_source = std.io.StreamSource{ .file = read_file };

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

test "Write uncompressed 16-bit true color TGA" {
    const image_file_name = "zigimg_tga_uncompressed_true_color_16.tga";

    var source_file = try helpers.testOpenFile(helpers.fixtures_path ++ "tga/utc16.tga");
    defer source_file.close();

    var source_image = try Image.fromFile(helpers.zigimg_test_allocator, &source_file);
    defer source_image.deinit();

    try source_image.writeToFilePath(image_file_name, Image.EncoderOptions{
        .tga = .{
            .rle_compressed = false,
            .color_map_depth = 16,
            .top_to_bottom_image = true,
            .image_id = "Truevision(R) Sample Image",
        },
    });
    defer {
        std.fs.cwd().deleteFile(image_file_name) catch {};
    }

    const read_file = try helpers.testOpenFile(image_file_name);
    defer read_file.close();

    var stream_source = std.io.StreamSource{ .file = read_file };

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

test "Write compressed 16-bit true color TGA" {
    const image_file_name = "zigimg_tga_compressed_true_color_16.tga";

    var source_file = try helpers.testOpenFile(helpers.fixtures_path ++ "tga/utc16.tga");
    defer source_file.close();

    var source_image = try Image.fromFile(helpers.zigimg_test_allocator, &source_file);
    defer source_image.deinit();

    try source_image.writeToFilePath(image_file_name, Image.EncoderOptions{
        .tga = .{
            .rle_compressed = true,
            .color_map_depth = 16,
            .top_to_bottom_image = true,
            .image_id = "Truevision(R) Sample Image",
        },
    });
    defer {
        std.fs.cwd().deleteFile(image_file_name) catch {};
    }

    const read_file = try helpers.testOpenFile(image_file_name);
    defer read_file.close();

    var stream_source = std.io.StreamSource{ .file = read_file };

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

test "Write uncompressed 24-bit true color TGA" {
    const image_file_name = "zigimg_tga_uncompressed_true_color_24.tga";

    var source_file = try helpers.testOpenFile(helpers.fixtures_path ++ "tga/utc24.tga");
    defer source_file.close();

    var source_image = try Image.fromFile(helpers.zigimg_test_allocator, &source_file);
    defer source_image.deinit();

    try source_image.writeToFilePath(image_file_name, Image.EncoderOptions{
        .tga = .{
            .rle_compressed = false,
            .color_map_depth = 24,
            .top_to_bottom_image = true,
            .image_id = "Truevision(R) Sample Image",
        },
    });
    defer {
        std.fs.cwd().deleteFile(image_file_name) catch {};
    }

    const read_file = try helpers.testOpenFile(image_file_name);
    defer read_file.close();

    var stream_source = std.io.StreamSource{ .file = read_file };

    var tga_file = tga.TGA{};

    const pixels = try tga_file.read(helpers.zigimg_test_allocator, &stream_source);
    defer pixels.deinit(helpers.zigimg_test_allocator);

    try helpers.expectEq(tga_file.width(), 128);
    try helpers.expectEq(tga_file.height(), 128);
    try helpers.expectEq(try tga_file.pixelFormat(), .bgr24);

    const expected_strip = [_]u32{ 0xff0000, 0x00ff00, 0x0000ff, 0x000000, 0xff0000, 0x00ff00, 0x0000ff, 0xffffff, 0xff0000, 0x00ff00, 0x0000ff, 0x000000, 0xff0000, 0x00ff00, 0x0000ff, 0xffffff };

    try testing.expect(pixels == .bgr24);

    try helpers.expectEq(pixels.bgr24.len, 128 * 128);

    const width = tga_file.width();
    const height = tga_file.height();

    var y: usize = 0;
    while (y < height) : (y += 1) {
        var x: usize = 0;

        const stride = y * width;

        while (x < width) : (x += 1) {
            const strip_index = x / 8;

            try helpers.expectEq(pixels.bgr24[stride + x].toU32Rgb(), expected_strip[strip_index]);
        }
    }
}

test "Write compressed 24-bit true color TGA" {
    const image_file_name = "zigimg_tga_compressed_true_color_24.tga";

    var source_file = try helpers.testOpenFile(helpers.fixtures_path ++ "tga/ctc24.tga");
    defer source_file.close();

    var source_image = try Image.fromFile(helpers.zigimg_test_allocator, &source_file);
    defer source_image.deinit();

    try source_image.writeToFilePath(image_file_name, Image.EncoderOptions{
        .tga = .{
            .rle_compressed = true,
            .color_map_depth = 24,
            .top_to_bottom_image = true,
            .image_id = "Truevision(R) Sample Image",
        },
    });
    defer {
        std.fs.cwd().deleteFile(image_file_name) catch {};
    }

    const read_file = try helpers.testOpenFile(image_file_name);
    defer read_file.close();

    var stream_source = std.io.StreamSource{ .file = read_file };

    var tga_file = tga.TGA{};

    const pixels = try tga_file.read(helpers.zigimg_test_allocator, &stream_source);
    defer pixels.deinit(helpers.zigimg_test_allocator);

    try helpers.expectEq(tga_file.width(), 128);
    try helpers.expectEq(tga_file.height(), 128);
    try helpers.expectEq(try tga_file.pixelFormat(), .bgr24);

    const expected_strip = [_]u32{ 0xff0000, 0x00ff00, 0x0000ff, 0x000000, 0xff0000, 0x00ff00, 0x0000ff, 0xffffff, 0xff0000, 0x00ff00, 0x0000ff, 0x000000, 0xff0000, 0x00ff00, 0x0000ff, 0xffffff };

    try testing.expect(pixels == .bgr24);

    try helpers.expectEq(pixels.bgr24.len, 128 * 128);

    const width = tga_file.width();
    const height = tga_file.height();

    var y: usize = 0;
    while (y < height) : (y += 1) {
        var x: usize = 0;

        const stride = y * width;

        while (x < width) : (x += 1) {
            const strip_index = x / 8;

            try helpers.expectEq(pixels.bgr24[stride + x].toU32Rgb(), expected_strip[strip_index]);
        }
    }
}

test "Write uncompressed 32-bit true color TGA" {
    const image_file_name = "zigimg_tga_uncompressed_true_color_32.tga";

    var source_file = try helpers.testOpenFile(helpers.fixtures_path ++ "tga/utc32.tga");
    defer source_file.close();

    var source_image = try Image.fromFile(helpers.zigimg_test_allocator, &source_file);
    defer source_image.deinit();

    try source_image.writeToFilePath(image_file_name, Image.EncoderOptions{
        .tga = .{
            .rle_compressed = false,
            .color_map_depth = 24,
            .top_to_bottom_image = true,
            .image_id = "Truevision(R) Sample Image",
        },
    });
    defer {
        std.fs.cwd().deleteFile(image_file_name) catch {};
    }

    const read_file = try helpers.testOpenFile(image_file_name);
    defer read_file.close();

    var stream_source = std.io.StreamSource{ .file = read_file };

    var tga_file = tga.TGA{};

    const pixels = try tga_file.read(helpers.zigimg_test_allocator, &stream_source);
    defer pixels.deinit(helpers.zigimg_test_allocator);

    try helpers.expectEq(tga_file.width(), 128);
    try helpers.expectEq(tga_file.height(), 128);
    try helpers.expectEq(try tga_file.pixelFormat(), .bgra32);

    const expected_strip = [_]u32{ 0xff0000, 0x00ff00, 0x0000ff, 0x000000, 0xff0000, 0x00ff00, 0x0000ff, 0xffffff, 0xff0000, 0x00ff00, 0x0000ff, 0x000000, 0xff0000, 0x00ff00, 0x0000ff, 0xffffff };

    try testing.expect(pixels == .bgra32);

    try helpers.expectEq(pixels.bgra32.len, 128 * 128);

    const width = tga_file.width();
    const height = tga_file.height();

    var y: usize = 0;
    while (y < height) : (y += 1) {
        var x: usize = 0;

        const stride = y * width;

        while (x < width) : (x += 1) {
            const strip_index = x / 8;

            try helpers.expectEq(pixels.bgra32[stride + x].toU32Rgba(), expected_strip[strip_index] << 8 | 0xff);
        }
    }
}

test "Write compressed 32-bit true color TGA" {
    const image_file_name = "zigimg_tga_compressed_true_color_32.tga";

    var source_file = try helpers.testOpenFile(helpers.fixtures_path ++ "tga/ctc32.tga");
    defer source_file.close();

    var source_image = try Image.fromFile(helpers.zigimg_test_allocator, &source_file);
    defer source_image.deinit();

    try source_image.writeToFilePath(image_file_name, Image.EncoderOptions{
        .tga = .{
            .rle_compressed = true,
            .color_map_depth = 24,
            .top_to_bottom_image = true,
            .image_id = "Truevision(R) Sample Image",
        },
    });
    defer {
        std.fs.cwd().deleteFile(image_file_name) catch {};
    }

    const read_file = try helpers.testOpenFile(image_file_name);
    defer read_file.close();

    var stream_source = std.io.StreamSource{ .file = read_file };

    var tga_file = tga.TGA{};

    const pixels = try tga_file.read(helpers.zigimg_test_allocator, &stream_source);
    defer pixels.deinit(helpers.zigimg_test_allocator);

    try helpers.expectEq(tga_file.width(), 128);
    try helpers.expectEq(tga_file.height(), 128);
    try helpers.expectEq(try tga_file.pixelFormat(), .bgra32);

    const expected_strip = [_]u32{ 0xff0000, 0x00ff00, 0x0000ff, 0x000000, 0xff0000, 0x00ff00, 0x0000ff, 0xffffff, 0xff0000, 0x00ff00, 0x0000ff, 0x000000, 0xff0000, 0x00ff00, 0x0000ff, 0xffffff };

    try testing.expect(pixels == .bgra32);

    try helpers.expectEq(pixels.bgra32.len, 128 * 128);

    const width = tga_file.width();
    const height = tga_file.height();

    var y: usize = 0;
    while (y < height) : (y += 1) {
        var x: usize = 0;

        const stride = y * width;

        while (x < width) : (x += 1) {
            const strip_index = x / 8;

            try helpers.expectEq(pixels.bgra32[stride + x].toU32Rgba(), expected_strip[strip_index] << 8 | 0xff);
        }
    }
}

test "Write uncompressed Rgb24 to TGA" {
    const image_file_name = "zigimg_tga_uncompressed_rgb24.tga";

    const uncompressed_source = [_]color.Rgb24{
        .{ .r = 0xEF, .g = 0xCD, .b = 0xAB },
        .{ .r = 0xEF, .g = 0xCD, .b = 0xAB },
        .{ .r = 0xEF, .g = 0xCD, .b = 0xAB },
        .{ .r = 0xEF, .g = 0xCD, .b = 0xAB },
        .{ .r = 0xEF, .g = 0xCD, .b = 0xAB },
        .{ .r = 0xEF, .g = 0xCD, .b = 0xAB },
        .{ .r = 0xEF, .g = 0xCD, .b = 0xAB },
        .{ .r = 0xEF, .g = 0xCD, .b = 0xAB },
        .{ .r = 0x1, .g = 0x2, .b = 0x3 },
        .{ .r = 0x4, .g = 0x5, .b = 0x6 },
        .{ .r = 0x7, .g = 0x8, .b = 0x9 },
    };

    var source_image = try Image.create(helpers.zigimg_test_allocator, uncompressed_source.len, 1, .rgb24);
    defer source_image.deinit();

    @memcpy(source_image.pixels.rgb24[0..], uncompressed_source[0..]);

    try source_image.writeToFilePath(image_file_name, Image.EncoderOptions{
        .tga = .{
            .rle_compressed = false,
            .color_map_depth = 24,
            .top_to_bottom_image = true,
            .image_id = "Truevision(R) Sample Image",
        },
    });
    defer {
        std.fs.cwd().deleteFile(image_file_name) catch {};
    }

    const read_file = try helpers.testOpenFile(image_file_name);
    defer read_file.close();

    var stream_source = std.io.StreamSource{ .file = read_file };

    var tga_file = tga.TGA{};

    const pixels = try tga_file.read(helpers.zigimg_test_allocator, &stream_source);
    defer pixels.deinit(helpers.zigimg_test_allocator);

    try helpers.expectEq(tga_file.width(), uncompressed_source.len);
    try helpers.expectEq(tga_file.height(), 1);
    try helpers.expectEq(try tga_file.pixelFormat(), .bgr24);

    const image_size = source_image.width * source_image.height;

    for (0..image_size) |index| {
        try helpers.expectEq(pixels.bgr24[index].r, source_image.pixels.rgb24[index].r);
        try helpers.expectEq(pixels.bgr24[index].g, source_image.pixels.rgb24[index].g);
        try helpers.expectEq(pixels.bgr24[index].b, source_image.pixels.rgb24[index].b);
    }
}

test "Write compressed Rgb24 to TGA" {
    const image_file_name = "zigimg_tga_compressed_rgb24.tga";

    const uncompressed_source = [_]color.Rgb24{
        .{ .r = 0xEF, .g = 0xCD, .b = 0xAB },
        .{ .r = 0xEF, .g = 0xCD, .b = 0xAB },
        .{ .r = 0xEF, .g = 0xCD, .b = 0xAB },
        .{ .r = 0xEF, .g = 0xCD, .b = 0xAB },
        .{ .r = 0xEF, .g = 0xCD, .b = 0xAB },
        .{ .r = 0xEF, .g = 0xCD, .b = 0xAB },
        .{ .r = 0xEF, .g = 0xCD, .b = 0xAB },
        .{ .r = 0xEF, .g = 0xCD, .b = 0xAB },
        .{ .r = 0x1, .g = 0x2, .b = 0x3 },
        .{ .r = 0x4, .g = 0x5, .b = 0x6 },
        .{ .r = 0x7, .g = 0x8, .b = 0x9 },
    };

    var source_image = try Image.create(helpers.zigimg_test_allocator, uncompressed_source.len, 1, .rgb24);
    defer source_image.deinit();

    @memcpy(source_image.pixels.rgb24[0..], uncompressed_source[0..]);

    try source_image.writeToFilePath(image_file_name, Image.EncoderOptions{
        .tga = .{
            .rle_compressed = true,
            .color_map_depth = 24,
            .top_to_bottom_image = false,
            .image_id = "Truevision(R) Sample Image",
        },
    });
    defer {
        std.fs.cwd().deleteFile(image_file_name) catch {};
    }

    const read_file = try helpers.testOpenFile(image_file_name);
    defer read_file.close();

    var stream_source = std.io.StreamSource{ .file = read_file };

    var tga_file = tga.TGA{};

    const pixels = try tga_file.read(helpers.zigimg_test_allocator, &stream_source);
    defer pixels.deinit(helpers.zigimg_test_allocator);

    try helpers.expectEq(tga_file.width(), uncompressed_source.len);
    try helpers.expectEq(tga_file.height(), 1);
    try helpers.expectEq(try tga_file.pixelFormat(), .bgr24);

    const image_size = source_image.width * source_image.height;

    for (0..image_size) |index| {
        try helpers.expectEq(pixels.bgr24[index].r, source_image.pixels.rgb24[index].r);
        try helpers.expectEq(pixels.bgr24[index].g, source_image.pixels.rgb24[index].g);
        try helpers.expectEq(pixels.bgr24[index].b, source_image.pixels.rgb24[index].b);
    }
}

test "Write uncompressed Rgba32 to TGA" {
    const image_file_name = "zigimg_tga_uncompressed_rgba32.tga";

    const uncompressed_source = [_]color.Rgba32{
        .{ .r = 0xEF, .g = 0xCD, .b = 0xAB, .a = 0x60 },
        .{ .r = 0xEF, .g = 0xCD, .b = 0xAB, .a = 0x60 },
        .{ .r = 0xEF, .g = 0xCD, .b = 0xAB, .a = 0x60 },
        .{ .r = 0xEF, .g = 0xCD, .b = 0xAB, .a = 0x60 },
        .{ .r = 0xEF, .g = 0xCD, .b = 0xAB, .a = 0x60 },
        .{ .r = 0xEF, .g = 0xCD, .b = 0xAB, .a = 0x60 },
        .{ .r = 0xEF, .g = 0xCD, .b = 0xAB, .a = 0x60 },
        .{ .r = 0xEF, .g = 0xCD, .b = 0xAB, .a = 0x60 },
        .{
            .r = 0x1,
            .g = 0x2,
            .b = 0x3,
            .a = 0x1A,
        },
        .{
            .r = 0x4,
            .g = 0x5,
            .b = 0x6,
            .a = 0x2B,
        },
        .{
            .r = 0x7,
            .g = 0x8,
            .b = 0x9,
            .a = 0x3F,
        },
    };

    var source_image = try Image.create(helpers.zigimg_test_allocator, uncompressed_source.len, 1, .rgba32);
    defer source_image.deinit();

    @memcpy(source_image.pixels.rgba32[0..], uncompressed_source[0..]);

    try source_image.writeToFilePath(image_file_name, Image.EncoderOptions{
        .tga = .{
            .rle_compressed = false,
            .color_map_depth = 24,
            .top_to_bottom_image = true,
            .image_id = "Truevision(R) Sample Image",
        },
    });
    defer {
        std.fs.cwd().deleteFile(image_file_name) catch {};
    }

    const read_file = try helpers.testOpenFile(image_file_name);
    defer read_file.close();

    var stream_source = std.io.StreamSource{ .file = read_file };

    var tga_file = tga.TGA{};

    const pixels = try tga_file.read(helpers.zigimg_test_allocator, &stream_source);
    defer pixels.deinit(helpers.zigimg_test_allocator);

    try helpers.expectEq(tga_file.width(), uncompressed_source.len);
    try helpers.expectEq(tga_file.height(), 1);
    try helpers.expectEq(try tga_file.pixelFormat(), .bgra32);

    const image_size = source_image.width * source_image.height;

    for (0..image_size) |index| {
        try helpers.expectEq(pixels.bgra32[index].r, source_image.pixels.rgba32[index].r);
        try helpers.expectEq(pixels.bgra32[index].g, source_image.pixels.rgba32[index].g);
        try helpers.expectEq(pixels.bgra32[index].b, source_image.pixels.rgba32[index].b);
        try helpers.expectEq(pixels.bgra32[index].a, source_image.pixels.rgba32[index].a);
    }
}

test "Write compressed Rgba32 to TGA" {
    const image_file_name = "zigimg_tga_compressed_rgba32.tga";

    const uncompressed_source = [_]color.Rgba32{
        .{ .r = 0xEF, .g = 0xCD, .b = 0xAB, .a = 0x60 },
        .{ .r = 0xEF, .g = 0xCD, .b = 0xAB, .a = 0x60 },
        .{ .r = 0xEF, .g = 0xCD, .b = 0xAB, .a = 0x60 },
        .{ .r = 0xEF, .g = 0xCD, .b = 0xAB, .a = 0x60 },
        .{ .r = 0xEF, .g = 0xCD, .b = 0xAB, .a = 0x60 },
        .{ .r = 0xEF, .g = 0xCD, .b = 0xAB, .a = 0x60 },
        .{ .r = 0xEF, .g = 0xCD, .b = 0xAB, .a = 0x60 },
        .{ .r = 0xEF, .g = 0xCD, .b = 0xAB, .a = 0x60 },
        .{
            .r = 0x1,
            .g = 0x2,
            .b = 0x3,
            .a = 0x1A,
        },
        .{
            .r = 0x4,
            .g = 0x5,
            .b = 0x6,
            .a = 0x2B,
        },
        .{
            .r = 0x7,
            .g = 0x8,
            .b = 0x9,
            .a = 0x3F,
        },
    };

    var source_image = try Image.create(helpers.zigimg_test_allocator, uncompressed_source.len, 1, .rgba32);
    defer source_image.deinit();

    @memcpy(source_image.pixels.rgba32[0..], uncompressed_source[0..]);

    try source_image.writeToFilePath(image_file_name, Image.EncoderOptions{
        .tga = .{
            .rle_compressed = true,
            .color_map_depth = 24,
            .top_to_bottom_image = false,
            .image_id = "Truevision(R) Sample Image",
        },
    });
    defer {
        std.fs.cwd().deleteFile(image_file_name) catch {};
    }

    const read_file = try helpers.testOpenFile(image_file_name);
    defer read_file.close();

    var stream_source = std.io.StreamSource{ .file = read_file };

    var tga_file = tga.TGA{};

    const pixels = try tga_file.read(helpers.zigimg_test_allocator, &stream_source);
    defer pixels.deinit(helpers.zigimg_test_allocator);

    try helpers.expectEq(tga_file.width(), uncompressed_source.len);
    try helpers.expectEq(tga_file.height(), 1);
    try helpers.expectEq(try tga_file.pixelFormat(), .bgra32);

    const image_size = source_image.width * source_image.height;

    for (0..image_size) |index| {
        try helpers.expectEq(pixels.bgra32[index].r, source_image.pixels.rgba32[index].r);
        try helpers.expectEq(pixels.bgra32[index].g, source_image.pixels.rgba32[index].g);
        try helpers.expectEq(pixels.bgra32[index].b, source_image.pixels.rgba32[index].b);
        try helpers.expectEq(pixels.bgra32[index].a, source_image.pixels.rgba32[index].a);
    }
}
