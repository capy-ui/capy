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

    var pixels_opt: ?color.PixelStorage = null;
    const invalidFile = jpeg_file.read(&stream_source, &pixels_opt);
    defer {
        if (pixels_opt) |pixels| {
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

    var pixels_opt: ?color.PixelStorage = null;
    const frame = try jpeg_file.read(&stream_source, &pixels_opt);

    defer {
        if (pixels_opt) |pixels| {
            pixels.deinit(helpers.zigimg_test_allocator);
        }
    }

    try helpers.expectEq(frame.frame_header.row_count, 8);
    try helpers.expectEq(frame.frame_header.samples_per_row, 16);
    try helpers.expectEq(frame.frame_header.sample_precision, 8);
    try helpers.expectEq(frame.frame_header.components.len, 3);

    try testing.expect(pixels_opt != null);

    if (pixels_opt) |pixels| {
        try testing.expect(pixels == .rgb24);
    }
}

test "Read the tuba properly" {
    const file = try helpers.testOpenFile(helpers.fixtures_path ++ "jpeg/tuba.jpg");
    defer file.close();

    var stream_source = std.io.StreamSource{ .file = file };

    var jpeg_file = jpeg.JPEG.init(helpers.zigimg_test_allocator);
    defer jpeg_file.deinit();

    var pixels_opt: ?color.PixelStorage = null;
    const frame = try jpeg_file.read(&stream_source, &pixels_opt);

    defer {
        if (pixels_opt) |pixels| {
            pixels.deinit(helpers.zigimg_test_allocator);
        }
    }

    try helpers.expectEq(frame.frame_header.row_count, 512);
    try helpers.expectEq(frame.frame_header.samples_per_row, 512);
    try helpers.expectEq(frame.frame_header.sample_precision, 8);
    try helpers.expectEq(frame.frame_header.components.len, 3);

    try testing.expect(pixels_opt != null);

    if (pixels_opt) |pixels| {
        try testing.expect(pixels == .rgb24);

        // Just for fun, let's sample a few pixels. :^)
        try helpers.expectEq(pixels.rgb24[(126 * 512 + 163)], color.Rgb24.initRgb(0xAC, 0x78, 0x54));
        try helpers.expectEq(pixels.rgb24[(265 * 512 + 284)], color.Rgb24.initRgb(0x37, 0x30, 0x33));
        try helpers.expectEq(pixels.rgb24[(431 * 512 + 300)], color.Rgb24.initRgb(0xFE, 0xE7, 0xC9));
    }
}

test "Read grayscale images" {
    const file = try helpers.testOpenFile(helpers.fixtures_path ++ "jpeg/grayscale_sample0.jpg");
    defer file.close();

    var stream_source = std.io.StreamSource{ .file = file };

    var jpeg_file = jpeg.JPEG.init(helpers.zigimg_test_allocator);
    defer jpeg_file.deinit();

    var pixels_opt: ?color.PixelStorage = null;
    const frame = try jpeg_file.read(&stream_source, &pixels_opt);

    defer {
        if (pixels_opt) |pixels| {
            pixels.deinit(helpers.zigimg_test_allocator);
        }
    }

    try helpers.expectEq(frame.frame_header.row_count, 32);
    try helpers.expectEq(frame.frame_header.samples_per_row, 32);
    try helpers.expectEq(frame.frame_header.sample_precision, 8);
    try helpers.expectEq(frame.frame_header.components.len, 1);

    try testing.expect(pixels_opt != null);

    if (pixels_opt) |pixels| {
        try testing.expect(pixels == .grayscale8);

        // Just for fun, let's sample a few pixels. :^)
        try helpers.expectEq(pixels.grayscale8[(0 * 32 + 0)], color.Grayscale8{ .value = 0x00 });
        try helpers.expectEq(pixels.grayscale8[(15 * 32 + 15)], color.Grayscale8{ .value = 0xaa });
        try helpers.expectEq(pixels.grayscale8[(28 * 32 + 28)], color.Grayscale8{ .value = 0xf7 });
    }
}

test "Read subsampling images" {
    var testdir = std.fs.cwd().openDir(helpers.fixtures_path ++ "jpeg/", .{ .access_sub_paths = false, .no_follow = true, .iterate = true }) catch null;
    if (testdir) |*idir| {
        defer idir.close();

        var it = idir.iterate();
        std.debug.print("\n", .{});
        while (try it.next()) |entry| {
            if (entry.kind != .file or !std.mem.endsWith(u8, entry.name, ".jpg") or !std.mem.startsWith(u8, entry.name, "subsampling_")) continue;

            std.debug.print("Testing file {s} ... ", .{entry.name});
            var tst_file = try idir.openFile(entry.name, .{ .mode = .read_only });
            defer tst_file.close();

            var stream = Image.Stream{ .file = tst_file };

            var jpeg_file = jpeg.JPEG.init(helpers.zigimg_test_allocator);
            defer jpeg_file.deinit();

            var pixels_opt: ?color.PixelStorage = null;
            _ = try jpeg_file.read(&stream, &pixels_opt);

            defer {
                if (pixels_opt) |pixels| {
                    pixels.deinit(helpers.zigimg_test_allocator);
                }
            }

            try testing.expect(pixels_opt != null);
            if (pixels_opt) |pixels| {
                try testing.expect(pixels == .rgb24);

                // Just for fun, let's sample a few pixels. :^)
                const actual: color.Colorf32 = pixels.rgb24[(0 * 32 + 0)].toColorf32();
                try testing.expectApproxEqAbs(@as(f32, 1.0), actual.r, 0.05);
                try testing.expectApproxEqAbs(@as(f32, 1.0), actual.g, 0.05);
                try testing.expectApproxEqAbs(@as(f32, 0.0), actual.b, 0.05);

                const actual1: color.Colorf32 = pixels.rgb24[(13 * 32 + 9)].toColorf32();
                try testing.expectApproxEqAbs(@as(f32, 0.71), actual1.r, 0.05);
                try testing.expectApproxEqAbs(@as(f32, 0.55), actual1.g, 0.05);
                try testing.expectApproxEqAbs(@as(f32, 0.0), actual1.b, 0.05);

                const actual2: color.Colorf32 = pixels.rgb24[(25 * 32 + 18)].toColorf32();
                try testing.expectApproxEqAbs(@as(f32, 0.42), actual2.r, 0.05);
                try testing.expectApproxEqAbs(@as(f32, 0.19), actual2.g, 0.05);
                try testing.expectApproxEqAbs(@as(f32, 0.39), actual2.b, 0.05);
            }
            std.debug.print("OK\n", .{});
        }
    }
}
