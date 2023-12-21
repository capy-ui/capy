const PixelFormat = @import("../../src/pixel_format.zig").PixelFormat;
const assert = std.debug.assert;
const color = @import("../../src/color.zig");
const pcx = @import("../../src/formats/pcx.zig");
const std = @import("std");
const testing = std.testing;
const Image = @import("../../src/Image.zig");
const helpers = @import("../helpers.zig");

test "PCX indexed1 (linear)" {
    const file = try helpers.testOpenFile(helpers.fixtures_path ++ "pcx/test-bpp1.pcx");
    defer file.close();

    var stream_source = std.io.StreamSource{ .file = file };

    var pcxFile = pcx.PCX{};

    const pixels = try pcxFile.read(helpers.zigimg_test_allocator, &stream_source);
    defer pixels.deinit(helpers.zigimg_test_allocator);

    try helpers.expectEq(pcxFile.width(), 27);
    try helpers.expectEq(pcxFile.height(), 27);
    try helpers.expectEq(try pcxFile.pixelFormat(), PixelFormat.indexed1);

    try testing.expect(pixels == .indexed1);

    try helpers.expectEq(pixels.indexed1.indices[0], 0);
    try helpers.expectEq(pixels.indexed1.indices[15], 1);
    try helpers.expectEq(pixels.indexed1.indices[18], 1);
    try helpers.expectEq(pixels.indexed1.indices[19], 1);
    try helpers.expectEq(pixels.indexed1.indices[20], 1);
    try helpers.expectEq(pixels.indexed1.indices[22 * 27 + 11], 1);

    const palette0 = pixels.indexed1.palette[0];

    try helpers.expectEq(palette0.r, 102);
    try helpers.expectEq(palette0.g, 90);
    try helpers.expectEq(palette0.b, 155);

    const palette1 = pixels.indexed1.palette[1];

    try helpers.expectEq(palette1.r, 115);
    try helpers.expectEq(palette1.g, 137);
    try helpers.expectEq(palette1.b, 106);
}

test "PCX indexed4 (linear)" {
    const file = try helpers.testOpenFile(helpers.fixtures_path ++ "pcx/test-bpp4.pcx");
    defer file.close();

    var stream_source = std.io.StreamSource{ .file = file };

    var pcxFile = pcx.PCX{};

    const pixels = try pcxFile.read(helpers.zigimg_test_allocator, &stream_source);
    defer pixels.deinit(helpers.zigimg_test_allocator);

    try helpers.expectEq(pcxFile.width(), 27);
    try helpers.expectEq(pcxFile.height(), 27);
    try helpers.expectEq(try pcxFile.pixelFormat(), PixelFormat.indexed4);

    try testing.expect(pixels == .indexed4);

    try helpers.expectEq(pixels.indexed4.indices[0], 1);
    try helpers.expectEq(pixels.indexed4.indices[1], 9);
    try helpers.expectEq(pixels.indexed4.indices[2], 0);
    try helpers.expectEq(pixels.indexed4.indices[3], 0);
    try helpers.expectEq(pixels.indexed4.indices[4], 4);
    try helpers.expectEq(pixels.indexed4.indices[14 * 27 + 9], 6);
    try helpers.expectEq(pixels.indexed4.indices[25 * 27 + 25], 7);

    const palette0 = pixels.indexed4.palette[0];

    try helpers.expectEq(palette0.r, 0x5e);
    try helpers.expectEq(palette0.g, 0x37);
    try helpers.expectEq(palette0.b, 0x97);

    const palette15 = pixels.indexed4.palette[15];

    try helpers.expectEq(palette15.r, 0x60);
    try helpers.expectEq(palette15.g, 0xb5);
    try helpers.expectEq(palette15.b, 0x68);
}

test "PCX indexed8 (linear)" {
    const file = try helpers.testOpenFile(helpers.fixtures_path ++ "pcx/test-bpp8.pcx");
    defer file.close();

    var stream_source = std.io.StreamSource{ .file = file };

    var pcxFile = pcx.PCX{};

    const pixels = try pcxFile.read(helpers.zigimg_test_allocator, &stream_source);
    defer pixels.deinit(helpers.zigimg_test_allocator);

    try helpers.expectEq(pcxFile.width(), 27);
    try helpers.expectEq(pcxFile.height(), 27);
    try helpers.expectEq(try pcxFile.pixelFormat(), PixelFormat.indexed8);

    try testing.expect(pixels == .indexed8);

    try helpers.expectEq(pixels.indexed8.indices[0], 37);
    try helpers.expectEq(pixels.indexed8.indices[3 * 27 + 15], 60);
    try helpers.expectEq(pixels.indexed8.indices[26 * 27 + 26], 254);

    const palette0 = pixels.indexed8.palette[0];

    try helpers.expectEq(palette0.r, 0x46);
    try helpers.expectEq(palette0.g, 0x1c);
    try helpers.expectEq(palette0.b, 0x71);

    const palette15 = pixels.indexed8.palette[15];

    try helpers.expectEq(palette15.r, 0x41);
    try helpers.expectEq(palette15.g, 0x49);
    try helpers.expectEq(palette15.b, 0x30);

    const palette219 = pixels.indexed8.palette[219];

    try helpers.expectEq(palette219.r, 0x61);
    try helpers.expectEq(palette219.g, 0x8e);
    try helpers.expectEq(palette219.b, 0xc3);
}

test "PCX indexed24 (planar)" {
    const file = try helpers.testOpenFile(helpers.fixtures_path ++ "pcx/test-bpp24.pcx");
    defer file.close();

    var stream_source = std.io.StreamSource{ .file = file };

    var pcxFile = pcx.PCX{};

    const pixels = try pcxFile.read(helpers.zigimg_test_allocator, &stream_source);
    defer pixels.deinit(helpers.zigimg_test_allocator);

    try helpers.expectEq(pcxFile.header.planes, 3);
    try helpers.expectEq(pcxFile.header.bpp, 8);

    try helpers.expectEq(pcxFile.width(), 27);
    try helpers.expectEq(pcxFile.height(), 27);
    try helpers.expectEq(try pcxFile.pixelFormat(), PixelFormat.rgb24);

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

test "Write PCX indexed1 (odd width)" {
    const image_file_name = "zigimg_pcx_indexed1_odd.pcx";

    var source_file = try helpers.testOpenFile(helpers.fixtures_path ++ "pcx/test-bpp1.pcx");
    defer source_file.close();

    var source_image = try Image.fromFile(helpers.zigimg_test_allocator, &source_file);
    defer source_image.deinit();

    try source_image.writeToFilePath(image_file_name, Image.EncoderOptions{
        .pcx = .{},
    });

    defer {
        std.fs.cwd().deleteFile(image_file_name) catch {};
    }

    const read_file = try helpers.testOpenFile(image_file_name);
    defer read_file.close();

    var stream_source = std.io.StreamSource{ .file = read_file };

    var pcxFile = pcx.PCX{};

    const pixels = try pcxFile.read(helpers.zigimg_test_allocator, &stream_source);
    defer pixels.deinit(helpers.zigimg_test_allocator);

    try helpers.expectEq(pcxFile.width(), 27);
    try helpers.expectEq(pcxFile.height(), 27);
    try helpers.expectEq(try pcxFile.pixelFormat(), PixelFormat.indexed1);

    try testing.expect(pixels == .indexed1);

    const image_size = source_image.width * source_image.height;

    for (0..image_size) |index| {
        try helpers.expectEq(pixels.indexed1.indices[index], source_image.pixels.indexed1.indices[index]);
    }

    for (0..pixels.indexed1.palette.len) |index| {
        try helpers.expectEq(pixels.indexed1.palette[index].r, source_image.pixels.indexed1.palette[index].r);
        try helpers.expectEq(pixels.indexed1.palette[index].g, source_image.pixels.indexed1.palette[index].g);
        try helpers.expectEq(pixels.indexed1.palette[index].b, source_image.pixels.indexed1.palette[index].b);
        try helpers.expectEq(pixels.indexed1.palette[index].a, 255);
    }
}

test "Write PCX indexed 1 (even width)" {
    const image_width = 256;
    const image_height = 256;
    const checker_size = 32;

    var image_pattern = try Image.create(helpers.zigimg_test_allocator, image_width, image_height, .indexed1);
    defer image_pattern.deinit();

    // Generate palette
    image_pattern.pixels.indexed1.palette[0] = color.Rgba32.initRgb(0, 0, 0);
    image_pattern.pixels.indexed1.palette[1] = color.Rgba32.initRgb(255, 255, 255);

    // Generate pattern
    for (0..image_height) |y| {
        const stride = y * image_width;

        const y_pattern = (y / checker_size) & 0x1;

        for (0..image_width) |x| {
            const x_pattern = (x / checker_size) & 0x1;

            image_pattern.pixels.indexed1.indices[stride + x] = @truncate(~(y_pattern ^ x_pattern));
        }
    }

    const image_file_name = "zigimg_pcx_indexed1_even.pcx";

    try image_pattern.writeToFilePath(image_file_name, Image.EncoderOptions{
        .pcx = .{},
    });
    defer {
        std.fs.cwd().deleteFile(image_file_name) catch {};
    }

    const read_file = try helpers.testOpenFile(image_file_name);
    defer read_file.close();

    var stream_source = std.io.StreamSource{ .file = read_file };

    var pcxFile = pcx.PCX{};

    const pixels = try pcxFile.read(helpers.zigimg_test_allocator, &stream_source);
    defer pixels.deinit(helpers.zigimg_test_allocator);

    try helpers.expectEq(pcxFile.width(), image_width);
    try helpers.expectEq(pcxFile.height(), image_height);
    try helpers.expectEq(try pcxFile.pixelFormat(), PixelFormat.indexed1);

    try testing.expect(pixels == .indexed1);

    // Check indices
    const image_size = image_pattern.width * image_pattern.height;
    for (0..image_size) |index| {
        try helpers.expectEq(pixels.indexed1.indices[index], image_pattern.pixels.indexed1.indices[index]);
    }

    // Check palette
    for (0..pixels.indexed1.palette.len) |index| {
        try helpers.expectEq(pixels.indexed1.palette[index].r, image_pattern.pixels.indexed1.palette[index].r);
        try helpers.expectEq(pixels.indexed1.palette[index].g, image_pattern.pixels.indexed1.palette[index].g);
        try helpers.expectEq(pixels.indexed1.palette[index].b, image_pattern.pixels.indexed1.palette[index].b);
        try helpers.expectEq(pixels.indexed1.palette[index].a, 255);
    }
}

test "Write PCX indexed4 (odd width)" {
    const image_file_name = "zigimg_pcx_indexed4_odd.pcx";

    var source_file = try helpers.testOpenFile(helpers.fixtures_path ++ "pcx/test-bpp4.pcx");
    defer source_file.close();

    var source_image = try Image.fromFile(helpers.zigimg_test_allocator, &source_file);
    defer source_image.deinit();

    try source_image.writeToFilePath(image_file_name, Image.EncoderOptions{
        .pcx = .{},
    });

    defer {
        std.fs.cwd().deleteFile(image_file_name) catch {};
    }

    const read_file = try helpers.testOpenFile(image_file_name);
    defer read_file.close();

    var stream_source = std.io.StreamSource{ .file = read_file };

    var pcxFile = pcx.PCX{};

    const pixels = try pcxFile.read(helpers.zigimg_test_allocator, &stream_source);
    defer pixels.deinit(helpers.zigimg_test_allocator);

    try helpers.expectEq(pcxFile.width(), 27);
    try helpers.expectEq(pcxFile.height(), 27);
    try helpers.expectEq(try pcxFile.pixelFormat(), PixelFormat.indexed4);

    try testing.expect(pixels == .indexed4);

    const image_size = source_image.width * source_image.height;
    for (0..image_size) |index| {
        try helpers.expectEq(pixels.indexed4.indices[index], source_image.pixels.indexed4.indices[index]);
    }

    for (0..pixels.indexed4.palette.len) |index| {
        try helpers.expectEq(pixels.indexed4.palette[index].r, source_image.pixels.indexed4.palette[index].r);
        try helpers.expectEq(pixels.indexed4.palette[index].g, source_image.pixels.indexed4.palette[index].g);
        try helpers.expectEq(pixels.indexed4.palette[index].b, source_image.pixels.indexed4.palette[index].b);
        try helpers.expectEq(pixels.indexed4.palette[index].a, 255);
    }
}

test "Write PCX indexed 4 (even width)" {
    var rainbow_test = try Image.create(helpers.zigimg_test_allocator, 16, 16, .indexed4);
    defer rainbow_test.deinit();

    // Generate palette
    const colors_per_channel = 16 / 3;
    for (0..16) |index| {
        const current_step = index % colors_per_channel;
        const current_channel = index / colors_per_channel;
        const current_intensity = color.toIntColor(u8, @as(f32, @floatFromInt(current_step)) / @as(f32, @floatFromInt(colors_per_channel)));
        rainbow_test.pixels.indexed4.palette[index].a = 255;
        switch (current_channel) {
            0 => rainbow_test.pixels.indexed4.palette[index].r = current_intensity,
            1 => rainbow_test.pixels.indexed4.palette[index].g = current_intensity,
            2, 3 => rainbow_test.pixels.indexed4.palette[index].b = current_intensity,
            else => {},
        }
    }

    // Generate pattern
    for (0..16) |y| {
        const stride = y * 16;
        for (0..16) |x| {
            rainbow_test.pixels.indexed4.indices[stride + x] = @truncate(y);
        }
    }

    const image_file_name = "zigimg_pcx_indexed4_even.pcx";

    try rainbow_test.writeToFilePath(image_file_name, Image.EncoderOptions{
        .pcx = .{},
    });
    defer {
        std.fs.cwd().deleteFile(image_file_name) catch {};
    }

    const read_file = try helpers.testOpenFile(image_file_name);
    defer read_file.close();

    var stream_source = std.io.StreamSource{ .file = read_file };

    var pcxFile = pcx.PCX{};

    const pixels = try pcxFile.read(helpers.zigimg_test_allocator, &stream_source);
    defer pixels.deinit(helpers.zigimg_test_allocator);

    try helpers.expectEq(pcxFile.width(), 16);
    try helpers.expectEq(pcxFile.height(), 16);
    try helpers.expectEq(try pcxFile.pixelFormat(), PixelFormat.indexed4);

    try testing.expect(pixels == .indexed4);

    const image_size = rainbow_test.width * rainbow_test.height;
    for (0..image_size) |index| {
        try helpers.expectEq(pixels.indexed4.indices[index], rainbow_test.pixels.indexed4.indices[index]);
    }

    for (0..pixels.indexed4.palette.len) |index| {
        try helpers.expectEq(pixels.indexed4.palette[index].r, rainbow_test.pixels.indexed4.palette[index].r);
        try helpers.expectEq(pixels.indexed4.palette[index].g, rainbow_test.pixels.indexed4.palette[index].g);
        try helpers.expectEq(pixels.indexed4.palette[index].b, rainbow_test.pixels.indexed4.palette[index].b);
        try helpers.expectEq(pixels.indexed4.palette[index].a, 255);
    }
}

test "Write PCX indexed8 (odd width)" {
    const image_file_name = "zigimg_pcx_indexed8_odd.pcx";

    var source_file = try helpers.testOpenFile(helpers.fixtures_path ++ "pcx/test-bpp8.pcx");
    defer source_file.close();

    var source_image = try Image.fromFile(helpers.zigimg_test_allocator, &source_file);
    defer source_image.deinit();

    try source_image.writeToFilePath(image_file_name, Image.EncoderOptions{
        .pcx = .{},
    });

    defer {
        std.fs.cwd().deleteFile(image_file_name) catch {};
    }

    const read_file = try helpers.testOpenFile(image_file_name);
    defer read_file.close();

    var stream_source = std.io.StreamSource{ .file = read_file };

    var pcxFile = pcx.PCX{};

    const pixels = try pcxFile.read(helpers.zigimg_test_allocator, &stream_source);
    defer pixels.deinit(helpers.zigimg_test_allocator);

    const image_size = source_image.width * source_image.height;
    for (0..image_size) |index| {
        try helpers.expectEq(pixels.indexed8.indices[index], source_image.pixels.indexed8.indices[index]);
    }

    for (0..pixels.indexed8.palette.len) |index| {
        try helpers.expectEq(pixels.indexed8.palette[index].r, source_image.pixels.indexed8.palette[index].r);
        try helpers.expectEq(pixels.indexed8.palette[index].g, source_image.pixels.indexed8.palette[index].g);
        try helpers.expectEq(pixels.indexed8.palette[index].b, source_image.pixels.indexed8.palette[index].b);
        try helpers.expectEq(pixels.indexed8.palette[index].a, 255);
    }
}

test "Write PCX indexed 8 (even width)" {
    var rainbow_test = try Image.create(helpers.zigimg_test_allocator, 256, 256, .indexed8);
    defer rainbow_test.deinit();

    // Generate palette
    const colors_per_channel = 256 / 3;
    for (0..255) |index| {
        const current_step = index % colors_per_channel;
        const current_channel = index / colors_per_channel;
        const current_intensity = color.toIntColor(u8, @as(f32, @floatFromInt(current_step)) / @as(f32, @floatFromInt(colors_per_channel)));

        rainbow_test.pixels.indexed8.palette[index].r = 0;
        rainbow_test.pixels.indexed8.palette[index].g = 0;
        rainbow_test.pixels.indexed8.palette[index].b = 0;
        rainbow_test.pixels.indexed8.palette[index].a = 255;
        switch (current_channel) {
            0 => rainbow_test.pixels.indexed8.palette[index].r = current_intensity,
            1 => rainbow_test.pixels.indexed8.palette[index].g = current_intensity,
            2, 3 => rainbow_test.pixels.indexed8.palette[index].b = current_intensity,
            else => {},
        }
    }

    // Generate pattern
    for (0..255) |y| {
        const stride = y * 256;
        for (0..255) |x| {
            rainbow_test.pixels.indexed8.indices[stride + x] = @truncate(y);
        }
    }

    const image_file_name = "zigimg_pcx_indexed8_even.pcx";

    try rainbow_test.writeToFilePath(image_file_name, Image.EncoderOptions{
        .pcx = .{},
    });
    defer {
        std.fs.cwd().deleteFile(image_file_name) catch {};
    }

    const read_file = try helpers.testOpenFile(image_file_name);
    defer read_file.close();

    var stream_source = std.io.StreamSource{ .file = read_file };

    var pcxFile = pcx.PCX{};

    const pixels = try pcxFile.read(helpers.zigimg_test_allocator, &stream_source);
    defer pixels.deinit(helpers.zigimg_test_allocator);

    try helpers.expectEq(pcxFile.width(), 256);
    try helpers.expectEq(pcxFile.height(), 256);
    try helpers.expectEq(try pcxFile.pixelFormat(), PixelFormat.indexed8);

    try testing.expect(pixels == .indexed8);

    const image_size = rainbow_test.width * rainbow_test.height;
    for (0..image_size) |index| {
        try helpers.expectEq(pixels.indexed8.indices[index], rainbow_test.pixels.indexed8.indices[index]);
    }

    for (0..pixels.indexed8.palette.len) |index| {
        try helpers.expectEq(pixels.indexed8.palette[index].r, rainbow_test.pixels.indexed8.palette[index].r);
        try helpers.expectEq(pixels.indexed8.palette[index].g, rainbow_test.pixels.indexed8.palette[index].g);
        try helpers.expectEq(pixels.indexed8.palette[index].b, rainbow_test.pixels.indexed8.palette[index].b);
        try helpers.expectEq(pixels.indexed8.palette[index].a, 255);
    }
}

test "Write PCX rgb24 (odd width)" {
    const image_file_name = "zigimg_pcx_bpp24_odd.pcx";

    var source_file = try helpers.testOpenFile(helpers.fixtures_path ++ "pcx/test-bpp24.pcx");
    defer source_file.close();

    var source_image = try Image.fromFile(helpers.zigimg_test_allocator, &source_file);
    defer source_image.deinit();

    try source_image.writeToFilePath(image_file_name, Image.EncoderOptions{
        .pcx = .{},
    });

    defer {
        std.fs.cwd().deleteFile(image_file_name) catch {};
    }

    const read_file = try helpers.testOpenFile(image_file_name);
    defer read_file.close();

    var stream_source = std.io.StreamSource{ .file = read_file };

    var pcxFile = pcx.PCX{};

    const pixels = try pcxFile.read(helpers.zigimg_test_allocator, &stream_source);
    defer pixels.deinit(helpers.zigimg_test_allocator);

    try helpers.expectEq(pcxFile.header.planes, 3);
    try helpers.expectEq(pcxFile.header.bpp, 8);

    try helpers.expectEq(pcxFile.width(), 27);
    try helpers.expectEq(pcxFile.height(), 27);
    try helpers.expectEq(try pcxFile.pixelFormat(), PixelFormat.rgb24);

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

test "Write PCX rgb24 (even width)" {
    var rainbow_test = try Image.create(helpers.zigimg_test_allocator, 256, 256, .rgb24);
    defer rainbow_test.deinit();

    // Generate pattern
    const image_size = rainbow_test.width * rainbow_test.height;
    for (0..image_size) |index| {
        const y = index / rainbow_test.width;
        const which_channel = y % 3;
        const intensity: u8 = @truncate(y % rainbow_test.width);

        rainbow_test.pixels.rgb24[index].r = 0;
        rainbow_test.pixels.rgb24[index].g = 0;
        rainbow_test.pixels.rgb24[index].b = 0;

        switch (which_channel) {
            0 => rainbow_test.pixels.rgb24[index].r = intensity,
            1 => rainbow_test.pixels.rgb24[index].g = intensity,
            2 => rainbow_test.pixels.rgb24[index].b = intensity,
            else => {},
        }
    }

    const image_file_name = "zigimg_pcx_rgb24_even.pcx";

    try rainbow_test.writeToFilePath(image_file_name, Image.EncoderOptions{
        .pcx = .{},
    });
    defer {
        std.fs.cwd().deleteFile(image_file_name) catch {};
    }

    const read_file = try helpers.testOpenFile(image_file_name);
    defer read_file.close();

    var stream_source = std.io.StreamSource{ .file = read_file };

    var pcxFile = pcx.PCX{};

    const pixels = try pcxFile.read(helpers.zigimg_test_allocator, &stream_source);
    defer pixels.deinit(helpers.zigimg_test_allocator);

    try helpers.expectEq(pcxFile.width(), 256);
    try helpers.expectEq(pcxFile.height(), 256);
    try helpers.expectEq(try pcxFile.pixelFormat(), PixelFormat.rgb24);

    try testing.expect(pixels == .rgb24);

    // Check pattern
    for (0..image_size) |index| {
        try helpers.expectEq(pixels.rgb24[index].r, rainbow_test.pixels.rgb24[index].r);
        try helpers.expectEq(pixels.rgb24[index].g, rainbow_test.pixels.rgb24[index].g);
        try helpers.expectEq(pixels.rgb24[index].b, rainbow_test.pixels.rgb24[index].b);
    }
}
