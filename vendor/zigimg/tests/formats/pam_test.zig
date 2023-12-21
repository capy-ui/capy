const std = @import("std");
const color = @import("../../src/color.zig");
const pam = @import("../../src/formats/pam.zig");
const PixelFormat = @import("../../src/pixel_format.zig").PixelFormat;
const Image = @import("../../src/Image.zig");
const helpers = @import("../helpers.zig");

test "rejects non-PAM images" {
    const file = try helpers.testOpenFile(helpers.fixtures_path ++ "bmp/simple_v4.bmp");
    defer file.close();

    var stream_source = std.io.StreamSource{ .file = file };

    const invalid = pam.PAM.readImage(helpers.zigimg_test_allocator, &stream_source);

    try helpers.expectError(invalid, Image.ReadError.InvalidData);
}

test "rejects PAM images with unsupported depth" {
    const file = try helpers.testOpenFile(helpers.fixtures_path ++ "pam/unsupported_depth.pam");
    defer file.close();

    var stream_source = std.io.StreamSource{ .file = file };

    const invalid = pam.PAM.readImage(helpers.zigimg_test_allocator, &stream_source);

    try helpers.expectError(invalid, Image.ReadError.Unsupported);
}

test "rejects PAM images with invalid maxval" {
    const file = try helpers.testOpenFile(helpers.fixtures_path ++ "pam/invalid_maxval.pam");
    defer file.close();

    var stream_source = std.io.StreamSource{ .file = file };

    const invalid = pam.PAM.readImage(helpers.zigimg_test_allocator, &stream_source);

    try helpers.expectError(invalid, Image.ReadError.InvalidData);
}

test "rejects PAM images with component values greater than maxval" {
    const file = try helpers.testOpenFile(helpers.fixtures_path ++ "pam/value_greater_than_maxval.pam");
    defer file.close();

    var stream_source = std.io.StreamSource{ .file = file };

    const invalid = pam.PAM.readImage(helpers.zigimg_test_allocator, &stream_source);
    try helpers.expectError(invalid, Image.ReadError.InvalidData);
}

test "rejects PAM images with unknown tuple type" {
    const file = try helpers.testOpenFile(helpers.fixtures_path ++ "pam/unknown_tupletype.pam");
    defer file.close();

    var stream_source = std.io.StreamSource{ .file = file };

    const invalid = pam.PAM.readImage(helpers.zigimg_test_allocator, &stream_source);

    try helpers.expectError(invalid, Image.ReadError.Unsupported);
}

test "rejects PAM images with invalid first token" {
    const file = try helpers.testOpenFile(helpers.fixtures_path ++ "pam/invalid_first_token.pam");
    defer file.close();

    var stream_source = std.io.StreamSource{ .file = file };

    const invalid = pam.PAM.readImage(helpers.zigimg_test_allocator, &stream_source);

    try helpers.expectError(invalid, Image.ReadError.InvalidData);
}

test "rejects PAM images with tuple type not matching other parameters" {
    const file = try helpers.testOpenFile(helpers.fixtures_path ++ "pam/non_matching_tuple_type.pam");
    defer file.close();

    var stream_source = std.io.StreamSource{ .file = file };

    const invalid = pam.PAM.readImage(helpers.zigimg_test_allocator, &stream_source);

    try helpers.expectError(invalid, Image.ReadError.InvalidData);
}

test "accepts comments" {
    const file = try helpers.testOpenFile(helpers.fixtures_path ++ "pam/simple_blackandwhite_comments.pam");
    defer file.close();
    var stream_source = std.io.StreamSource{ .file = file };

    var image = try pam.PAM.readImage(helpers.zigimg_test_allocator, &stream_source);
    defer image.deinit();

    try std.testing.expectEqual(@as(usize, 4), image.height);
    try std.testing.expectEqual(@as(usize, 4), image.width);
    try helpers.expectEqSlice(color.Grayscale1, image.pixels.grayscale1, &[16]color.Grayscale1{
        // zig fmt: off
        .{.value = 1}, .{.value = 0}, .{.value = 1}, .{.value = 0},
        .{.value = 0}, .{.value = 1}, .{.value = 0}, .{.value = 1},
        .{.value = 1}, .{.value = 0}, .{.value = 1}, .{.value = 0},
        .{.value = 0}, .{.value = 1}, .{.value = 0}, .{.value = 1},
        // zig fmt: on
    });
}

test "reads blackandwhite pam" {
    const file = try helpers.testOpenFile(helpers.fixtures_path ++ "pam/simple_blackandwhite.pam");
    defer file.close();
    var stream_source = std.io.StreamSource{ .file = file };

    var image = try pam.PAM.readImage(helpers.zigimg_test_allocator, &stream_source);
    defer image.deinit();

    try std.testing.expectEqual(@as(usize, 4), image.height);
    try std.testing.expectEqual(@as(usize, 4), image.width);
    try helpers.expectEqSlice(color.Grayscale1, image.pixels.grayscale1, &[16]color.Grayscale1{
        // zig fmt: off
        .{.value = 1}, .{.value = 0}, .{.value = 1}, .{.value = 0},
        .{.value = 0}, .{.value = 1}, .{.value = 0}, .{.value = 1},
        .{.value = 1}, .{.value = 0}, .{.value = 1}, .{.value = 0},
        .{.value = 0}, .{.value = 1}, .{.value = 0}, .{.value = 1},
        // zig fmt: on
    });
}

test "reads blackandwhite_alpha pam" {
    const file = try helpers.testOpenFile(helpers.fixtures_path ++ "pam/simple_blackandwhite_alpha.pam");
    defer file.close();
    var stream_source = std.io.StreamSource{ .file = file };

    var image = try pam.PAM.readImage(helpers.zigimg_test_allocator, &stream_source);
    defer image.deinit();

    try std.testing.expectEqual(@as(usize, 4), image.height);
    try std.testing.expectEqual(@as(usize, 4), image.width);
    try helpers.expectEqSlice(color.Grayscale1, image.pixels.grayscale1, &[16]color.Grayscale1{
        // zig fmt: off
        .{.value = 1}, .{.value = 0}, .{.value = 0}, .{.value = 0},
        .{.value = 1}, .{.value = 0}, .{.value = 0}, .{.value = 0},
        .{.value = 1}, .{.value = 0}, .{.value = 0}, .{.value = 0},
        .{.value = 1}, .{.value = 0}, .{.value = 0}, .{.value = 0},
        // zig fmt: on
    });
}

test "reads grayscale pam with maxval 255" {
    const file = try helpers.testOpenFile(helpers.fixtures_path ++ "pam/simple_grayscale_maxval_255.pam");
    defer file.close();
    var stream_source = std.io.StreamSource{ .file = file };

    var image = try pam.PAM.readImage(helpers.zigimg_test_allocator, &stream_source);
    defer image.deinit();

    try std.testing.expectEqual(@as(usize, 4), image.height);
    try std.testing.expectEqual(@as(usize, 4), image.width);
    try helpers.expectEqSlice(color.Grayscale8, image.pixels.grayscale8, &[16]color.Grayscale8{
        // zig fmt: off
        .{.value = 0x68}, .{.value = 0x61}, .{.value = 0x68}, .{.value = 0x61},
        .{.value = 0x20}, .{.value = 0x72}, .{.value = 0x65}, .{.value = 0x64},
        .{.value = 0x20}, .{.value = 0x73}, .{.value = 0x75}, .{.value = 0x73},
        .{.value = 0x2c}, .{.value = 0x20}, .{.value = 0x66}, .{.value = 0x6f},
        // zig fmt: on
    });
}

test "reads grayscale alpha pam with maxval 255" {
    const file = try helpers.testOpenFile(helpers.fixtures_path ++ "pam/simple_grayscale_alpha_maxval_255.pam");
    defer file.close();
    var stream_source = std.io.StreamSource{ .file = file };

    var image = try pam.PAM.readImage(helpers.zigimg_test_allocator, &stream_source);
    defer image.deinit();

    try std.testing.expectEqual(@as(usize, 4), image.height);
    try std.testing.expectEqual(@as(usize, 4), image.width);
    try helpers.expectEqSlice(color.Grayscale8Alpha, image.pixels.grayscale8Alpha, &[16]color.Grayscale8Alpha{
        // zig fmt: off
        .{.value = 0x68, .alpha = 0x61}, .{.value = 0x68, .alpha = 0x61}, .{.value = 0x20, .alpha = 0x72}, .{.value = 0x65, .alpha = 0x64},
        .{.value = 0x20, .alpha = 0x73}, .{.value = 0x75, .alpha = 0x73}, .{.value = 0x2c, .alpha = 0x20}, .{.value = 0x66, .alpha = 0x6f},
        .{.value = 0x6f, .alpha = 0x20}, .{.value = 0x62, .alpha = 0x61}, .{.value = 0x72, .alpha = 0x20}, .{.value = 0x62, .alpha = 0x61},
        .{.value = 0x7a, .alpha = 0x20}, .{.value = 0x71, .alpha = 0x75}, .{.value = 0x75, .alpha = 0x78}, .{.value = 0x20, .alpha = 0x65},
        // zig fmt: on
    });
}

test "read of rgb pam with maxval 255" {
    const file = try helpers.testOpenFile(helpers.fixtures_path ++ "pam/horse.pam");
    defer file.close();
    var stream_source = std.io.StreamSource{ .file = file };

    var image = try pam.PAM.readImage(helpers.zigimg_test_allocator, &stream_source);
    defer image.deinit();

    try std.testing.expectEqual(@as(usize, 843750), image.pixels.len());
}

test "basic read-write-read produces same result" {
    const file = try helpers.testOpenFile(helpers.fixtures_path ++ "pam/simple_grayscale_alpha_maxval_255.pam");
    defer file.close();
    var stream_source = std.io.StreamSource{ .file = file };

    var image = try pam.PAM.readImage(helpers.zigimg_test_allocator, &stream_source);
    defer image.deinit();

    try std.testing.expectEqual(@as(usize, 4), image.height);
    try std.testing.expectEqual(@as(usize, 4), image.width);
    try helpers.expectEqSlice(color.Grayscale8Alpha, image.pixels.grayscale8Alpha, &[16]color.Grayscale8Alpha{
        // zig fmt: off
        .{.value = 0x68, .alpha = 0x61}, .{.value = 0x68, .alpha = 0x61}, .{.value = 0x20, .alpha = 0x72}, .{.value = 0x65, .alpha = 0x64},
        .{.value = 0x20, .alpha = 0x73}, .{.value = 0x75, .alpha = 0x73}, .{.value = 0x2c, .alpha = 0x20}, .{.value = 0x66, .alpha = 0x6f},
        .{.value = 0x6f, .alpha = 0x20}, .{.value = 0x62, .alpha = 0x61}, .{.value = 0x72, .alpha = 0x20}, .{.value = 0x62, .alpha = 0x61},
        .{.value = 0x7a, .alpha = 0x20}, .{.value = 0x71, .alpha = 0x75}, .{.value = 0x75, .alpha = 0x78}, .{.value = 0x20, .alpha = 0x65},
        // zig fmt: on
    });

    var buf: [8192]u8 = undefined;
    var s = Image.Stream{
        .buffer = std.io.fixedBufferStream(&buf),
    };

    try pam.PAM.writeImage(helpers.zigimg_test_allocator, &s, image, .{.pam = .{}});
    s.buffer = std.io.fixedBufferStream(s.buffer.getWritten());

    var decoded_image = try pam.PAM.readImage(helpers.zigimg_test_allocator, &s);
    defer decoded_image.deinit();
    try std.testing.expectEqual(@as(usize, 4), decoded_image.height);
    try std.testing.expectEqual(@as(usize, 4), decoded_image.width);
    try helpers.expectEqSlice(color.Grayscale8Alpha, decoded_image.pixels.grayscale8Alpha, &[16]color.Grayscale8Alpha{
        // zig fmt: off
        .{.value = 0x68, .alpha = 0x61}, .{.value = 0x68, .alpha = 0x61}, .{.value = 0x20, .alpha = 0x72}, .{.value = 0x65, .alpha = 0x64},
        .{.value = 0x20, .alpha = 0x73}, .{.value = 0x75, .alpha = 0x73}, .{.value = 0x2c, .alpha = 0x20}, .{.value = 0x66, .alpha = 0x6f},
        .{.value = 0x6f, .alpha = 0x20}, .{.value = 0x62, .alpha = 0x61}, .{.value = 0x72, .alpha = 0x20}, .{.value = 0x62, .alpha = 0x61},
        .{.value = 0x7a, .alpha = 0x20}, .{.value = 0x71, .alpha = 0x75}, .{.value = 0x75, .alpha = 0x78}, .{.value = 0x20, .alpha = 0x65},
        // zig fmt: on
    });

}

test "reads rgba pam with maxval 255" {
    const file = try helpers.testOpenFile(helpers.fixtures_path ++ "pam/simple_rgba_maxval_255.pam");
    defer file.close();
    var stream_source = std.io.StreamSource{ .file = file };

    var image = try pam.PAM.readImage(helpers.zigimg_test_allocator, &stream_source);
    defer image.deinit();

    try std.testing.expectEqual(@as(usize, 4), image.pixels.len());
    try helpers.expectEqSlice(color.Rgba32, image.pixels.rgba32, &[4]color.Rgba32{
        .{.r = 'a', .g = 'b', .b = 'c', .a = 'd'},
        .{.r = 'e', .g = 'f', .b = 'g', .a = 'h'},
        .{.r = 'i', .g = 'j', .b = 'k', .a = 'l'},
        .{.r = 'm', .g = 'n', .b = 'o', .a = 'p'},
    });
}

test "reads rgba pam with maxval 65535" {
    const file = try helpers.testOpenFile(helpers.fixtures_path ++ "pam/simple_rgba_maxval_65535.pam");
    defer file.close();
    var stream_source = std.io.StreamSource{ .file = file };

    var image = try pam.PAM.readImage(helpers.zigimg_test_allocator, &stream_source);
    defer image.deinit();

    try std.testing.expectEqual(@as(usize, 4), image.pixels.len());
    try helpers.expectEqSlice(color.Rgba64, image.pixels.rgba64, &[4]color.Rgba64{
        .{ .r = 25185, .g = 25699, .b = 26213, .a = 26727 },
        .{ .r = 27241, .g = 27755, .b = 28269, .a = 28783 },
        .{ .r = 29297, .g = 29811, .b = 30325, .a = 30839 },
        .{ .r = 31353, .g = 31867, .b = 32381, .a = 49791 },
    });
}
