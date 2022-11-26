const std = @import("std");
const testing = std.testing;
const color = @import("../src/color.zig");
const helpers = @import("helpers.zig");

test "Convert color to premultipled alpha" {
    const originalColor = color.Colorf32.initRgba(100 / 255, 128 / 255, 210 / 255, 100 / 255);
    const premultipliedAlpha = originalColor.toPremultipliedAlpha();

    try helpers.expectEq(premultipliedAlpha.r, 39 / 255);
    try helpers.expectEq(premultipliedAlpha.g, 50 / 255);
    try helpers.expectEq(premultipliedAlpha.b, 82 / 255);
    try helpers.expectEq(premultipliedAlpha.a, 100 / 255);

    const expectedRgba32 = premultipliedAlpha.toRgba32();
    const originalRgba32 = originalColor.toRgba32();
    const premultipliedAlphaRgba32 = originalRgba32.toPremultipliedAlpha();
    try helpers.expectEq(premultipliedAlphaRgba32, expectedRgba32);

    const expectedRgba64 = premultipliedAlpha.toRgba64();
    const originalRgba64 = originalColor.toRgba64();
    const premultipliedAlphaRgba64 = originalRgba64.toPremultipliedAlpha();
    try helpers.expectEq(premultipliedAlphaRgba64, expectedRgba64);
}

test "Convert Rgb24 to Colorf32" {
    const originalColor = color.Rgb24.initRgb(100, 128, 210);
    const result = originalColor.toColorf32().toRgba32();

    try helpers.expectEq(result.r, 100);
    try helpers.expectEq(result.g, 128);
    try helpers.expectEq(result.b, 210);
    try helpers.expectEq(result.a, 255);
}

test "Convert Rgb48 to Colorf32" {
    const originalColor = color.Rgb48.initRgb(25500, 32640, 53550);
    const result = originalColor.toColorf32().toRgba64();

    try helpers.expectEq(result.r, 25500);
    try helpers.expectEq(result.g, 32640);
    try helpers.expectEq(result.b, 53550);
    try helpers.expectEq(result.a, 65535);
}

test "Convert Rgba32 to Colorf32" {
    const originalColor = color.Rgba32.initRgba(1, 2, 3, 4);
    const result = originalColor.toColorf32().toRgba32();

    try helpers.expectEq(result.r, 1);
    try helpers.expectEq(result.g, 2);
    try helpers.expectEq(result.b, 3);
    try helpers.expectEq(result.a, 4);
}

test "Convert Rgba64 to Colorf32" {
    const originalColor = color.Rgba64.initRgba(1, 2, 3, 4);
    const result = originalColor.toColorf32().toRgba64();

    try helpers.expectEq(result.r, 1);
    try helpers.expectEq(result.g, 2);
    try helpers.expectEq(result.b, 3);
    try helpers.expectEq(result.a, 4);
}

test "Convert Rgb565 to Colorf32" {
    const originalColor = color.Rgb565.initRgb(10, 30, 20);
    const result = originalColor.toColorf32().toRgba32();

    try helpers.expectEq(result.r, 82);
    try helpers.expectEq(result.g, 121);
    try helpers.expectEq(result.b, 165);
    try helpers.expectEq(result.a, 255);
}

test "Convert Rgb555 to Colorf32" {
    const originalColor = color.Rgb555.initRgb(16, 20, 24);
    const result = originalColor.toColorf32().toRgba32();

    try helpers.expectEq(result.r, 132);
    try helpers.expectEq(result.g, 165);
    try helpers.expectEq(result.b, 197);
    try helpers.expectEq(result.a, 255);
}

test "Convert Bgra32 to Colorf32" {
    const originalColor = color.Bgra32.initRgba(50, 100, 150, 200);
    const result = originalColor.toColorf32().toRgba32();

    try helpers.expectEq(result.r, 50);
    try helpers.expectEq(result.g, 100);
    try helpers.expectEq(result.b, 150);
    try helpers.expectEq(result.a, 200);
}

test "Convert Grayscale1 to Colorf32" {
    const white = color.Grayscale1{ .value = 1 };
    const whiteColor = white.toColorf32().toRgba32();

    try helpers.expectEq(whiteColor.r, 255);
    try helpers.expectEq(whiteColor.g, 255);
    try helpers.expectEq(whiteColor.b, 255);
    try helpers.expectEq(whiteColor.a, 255);

    const black = color.Grayscale1{ .value = 0 };
    const blackColor = black.toColorf32().toRgba32();

    try helpers.expectEq(blackColor.r, 0);
    try helpers.expectEq(blackColor.g, 0);
    try helpers.expectEq(blackColor.b, 0);
    try helpers.expectEq(blackColor.a, 255);
}

test "Convert Grayscale8 to Colorf32" {
    const original = color.Grayscale8{ .value = 128 };
    const result = original.toColorf32().toRgba32();

    try helpers.expectEq(result.r, 128);
    try helpers.expectEq(result.g, 128);
    try helpers.expectEq(result.b, 128);
    try helpers.expectEq(result.a, 255);
}

test "Convert Grayscale16 to Colorf32" {
    const original = color.Grayscale16{ .value = 21845 };
    const result = original.toColorf32().toRgba32();

    try helpers.expectEq(result.r, 85);
    try helpers.expectEq(result.g, 85);
    try helpers.expectEq(result.b, 85);
    try helpers.expectEq(result.a, 255);
}

test "Rgb from and to U32" {
    const expected = color.Rgba32.initRgba(0x87, 0x63, 0x47, 0xff);
    const actualU32 = expected.toU32Rgba();
    const actual = color.Rgba32.fromU32Rgba(actualU32);

    try helpers.expectEq(actualU32, 0x876347FF);
    try helpers.expectEq(actual, expected);

    const actualRgb = color.Rgba32.fromU32Rgb(0x876347);

    try helpers.expectEq(actualRgb.r, 0x87);
    try helpers.expectEq(actualRgb.g, 0x63);
    try helpers.expectEq(actualRgb.b, 0x47);
    try helpers.expectEq(actualRgb.a, 0xff);
}

test "toIntColor" {
    try helpers.expectEq(color.toIntColor(u8, 0), 0);
    try helpers.expectEq(color.toIntColor(u8, 0.33), 84);
    try helpers.expectEq(color.toIntColor(u8, 1), 255);
    try helpers.expectEq(color.toIntColor(u8, 1.33), 255);
    try helpers.expectEq(color.toIntColor(u8, -0.33), 0);

    try helpers.expectEq(color.toIntColor(u16, 0), 0);
    try helpers.expectEq(color.toIntColor(u16, 0.33), 21627);
    try helpers.expectEq(color.toIntColor(u16, 1), 65535);
    try helpers.expectEq(color.toIntColor(u16, 1.33), 65535);
    try helpers.expectEq(color.toIntColor(u16, -0.33), 0);
}

test "Colorf32.toFromU32Rgba()" {
    const expected_u32 = [_]u32{ 0xb7e795d2, 0x9967044f, 0xefa1f714, 0x26ce0589, 0xf50f68ea };
    const expected_c32 = [_]color.Colorf32{
        color.Colorf32.initRgba(0xb7.0 / 255.0, 0xe7.0 / 255.0, 0x95.0 / 255.0, 0xd2.0 / 255.0),
        color.Colorf32.initRgba(0x99.0 / 255.0, 0x67.0 / 255.0, 0x04.0 / 255.0, 0x4f.0 / 255.0),
        color.Colorf32.initRgba(0xef.0 / 255.0, 0xa1.0 / 255.0, 0xf7.0 / 255.0, 0x14.0 / 255.0),
        color.Colorf32.initRgba(0x26.0 / 255.0, 0xce.0 / 255.0, 0x05.0 / 255.0, 0x89.0 / 255.0),
        color.Colorf32.initRgba(0xf5.0 / 255.0, 0x0f.0 / 255.0, 0x68.0 / 255.0, 0xea.0 / 255.0),
    };
    for (expected_u32) |expected, i| {
        const actual = color.Colorf32.fromU32Rgba(expected);
        try helpers.expectEq(actual, expected_c32[i]);
        try helpers.expectEq(actual.toU32Rgba(), expected);
    }
}

test "Colorf32.toFromU64Rgba()" {
    const expected_u64 = [_]u64{ 0xf034da495288b4f0, 0x8f43957daf1fad51, 0xb2c84b7efea70316, 0x68bb87b393a1c104, 0x48b7f617a4520099 };
    const expected_c32 = [_]color.Colorf32{
        color.Colorf32.initRgba(0xf034.0 / 65535.0, 0xda49.0 / 65535.0, 0x5288.0 / 65535.0, 0xb4f0.0 / 65535.0),
        color.Colorf32.initRgba(0x8f43.0 / 65535.0, 0x957d.0 / 65535.0, 0xaf1f.0 / 65535.0, 0xad51.0 / 65535.0),
        color.Colorf32.initRgba(0xb2c8.0 / 65535.0, 0x4b7e.0 / 65535.0, 0xfea7.0 / 65535.0, 0x0316.0 / 65535.0),
        color.Colorf32.initRgba(0x68bb.0 / 65535.0, 0x87b3.0 / 65535.0, 0x93a1.0 / 65535.0, 0xc104.0 / 65535.0),
        color.Colorf32.initRgba(0x48b7.0 / 65535.0, 0xf617.0 / 65535.0, 0xa452.0 / 65535.0, 0x0099.0 / 65535.0),
    };
    for (expected_u64) |expected, i| {
        const actual = color.Colorf32.fromU64Rgba(expected);
        try helpers.expectEq(actual, expected_c32[i]);
        try helpers.expectEq(actual.toU64Rgba(), expected);
    }
}

test "Rgb.toFromU32Rgba()" {
    const expected_u32 = [_]u32{ 0xb7e795d2, 0x9967044f, 0xefa1f714, 0x26ce0589, 0xf50f68ea };
    const expected_rgb24_from_rgba = [_]color.Rgb24{
        color.Rgb24.initRgb(0xb7, 0xe7, 0x95),
        color.Rgb24.initRgb(0x99, 0x67, 0x04),
        color.Rgb24.initRgb(0xef, 0xa1, 0xf7),
        color.Rgb24.initRgb(0x26, 0xce, 0x05),
        color.Rgb24.initRgb(0xf5, 0x0f, 0x68),
    };
    const expected_rgb24_from_rgb = [_]color.Rgb24{
        color.Rgb24.initRgb(0xe7, 0x95, 0xd2),
        color.Rgb24.initRgb(0x67, 0x04, 0x4f),
        color.Rgb24.initRgb(0xa1, 0xf7, 0x14),
        color.Rgb24.initRgb(0xce, 0x05, 0x89),
        color.Rgb24.initRgb(0x0f, 0x68, 0xea),
    };
    const expected_rgb555_from_rgb = [_]color.Rgb555{
        color.Rgb555.initRgb(0xe7 >> 3, 0x95 >> 3, 0xd2 >> 3),
        color.Rgb555.initRgb(0x67 >> 3, 0x04 >> 3, 0x4f >> 3),
        color.Rgb555.initRgb(0xa1 >> 3, 0xf7 >> 3, 0x14 >> 3),
        color.Rgb555.initRgb(0xce >> 3, 0x05 >> 3, 0x89 >> 3),
        color.Rgb555.initRgb(0x0f >> 3, 0x68 >> 3, 0xea >> 3),
    };
    const expected_rgb565_from_rgb = [_]color.Rgb565{
        color.Rgb565.initRgb(0xe7 >> 3, 0x95 >> 2, 0xd2 >> 3),
        color.Rgb565.initRgb(0x67 >> 3, 0x04 >> 2, 0x4f >> 3),
        color.Rgb565.initRgb(0xa1 >> 3, 0xf7 >> 2, 0x14 >> 3),
        color.Rgb565.initRgb(0xce >> 3, 0x05 >> 2, 0x89 >> 3),
        color.Rgb565.initRgb(0x0f >> 3, 0x68 >> 2, 0xea >> 3),
    };

    const expected_colorf32 = [_]color.Colorf32{
        expected_rgb24_from_rgba[0].toColorf32(),
        expected_rgb24_from_rgba[1].toColorf32(),
        expected_rgb24_from_rgba[2].toColorf32(),
        expected_rgb24_from_rgba[3].toColorf32(),
        expected_rgb24_from_rgba[4].toColorf32(),
    };

    const expected_rgb48_from_rgba = [_]color.Rgb48{
        color.Rgb48.initRgb(0xb7 * 257, 0xe7 * 257, 0x95 * 257),
        color.Rgb48.initRgb(0x99 * 257, 0x67 * 257, 0x04 * 257),
        color.Rgb48.initRgb(0xef * 257, 0xa1 * 257, 0xf7 * 257),
        color.Rgb48.initRgb(0x26 * 257, 0xce * 257, 0x05 * 257),
        color.Rgb48.initRgb(0xf5 * 257, 0x0f * 257, 0x68 * 257),
    };
    const expected_rgb48_from_rgb = [_]color.Rgb48{
        color.Rgb48.initRgb(0xe7 * 257, 0x95 * 257, 0xd2 * 257),
        color.Rgb48.initRgb(0x67 * 257, 0x04 * 257, 0x4f * 257),
        color.Rgb48.initRgb(0xa1 * 257, 0xf7 * 257, 0x14 * 257),
        color.Rgb48.initRgb(0xce * 257, 0x05 * 257, 0x89 * 257),
        color.Rgb48.initRgb(0x0f * 257, 0x68 * 257, 0xea * 257),
    };
    for (expected_u32) |expected, i| {
        const actual24_from_rgba = color.Rgb24.fromU32Rgba(expected);
        try helpers.expectEq(actual24_from_rgba, expected_rgb24_from_rgba[i]);
        try helpers.expectEq(actual24_from_rgba.toU32Rgba(), expected | 0xff);
        const actual24_from_rgb = color.Rgb24.fromU32Rgb(expected);
        try helpers.expectEq(actual24_from_rgb, expected_rgb24_from_rgb[i]);
        try helpers.expectEq(actual24_from_rgb.toU32Rgba(), expected << 8 | 0xff);
        const actual555_from_rgb = color.Rgb555.fromU32Rgb(expected);
        try helpers.expectEq(actual555_from_rgb, expected_rgb555_from_rgb[i]);
        try helpers.expectEq(actual555_from_rgb.toU32Rgba(), expected_rgb555_from_rgb[i].toColorf32().toU32Rgba());
        const actual565_from_rgb = color.Rgb565.fromU32Rgb(expected);
        try helpers.expectEq(actual565_from_rgb, expected_rgb565_from_rgb[i]);
        try helpers.expectEq(actual565_from_rgb.toU32Rgba(), expected_rgb565_from_rgb[i].toColorf32().toU32Rgba());

        // We make sure that conversion through u32 give the same result as through f32
        try helpers.expectEq(actual24_from_rgba.toU32Rgba(), expected_colorf32[i].toU32Rgba());

        const actual48_from_rgba = color.Rgb48.fromU32Rgba(expected);
        try helpers.expectEq(actual48_from_rgba, expected_rgb48_from_rgba[i]);
        try helpers.expectEq(actual48_from_rgba.toU32Rgba(), expected | 0xff);
        const actual48_from_rgb = color.Rgb48.fromU32Rgb(expected);
        try helpers.expectEq(actual48_from_rgb, expected_rgb48_from_rgb[i]);
        try helpers.expectEq(actual48_from_rgb.toU32Rgba(), expected << 8 | 0xff);

        // We make sure that conversion through u64 give the same result as through f32
        try helpers.expectEq(actual48_from_rgba.toU64Rgba(), expected_colorf32[i].toU64Rgba());
    }
}

test "Rgb.toFromU64Rgba()" {
    const expected_u64 = [_]u64{ 0xf034da495288b4f0, 0x8f43957daf1fad51, 0xb2c84b7efea70316, 0x68bb87b393a1c104, 0x48b7f617a4520099 };
    const expected_rgb48_from_rgba = [_]color.Rgb48{
        color.Rgb48.initRgb(0xf034, 0xda49, 0x5288),
        color.Rgb48.initRgb(0x8f43, 0x957d, 0xaf1f),
        color.Rgb48.initRgb(0xb2c8, 0x4b7e, 0xfea7),
        color.Rgb48.initRgb(0x68bb, 0x87b3, 0x93a1),
        color.Rgb48.initRgb(0x48b7, 0xf617, 0xa452),
    };
    const expected_rgb48_from_rgb = [_]color.Rgb48{
        color.Rgb48.initRgb(0xda49, 0x5288, 0xb4f0),
        color.Rgb48.initRgb(0x957d, 0xaf1f, 0xad51),
        color.Rgb48.initRgb(0x4b7e, 0xfea7, 0x0316),
        color.Rgb48.initRgb(0x87b3, 0x93a1, 0xc104),
        color.Rgb48.initRgb(0xf617, 0xa452, 0x0099),
    };

    const expected_colorf32 = [_]color.Colorf32{
        expected_rgb48_from_rgba[0].toColorf32(),
        expected_rgb48_from_rgba[1].toColorf32(),
        expected_rgb48_from_rgba[2].toColorf32(),
        expected_rgb48_from_rgba[3].toColorf32(),
        expected_rgb48_from_rgba[4].toColorf32(),
    };
    for (expected_u64) |expected, i| {
        const actual_from_rgba = color.Rgb48.fromU64Rgba(expected);
        try helpers.expectEq(actual_from_rgba, expected_rgb48_from_rgba[i]);
        try helpers.expectEq(actual_from_rgba.toU64Rgba(), expected | 0xffff);
        const actual_from_rgb = color.Rgb48.fromU64Rgb(expected);
        try helpers.expectEq(actual_from_rgb, expected_rgb48_from_rgb[i]);
        try helpers.expectEq(actual_from_rgb.toU64Rgba(), expected << 16 | 0xffff);

        // We make sure that conversion through u64 give the same result as through f32
        try helpers.expectEq(actual_from_rgba.toU64Rgba(), expected_colorf32[i].toU64Rgba());
    }
}

test "Rgba.toFromU32Rgba()" {
    const expected_u32 = [_]u32{ 0xb7e795d2, 0x9967044f, 0xefa1f714, 0x26ce0589, 0xf50f68ea };
    const expected_rgba32_from_rgba = [_]color.Rgba32{
        color.Rgba32.initRgba(0xb7, 0xe7, 0x95, 0xd2),
        color.Rgba32.initRgba(0x99, 0x67, 0x04, 0x4f),
        color.Rgba32.initRgba(0xef, 0xa1, 0xf7, 0x14),
        color.Rgba32.initRgba(0x26, 0xce, 0x05, 0x89),
        color.Rgba32.initRgba(0xf5, 0x0f, 0x68, 0xea),
    };

    const expected_colorf32 = [_]color.Colorf32{
        expected_rgba32_from_rgba[0].toColorf32(),
        expected_rgba32_from_rgba[1].toColorf32(),
        expected_rgba32_from_rgba[2].toColorf32(),
        expected_rgba32_from_rgba[3].toColorf32(),
        expected_rgba32_from_rgba[4].toColorf32(),
    };

    const expected_rgba64_from_rgba = [_]color.Rgba64{
        color.Rgba64.initRgba(0xb7 * 257, 0xe7 * 257, 0x95 * 257, 0xd2 * 257),
        color.Rgba64.initRgba(0x99 * 257, 0x67 * 257, 0x04 * 257, 0x4f * 257),
        color.Rgba64.initRgba(0xef * 257, 0xa1 * 257, 0xf7 * 257, 0x14 * 257),
        color.Rgba64.initRgba(0x26 * 257, 0xce * 257, 0x05 * 257, 0x89 * 257),
        color.Rgba64.initRgba(0xf5 * 257, 0x0f * 257, 0x68 * 257, 0xea * 257),
    };
    for (expected_u32) |expected, i| {
        const actual32_from_rgba = color.Rgba32.fromU32Rgba(expected);
        try helpers.expectEq(actual32_from_rgba, expected_rgba32_from_rgba[i]);
        try helpers.expectEq(actual32_from_rgba.toU32Rgba(), expected);

        // We make sure that conversion through u32 give the same result as through f32
        try helpers.expectEq(actual32_from_rgba.toU32Rgba(), expected_colorf32[i].toU32Rgba());

        const actual64_from_rgba = color.Rgba64.fromU32Rgba(expected);
        try helpers.expectEq(actual64_from_rgba, expected_rgba64_from_rgba[i]);
        try helpers.expectEq(actual64_from_rgba.toU32Rgba(), expected);

        // We make sure that conversion through u64 give the same result as through f32
        try helpers.expectEq(actual64_from_rgba.toU64Rgba(), expected_colorf32[i].toU64Rgba());
    }
}

test "Rgba.toFromU64Rgba())" {
    const expected_u64 = [_]u64{ 0xf034da495288b4f0, 0x8f43957daf1fad51, 0xb2c84b7efea70316, 0x68bb87b393a1c104, 0x48b7f617a4520099 };
    const expected_rgba64_from_rgba = [_]color.Rgba64{
        color.Rgba64.initRgba(0xf034, 0xda49, 0x5288, 0xb4f0),
        color.Rgba64.initRgba(0x8f43, 0x957d, 0xaf1f, 0xad51),
        color.Rgba64.initRgba(0xb2c8, 0x4b7e, 0xfea7, 0x0316),
        color.Rgba64.initRgba(0x68bb, 0x87b3, 0x93a1, 0xc104),
        color.Rgba64.initRgba(0x48b7, 0xf617, 0xa452, 0x0099),
    };

    const expected_colorf32 = [_]color.Colorf32{
        expected_rgba64_from_rgba[0].toColorf32(),
        expected_rgba64_from_rgba[1].toColorf32(),
        expected_rgba64_from_rgba[2].toColorf32(),
        expected_rgba64_from_rgba[3].toColorf32(),
        expected_rgba64_from_rgba[4].toColorf32(),
    };
    for (expected_u64) |expected, i| {
        const actual_from_rgba = color.Rgba64.fromU64Rgba(expected);
        try helpers.expectEq(actual_from_rgba, expected_rgba64_from_rgba[i]);
        try helpers.expectEq(actual_from_rgba.toU64Rgba(), expected);

        // We make sure that conversion through u64 give the same result as through f32
        try helpers.expectEq(actual_from_rgba.toU64Rgba(), expected_colorf32[i].toU64Rgba());
    }
}

test "Colorf32 from and to [4]f32 array" {
    const expected = [_]f32{ 0.12, 0.34, 0.56, 0.78 };
    const sample = color.Colorf32.fromArray(expected);

    try helpers.expectEq(sample.r, 0.12);
    try helpers.expectEq(sample.g, 0.34);
    try helpers.expectEq(sample.b, 0.56);
    try helpers.expectEq(sample.a, 0.78);
    const actual = sample.toArray();
    try helpers.expectEqSlice(f32, actual[0..], expected[0..]);
}

test "Rgb.fromHtmlHex() with valid inputs" {
    const inputs = [_][]const u8{
        "#fff",
        "#ffffff",
        "#000",
        "#000000",
        "#123456",
        "#123",
        "#AFCDEB",
    };

    const expected_colors = [_]color.Rgb24{
        color.Rgb24.initRgb(0xff, 0xff, 0xff),
        color.Rgb24.initRgb(0xff, 0xff, 0xff),
        color.Rgb24.initRgb(0x00, 0x00, 0x00),
        color.Rgb24.initRgb(0x00, 0x00, 0x00),
        color.Rgb24.initRgb(0x12, 0x34, 0x56),
        color.Rgb24.initRgb(0x11, 0x22, 0x33),
        color.Rgb24.initRgb(0xAF, 0xCD, 0xEB),
    };

    std.debug.assert(inputs.len == expected_colors.len);

    var index: usize = 0;
    while (index < inputs.len) : (index += 1) {
        const actual_color = try color.Rgb24.fromHtmlHex(inputs[index]);

        const expected_color = expected_colors[index];

        try helpers.expectEq(actual_color.r, expected_color.r);
        try helpers.expectEq(actual_color.g, expected_color.g);
        try helpers.expectEq(actual_color.b, expected_color.b);
    }
}

test "Rgba.fromHtmlHex() with valid inputs" {
    const inputs = [_][]const u8{
        "#ffff",
        "#1234",
        "#ffffffff",
        "#12345678",
        "#ABCDEF9D",
        "#fedcba34",
    };

    const expected_colors = [_]color.Rgba32{
        color.Rgba32.initRgba(0xff, 0xff, 0xff, 0xff),
        color.Rgba32.initRgba(0x11, 0x22, 0x33, 0x44),
        color.Rgba32.initRgba(0xff, 0xff, 0xff, 0xff),
        color.Rgba32.initRgba(0x12, 0x34, 0x56, 0x78),
        color.Rgba32.initRgba(0xAB, 0xCD, 0xEF, 0x9D),
        color.Rgba32.initRgba(0xfe, 0xdc, 0xba, 0x34),
    };

    std.debug.assert(inputs.len == expected_colors.len);

    var index: usize = 0;
    while (index < inputs.len) : (index += 1) {
        const actual_color = try color.Rgba32.fromHtmlHex(inputs[index]);

        const expected_color = expected_colors[index];

        try helpers.expectEq(actual_color.r, expected_color.r);
        try helpers.expectEq(actual_color.g, expected_color.g);
        try helpers.expectEq(actual_color.b, expected_color.b);
        try helpers.expectEq(actual_color.a, expected_color.a);
    }
}

test "Rgb.fromHtmlHex() with invalid inputs" {
    const inputs = [_][]const u8{
        "#zzz",
        "#ag",
        "#agerty",
        "zxczfet",
        "ffFFFF",
        "abcdef",
        "123456",
        "",
        "#a",
        "#aaaa", // #RGBA should not be valid with Rgb24
        "#12345678", // #RRGGBBAA should not be valid with Rgb24
    };

    var index: usize = 0;
    while (index < inputs.len) : (index += 1) {
        const actual_error = color.Rgb24.fromHtmlHex(inputs[index]);

        try helpers.expectError(actual_error, error.InvalidHtmlHexString);
    }
}

test "Rgba.fromHtmlHex() with invalid inputs" {
    const inputs = [_][]const u8{
        "#zzz",
        "#ag",
        "#agerty",
        "zxczfet",
        "ffFFFF",
        "abcdef",
        "123456",
        "",
        "#a",
        "#zzzz",
        "12345678",
    };

    var index: usize = 0;
    while (index < inputs.len) : (index += 1) {
        const actual_error = color.Rgba32.fromHtmlHex(inputs[index]);

        try helpers.expectError(actual_error, error.InvalidHtmlHexString);
    }
}

test "u8 Rgb colors should have fromHtmlHex" {
    try helpers.expectEq(@hasDecl(color.Rgb24, "fromHtmlHex"), true);
    try helpers.expectEq(@hasDecl(color.Rgba32, "fromHtmlHex"), true);
    try helpers.expectEq(@hasDecl(color.Bgr24, "fromHtmlHex"), true);
    try helpers.expectEq(@hasDecl(color.Bgra32, "fromHtmlHex"), true);
}

test "Non u8 Rgb colors should not have fromHtmlHex" {
    try helpers.expectEq(@hasDecl(color.Rgb555, "fromHtmlHex"), false);
    try helpers.expectEq(@hasDecl(color.Rgb48, "fromHtmlHex"), false);
    try helpers.expectEq(@hasDecl(color.Rgba64, "fromHtmlHex"), false);
    try helpers.expectEq(@hasDecl(color.Rgb565, "fromHtmlHex"), false);
}
