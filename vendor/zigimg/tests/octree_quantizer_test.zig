const ArrayList = std.ArrayList;
const HeapAllocator = std.heap.HeapAllocator;
const Image = @import("../src/Image.zig");
const OctTreeQuantizer = @import("../src/octree_quantizer.zig").OctTreeQuantizer;
const assert = std.debug.assert;
const color = @import("../src/color.zig");
const std = @import("std");
const testing = std.testing;
const helpers = @import("helpers.zig");

test "Build the oct tree with 3 colors" {
    var quantizer = OctTreeQuantizer.init(helpers.zigimg_test_allocator);
    defer quantizer.deinit();
    const red = color.Rgba32.initRgb(0xFF, 0, 0);
    const green = color.Rgba32.initRgb(0, 0xFF, 0);
    const blue = color.Rgba32.initRgb(0, 0, 0xFF);
    try quantizer.addColor(red);
    try quantizer.addColor(green);
    try quantizer.addColor(blue);
    var paletteStorage: [256]color.Rgba32 = undefined;
    var palette = try quantizer.makePalette(256, paletteStorage[0..]);
    try helpers.expectEq(palette.len, 3);

    try helpers.expectEq(try quantizer.getPaletteIndex(red), 2);
    try helpers.expectEq(try quantizer.getPaletteIndex(green), 1);
    try helpers.expectEq(try quantizer.getPaletteIndex(blue), 0);

    try helpers.expectEq(palette[0].b, 0xFF);
    try helpers.expectEq(palette[1].g, 0xFF);
    try helpers.expectEq(palette[2].r, 0xFF);
}

test "Build a oct tree with 32-bit RGBA bitmap" {
    var MemoryRGBABitmap: [200 * 1024]u8 = undefined;
    var buffer = try helpers.testReadFile(helpers.fixtures_path ++ "bmp/windows_rgba_v5.bmp", MemoryRGBABitmap[0..]);

    var image = try Image.fromMemory(helpers.zigimg_test_allocator, buffer);
    defer image.deinit();

    var quantizer = OctTreeQuantizer.init(helpers.zigimg_test_allocator);
    defer quantizer.deinit();

    var colorIt = image.iterator();

    while (colorIt.next()) |pixel| {
        try quantizer.addColor(pixel.toPremultipliedAlpha().toRgba32());
    }

    var paletteStorage: [256]color.Rgba32 = undefined;
    var palette = try quantizer.makePalette(255, paletteStorage[0..]);
    try helpers.expectEq(palette.len, 255);

    var paletteIndex = try quantizer.getPaletteIndex(color.Rgba32.initRgba(110, 0, 0, 255));
    try helpers.expectEq(paletteIndex, 93);
    try helpers.expectEq(palette[93].r, 110);
    try helpers.expectEq(palette[93].g, 2);
    try helpers.expectEq(palette[93].b, 2);
    try helpers.expectEq(palette[93].a, 255);

    var secondPaletteIndex = try quantizer.getPaletteIndex(color.Rgba32.initRgba(0, 0, 119, 255));
    try helpers.expectEq(secondPaletteIndex, 53);
    try helpers.expectEq(palette[53].r, 0);
    try helpers.expectEq(palette[53].g, 0);
    try helpers.expectEq(palette[53].b, 117);
    try helpers.expectEq(palette[53].a, 255);
}
