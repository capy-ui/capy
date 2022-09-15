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

    try helpers.expectEq(pcxFile.width, 27);
    try helpers.expectEq(pcxFile.height, 27);
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

    try helpers.expectEq(pcxFile.width, 27);
    try helpers.expectEq(pcxFile.height, 27);
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

    try helpers.expectEq(pcxFile.width, 27);
    try helpers.expectEq(pcxFile.height, 27);
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

    try helpers.expectEq(pcxFile.width, 27);
    try helpers.expectEq(pcxFile.height, 27);
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
