const PixelFormat = @import("../../src/pixel_format.zig").PixelFormat;
const assert = std.debug.assert;
const color = @import("../../src/color.zig");
const std = @import("std");
const testing = std.testing;
const netpbm = @import("../../src/formats/netpbm.zig");
const Image = @import("../../src/Image.zig");
const helpers = @import("../helpers.zig");

test "Load ASCII PBM image" {
    const file = try helpers.testOpenFile(helpers.fixtures_path ++ "netpbm/pbm_ascii.pbm");
    defer file.close();

    var stream_source = std.io.StreamSource{ .file = file };

    var pbmFile = netpbm.PBM{};

    const pixels = try pbmFile.read(helpers.zigimg_test_allocator, &stream_source);
    defer pixels.deinit(helpers.zigimg_test_allocator);

    try helpers.expectEq(pbmFile.header.width, 8);
    try helpers.expectEq(pbmFile.header.height, 16);
    try helpers.expectEq(try pbmFile.pixelFormat(), PixelFormat.grayscale1);

    try testing.expect(pixels == .grayscale1);
    try helpers.expectEq(pixels.grayscale1[0].value, 0);
    try helpers.expectEq(pixels.grayscale1[1].value, 1);
    try helpers.expectEq(pixels.grayscale1[15 * 8 + 7].value, 1);
}

test "Load binary PBM image" {
    const file = try helpers.testOpenFile(helpers.fixtures_path ++ "netpbm/pbm_binary.pbm");
    defer file.close();

    var stream_source = std.io.StreamSource{ .file = file };

    var pbmFile = netpbm.PBM{};

    const pixels = try pbmFile.read(helpers.zigimg_test_allocator, &stream_source);
    defer pixels.deinit(helpers.zigimg_test_allocator);

    try helpers.expectEq(pbmFile.header.width, 8);
    try helpers.expectEq(pbmFile.header.height, 16);
    try helpers.expectEq(try pbmFile.pixelFormat(), PixelFormat.grayscale1);

    try testing.expect(pixels == .grayscale1);
    try helpers.expectEq(pixels.grayscale1[0].value, 0);
    try helpers.expectEq(pixels.grayscale1[1].value, 1);
    try helpers.expectEq(pixels.grayscale1[15 * 8 + 7].value, 1);
}

test "Load ASCII PGM 8-bit grayscale image" {
    const file = try helpers.testOpenFile(helpers.fixtures_path ++ "netpbm/pgm_ascii_grayscale8.pgm");
    defer file.close();

    var stream_source = std.io.StreamSource{ .file = file };

    var pgmFile = netpbm.PGM{};

    const pixels = try pgmFile.read(helpers.zigimg_test_allocator, &stream_source);
    defer pixels.deinit(helpers.zigimg_test_allocator);

    try helpers.expectEq(pgmFile.header.width, 16);
    try helpers.expectEq(pgmFile.header.height, 24);
    try helpers.expectEq(try pgmFile.pixelFormat(), PixelFormat.grayscale8);

    try testing.expect(pixels == .grayscale8);
    try helpers.expectEq(pixels.grayscale8[0].value, 2);
    try helpers.expectEq(pixels.grayscale8[1].value, 5);
    try helpers.expectEq(pixels.grayscale8[383].value, 196);
}

test "Load Binary PGM 8-bit grayscale image" {
    const file = try helpers.testOpenFile(helpers.fixtures_path ++ "netpbm/pgm_binary_grayscale8.pgm");
    defer file.close();

    var stream_source = std.io.StreamSource{ .file = file };

    var pgmFile = netpbm.PGM{};

    const pixels = try pgmFile.read(helpers.zigimg_test_allocator, &stream_source);
    defer pixels.deinit(helpers.zigimg_test_allocator);

    try helpers.expectEq(pgmFile.header.width, 16);
    try helpers.expectEq(pgmFile.header.height, 24);
    try helpers.expectEq(try pgmFile.pixelFormat(), PixelFormat.grayscale8);

    try testing.expect(pixels == .grayscale8);
    try helpers.expectEq(pixels.grayscale8[0].value, 2);
    try helpers.expectEq(pixels.grayscale8[1].value, 5);
    try helpers.expectEq(pixels.grayscale8[383].value, 196);
}

test "Load ASCII PGM 16-bit grayscale image" {
    const file = try helpers.testOpenFile(helpers.fixtures_path ++ "netpbm/pgm_ascii_grayscale16.pgm");
    defer file.close();

    var stream_source = std.io.StreamSource{ .file = file };

    var pgmFile = netpbm.PGM{};

    const pixels = try pgmFile.read(helpers.zigimg_test_allocator, &stream_source);
    defer pixels.deinit(helpers.zigimg_test_allocator);

    try helpers.expectEq(pgmFile.header.width, 8);
    try helpers.expectEq(pgmFile.header.height, 16);
    try helpers.expectEq(try pgmFile.pixelFormat(), PixelFormat.grayscale16);

    try testing.expect(pixels == .grayscale16);
    try helpers.expectEq(pixels.grayscale16[0].value, 3553);
    try helpers.expectEq(pixels.grayscale16[1].value, 4319);
    try helpers.expectEq(pixels.grayscale16[127].value, 61139);
}

test "Load Binary PGM 16-bit grayscale image" {
    const file = try helpers.testOpenFile(helpers.fixtures_path ++ "netpbm/pgm_binary_grayscale16.pgm");
    defer file.close();

    var stream_source = std.io.StreamSource{ .file = file };

    var pgmFile = netpbm.PGM{};

    const pixels = try pgmFile.read(helpers.zigimg_test_allocator, &stream_source);
    defer pixels.deinit(helpers.zigimg_test_allocator);

    try helpers.expectEq(pgmFile.header.width, 8);
    try helpers.expectEq(pgmFile.header.height, 16);
    try helpers.expectEq(try pgmFile.pixelFormat(), PixelFormat.grayscale16);

    try testing.expect(pixels == .grayscale16);
    try helpers.expectEq(pixels.grayscale16[0].value, 3553);
    try helpers.expectEq(pixels.grayscale16[1].value, 4319);
    try helpers.expectEq(pixels.grayscale16[127].value, 61139);
}

test "Load ASCII PPM image" {
    const file = try helpers.testOpenFile(helpers.fixtures_path ++ "netpbm/ppm_ascii_rgb24.ppm");
    defer file.close();

    var stream_source = std.io.StreamSource{ .file = file };

    var ppmFile = netpbm.PPM{};

    const pixels = try ppmFile.read(helpers.zigimg_test_allocator, &stream_source);
    defer pixels.deinit(helpers.zigimg_test_allocator);

    try helpers.expectEq(ppmFile.header.width, 27);
    try helpers.expectEq(ppmFile.header.height, 27);
    try helpers.expectEq(try ppmFile.pixelFormat(), PixelFormat.rgb24);

    try testing.expect(pixels == .rgb24);

    try helpers.expectEq(pixels.rgb24[0].r, 0x34);
    try helpers.expectEq(pixels.rgb24[0].g, 0x53);
    try helpers.expectEq(pixels.rgb24[0].b, 0x9f);

    try helpers.expectEq(pixels.rgb24[1].r, 0x32);
    try helpers.expectEq(pixels.rgb24[1].g, 0x5b);
    try helpers.expectEq(pixels.rgb24[1].b, 0x96);

    try helpers.expectEq(pixels.rgb24[26].r, 0xa8);
    try helpers.expectEq(pixels.rgb24[26].g, 0x5a);
    try helpers.expectEq(pixels.rgb24[26].b, 0x78);

    try helpers.expectEq(pixels.rgb24[27].r, 0x2e);
    try helpers.expectEq(pixels.rgb24[27].g, 0x54);
    try helpers.expectEq(pixels.rgb24[27].b, 0x99);

    try helpers.expectEq(pixels.rgb24[26 * 27 + 26].r, 0x88);
    try helpers.expectEq(pixels.rgb24[26 * 27 + 26].g, 0xb7);
    try helpers.expectEq(pixels.rgb24[26 * 27 + 26].b, 0x55);
}

test "Load binary PPM image" {
    const file = try helpers.testOpenFile(helpers.fixtures_path ++ "netpbm/ppm_binary_rgb24.ppm");
    defer file.close();

    var stream_source = std.io.StreamSource{ .file = file };

    var ppmFile = netpbm.PPM{};

    const pixels = try ppmFile.read(helpers.zigimg_test_allocator, &stream_source);
    defer pixels.deinit(helpers.zigimg_test_allocator);

    try helpers.expectEq(ppmFile.header.width, 27);
    try helpers.expectEq(ppmFile.header.height, 27);
    try helpers.expectEq(try ppmFile.pixelFormat(), PixelFormat.rgb24);

    try testing.expect(pixels == .rgb24);

    try helpers.expectEq(pixels.rgb24[0].r, 0x34);
    try helpers.expectEq(pixels.rgb24[0].g, 0x53);
    try helpers.expectEq(pixels.rgb24[0].b, 0x9f);

    try helpers.expectEq(pixels.rgb24[1].r, 0x32);
    try helpers.expectEq(pixels.rgb24[1].g, 0x5b);
    try helpers.expectEq(pixels.rgb24[1].b, 0x96);

    try helpers.expectEq(pixels.rgb24[26].r, 0xa8);
    try helpers.expectEq(pixels.rgb24[26].g, 0x5a);
    try helpers.expectEq(pixels.rgb24[26].b, 0x78);

    try helpers.expectEq(pixels.rgb24[27].r, 0x2e);
    try helpers.expectEq(pixels.rgb24[27].g, 0x54);
    try helpers.expectEq(pixels.rgb24[27].b, 0x99);

    try helpers.expectEq(pixels.rgb24[26 * 27 + 26].r, 0x88);
    try helpers.expectEq(pixels.rgb24[26 * 27 + 26].g, 0xb7);
    try helpers.expectEq(pixels.rgb24[26 * 27 + 26].b, 0x55);
}

test "Write bitmap(grayscale1) ASCII PBM file" {
    const grayscales = [_]u1{
        1, 0, 0, 1,
        1, 0, 1, 0,
        0, 1, 0, 1,
        1, 1, 1, 0,
    };

    const image_file_name = "zigimg_pbm_ascii_test.pbm";
    const width = grayscales.len;
    const height = 1;

    var source_image = try Image.create(helpers.zigimg_test_allocator, width, height, PixelFormat.grayscale1);
    defer source_image.deinit();

    const source = source_image.pixels;
    for (grayscales) |value, index| {
        source.grayscale1[index].value = value;
    }

    try source_image.writeToFilePath(image_file_name, Image.EncoderOptions{
        .pbm = .{ .binary = false },
    });

    defer {
        std.fs.cwd().deleteFile(image_file_name) catch unreachable;
    }

    var read_image = try Image.fromFilePath(helpers.zigimg_test_allocator, image_file_name);
    defer read_image.deinit();

    try helpers.expectEq(read_image.width, width);
    try helpers.expectEq(read_image.height, height);

    const read_pixels = read_image.pixels;

    try testing.expect(read_pixels == .grayscale1);

    for (grayscales) |grayscale_value, index| {
        try helpers.expectEq(read_pixels.grayscale1[index].value, grayscale_value);
    }
}

test "Write bitmap(Grayscale1) binary PBM file" {
    const grayscales = [_]u1{
        1, 0, 0, 1,
        1, 0, 1, 0,
        0, 1, 0, 1,
        1, 1, 1, 0,
        1, 1,
    };

    const image_file_name = "zigimg_pbm_binary_test.pbm";
    const width = grayscales.len;
    const height = 1;

    var source_image = try Image.create(helpers.zigimg_test_allocator, width, height, PixelFormat.grayscale1);
    defer source_image.deinit();

    const source = source_image.pixels;

    for (grayscales) |value, index| {
        source.grayscale1[index].value = value;
    }

    try source_image.writeToFilePath(image_file_name, Image.EncoderOptions{
        .pbm = .{ .binary = true },
    });

    defer {
        std.fs.cwd().deleteFile(image_file_name) catch unreachable;
    }

    var read_image = try Image.fromFilePath(helpers.zigimg_test_allocator, image_file_name);
    defer read_image.deinit();

    try helpers.expectEq(read_image.width, width);
    try helpers.expectEq(read_image.height, height);

    const read_pixels = read_image.pixels;

    try testing.expect(read_pixels == .grayscale1);

    for (grayscales) |grayscale_value, index| {
        try helpers.expectEq(read_pixels.grayscale1[index].value, grayscale_value);
    }
}

test "Write grayscale8 ASCII PGM file" {
    const grayscales = [_]u8{
        0,   29,  56,  85,  113, 142, 170, 199, 227, 255,
        227, 199, 170, 142, 113, 85,  56,  29,  0,
    };

    const image_file_name = "zigimg_pgm_ascii_test.pgm";
    const width = grayscales.len;
    const height = 1;

    var source_image = try Image.create(helpers.zigimg_test_allocator, width, height, PixelFormat.grayscale8);
    defer source_image.deinit();

    const source = source_image.pixels;
    for (grayscales) |value, index| {
        source.grayscale8[index].value = value;
    }

    try source_image.writeToFilePath(image_file_name, Image.EncoderOptions{
        .pgm = .{ .binary = false },
    });

    defer {
        std.fs.cwd().deleteFile(image_file_name) catch unreachable;
    }

    var read_image = try Image.fromFilePath(helpers.zigimg_test_allocator, image_file_name);
    defer read_image.deinit();

    try helpers.expectEq(read_image.width, width);
    try helpers.expectEq(read_image.height, height);

    const read_pixels = read_image.pixels;

    try testing.expect(read_pixels == .grayscale8);

    for (grayscales) |grayscale_value, index| {
        try helpers.expectEq(read_pixels.grayscale8[index].value, grayscale_value);
    }
}

test "Write grayscale8 binary PGM file" {
    const grayscales = [_]u8{
        0,   29,  56,  85,  113, 142, 170, 199, 227, 255,
        227, 199, 170, 142, 113, 85,  56,  29,  0,
    };

    const image_file_name = "zigimg_pgm_binary_test.pgm";
    const width = grayscales.len;
    const height = 1;

    var source_image = try Image.create(helpers.zigimg_test_allocator, width, height, PixelFormat.grayscale8);
    defer source_image.deinit();

    const source = source_image.pixels;
    for (grayscales) |value, index| {
        source.grayscale8[index].value = value;
    }

    try source_image.writeToFilePath(image_file_name, Image.EncoderOptions{
        .pgm = .{ .binary = true },
    });

    defer {
        std.fs.cwd().deleteFile(image_file_name) catch unreachable;
    }

    var read_image = try Image.fromFilePath(helpers.zigimg_test_allocator, image_file_name);
    defer read_image.deinit();

    try helpers.expectEq(read_image.width, width);
    try helpers.expectEq(read_image.height, height);

    const read_pixels = read_image.pixels;
    try testing.expect(read_pixels == .grayscale8);

    for (grayscales) |grayscale_value, index| {
        try helpers.expectEq(read_pixels.grayscale8[index].value, grayscale_value);
    }
}

test "Writing Rgb24 ASCII PPM format" {
    const expected_colors = [_]u32{ 0xff0000, 0x00ff00, 0x0000ff, 0x000000, 0xffffff, 0x00ffff, 0xff00ff, 0xffff00 };

    const image_file_name = "zigimg_ppm_rgb24_ascii_test.ppm";
    const width = expected_colors.len;
    const height = 1;

    var source_image = try Image.create(helpers.zigimg_test_allocator, width, height, PixelFormat.rgb24);
    defer source_image.deinit();

    const pixels = source_image.pixels;

    try testing.expect(pixels == .rgb24);
    try testing.expect(pixels.rgb24.len == width * height);

    // R, G, B
    pixels.rgb24[0] = color.Rgb24.initRgb(255, 0, 0);
    pixels.rgb24[1] = color.Rgb24.initRgb(0, 255, 0);
    pixels.rgb24[2] = color.Rgb24.initRgb(0, 0, 255);

    // Black, white
    pixels.rgb24[3] = color.Rgb24.initRgb(0, 0, 0);
    pixels.rgb24[4] = color.Rgb24.initRgb(255, 255, 255);

    // Cyan, Magenta, Yellow
    pixels.rgb24[5] = color.Rgb24.initRgb(0, 255, 255);
    pixels.rgb24[6] = color.Rgb24.initRgb(255, 0, 255);
    pixels.rgb24[7] = color.Rgb24.initRgb(255, 255, 0);

    try source_image.writeToFilePath(image_file_name, Image.EncoderOptions{
        .ppm = .{ .binary = false },
    });

    defer {
        std.fs.cwd().deleteFile(image_file_name) catch unreachable;
    }

    var read_image = try Image.fromFilePath(helpers.zigimg_test_allocator, image_file_name);
    defer read_image.deinit();

    try helpers.expectEq(read_image.width, width);
    try helpers.expectEq(read_image.height, height);

    const read_image_pixels = read_image.pixels;

    try testing.expect(read_image_pixels == .rgb24);

    for (expected_colors) |hex_color, index| {
        try helpers.expectEq(read_image_pixels.rgb24[index].toU32Rgb(), hex_color);
    }
}

test "Writing Rgb24 binary PPM format" {
    const expected_colors = [_]u32{ 0xff0000, 0x00ff00, 0x0000ff, 0x000000, 0xffffff, 0x00ffff, 0xff00ff, 0xffff00 };

    const image_file_name = "zigimg_ppm_rgb24_binary_test.ppm";
    const width = expected_colors.len;
    const height = 1;

    var source_image = try Image.create(helpers.zigimg_test_allocator, width, height, PixelFormat.rgb24);
    defer source_image.deinit();

    const pixels = source_image.pixels;

    try testing.expect(pixels == .rgb24);
    try testing.expect(pixels.rgb24.len == width * height);

    // R, G, B
    pixels.rgb24[0] = color.Rgb24.initRgb(255, 0, 0);
    pixels.rgb24[1] = color.Rgb24.initRgb(0, 255, 0);
    pixels.rgb24[2] = color.Rgb24.initRgb(0, 0, 255);

    // Black, white
    pixels.rgb24[3] = color.Rgb24.initRgb(0, 0, 0);
    pixels.rgb24[4] = color.Rgb24.initRgb(255, 255, 255);

    // Cyan, Magenta, Yellow
    pixels.rgb24[5] = color.Rgb24.initRgb(0, 255, 255);
    pixels.rgb24[6] = color.Rgb24.initRgb(255, 0, 255);
    pixels.rgb24[7] = color.Rgb24.initRgb(255, 255, 0);

    try source_image.writeToFilePath(image_file_name, Image.EncoderOptions{
        .ppm = .{ .binary = true },
    });

    defer {
        std.fs.cwd().deleteFile(image_file_name) catch unreachable;
    }

    var read_image = try Image.fromFilePath(helpers.zigimg_test_allocator, image_file_name);
    defer read_image.deinit();

    try helpers.expectEq(read_image.width, width);
    try helpers.expectEq(read_image.height, height);

    const read_image_pixels = read_image.pixels;

    try testing.expect(read_image_pixels == .rgb24);

    for (expected_colors) |hex_color, index| {
        try helpers.expectEq(read_image_pixels.rgb24[index].toU32Rgb(), hex_color);
    }
}
