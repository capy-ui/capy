const std = @import("std");
const Allocator = std.mem.Allocator;

/// Bilinear downscale of an RGBA image.
/// Returns an owned buffer of `dst_w * dst_h * 4` bytes.
pub fn downscaleRGBA(
    src: []const u8,
    src_w: u32,
    src_h: u32,
    dst_w: u32,
    dst_h: u32,
    allocator: Allocator,
) ![]u8 {
    if (dst_w == 0 or dst_h == 0) return error.InvalidDimensions;
    if (src.len < src_w * src_h * 4) return error.InvalidDimensions;

    // Identity case: no scaling needed
    if (src_w == dst_w and src_h == dst_h) {
        const out = try allocator.alloc(u8, dst_w * dst_h * 4);
        @memcpy(out, src[0 .. dst_w * dst_h * 4]);
        return out;
    }

    const out = try allocator.alloc(u8, dst_w * dst_h * 4);
    errdefer allocator.free(out);

    const sx: f64 = @as(f64, @floatFromInt(src_w)) / @as(f64, @floatFromInt(dst_w));
    const sy: f64 = @as(f64, @floatFromInt(src_h)) / @as(f64, @floatFromInt(dst_h));

    for (0..dst_h) |dy| {
        for (0..dst_w) |dx| {
            // Map destination pixel center to source coordinates
            const src_x = (@as(f64, @floatFromInt(dx)) + 0.5) * sx - 0.5;
            const src_y = (@as(f64, @floatFromInt(dy)) + 0.5) * sy - 0.5;

            const x0 = @as(u32, @intFromFloat(@max(0.0, @floor(src_x))));
            const y0 = @as(u32, @intFromFloat(@max(0.0, @floor(src_y))));
            const x1 = @min(x0 + 1, src_w - 1);
            const y1 = @min(y0 + 1, src_h - 1);

            const fx = src_x - @floor(src_x);
            const fy = src_y - @floor(src_y);

            const dst_idx = (dy * dst_w + dx) * 4;
            const src_stride = src_w * 4;

            // Bilinear interpolation for each channel
            for (0..4) |ch| {
                const p00 = @as(f64, @floatFromInt(src[y0 * src_stride + x0 * 4 + ch]));
                const p10 = @as(f64, @floatFromInt(src[y0 * src_stride + x1 * 4 + ch]));
                const p01 = @as(f64, @floatFromInt(src[y1 * src_stride + x0 * 4 + ch]));
                const p11 = @as(f64, @floatFromInt(src[y1 * src_stride + x1 * 4 + ch]));

                const top = p00 * (1.0 - fx) + p10 * fx;
                const bot = p01 * (1.0 - fx) + p11 * fx;
                const val = top * (1.0 - fy) + bot * fy;
                out[dst_idx + ch] = @intFromFloat(@min(255.0, @max(0.0, val + 0.5)));
            }
        }
    }

    return out;
}

/// In-place RGBA → BGRA channel swap (or vice versa, since it's symmetric).
pub fn rgbaToBgra(data: []u8) void {
    var i: usize = 0;
    while (i + 3 < data.len) : (i += 4) {
        const tmp = data[i];
        data[i] = data[i + 2];
        data[i + 2] = tmp;
    }
}

/// Validate that source icon dimensions are suitable (at least 16x16, square).
pub fn validateIconSource(width: u32, height: u32) !void {
    if (width != height) return error.IconNotSquare;
    if (width < 16) return error.IconTooSmall;
}

// ── Tests ──────────────────────────────────────────────────────────────

test "downscaleRGBA produces correct output dimensions" {
    const allocator = std.testing.allocator;
    // Create a 4x4 source image (64 bytes RGBA)
    var src: [4 * 4 * 4]u8 = undefined;
    for (&src) |*b| b.* = 128;

    const result = try downscaleRGBA(&src, 4, 4, 2, 2, allocator);
    defer allocator.free(result);
    try std.testing.expectEqual(@as(usize, 2 * 2 * 4), result.len);
}

test "downscaleRGBA identity case" {
    const allocator = std.testing.allocator;
    // 2x2 image with known pixel values
    const src = [_]u8{
        255, 0,   0,   255, // red
        0,   255, 0,   255, // green
        0,   0,   255, 255, // blue
        255, 255, 0,   255, // yellow
    };

    const result = try downscaleRGBA(&src, 2, 2, 2, 2, allocator);
    defer allocator.free(result);
    try std.testing.expectEqualSlices(u8, &src, result);
}

test "downscaleRGBA uniform color preserved" {
    const allocator = std.testing.allocator;
    // 4x4 uniform red image
    var src: [4 * 4 * 4]u8 = undefined;
    var i: usize = 0;
    while (i < src.len) : (i += 4) {
        src[i] = 200;
        src[i + 1] = 100;
        src[i + 2] = 50;
        src[i + 3] = 255;
    }

    const result = try downscaleRGBA(&src, 4, 4, 2, 2, allocator);
    defer allocator.free(result);

    // Every pixel in the output should be the same uniform color
    var j: usize = 0;
    while (j < result.len) : (j += 4) {
        try std.testing.expectEqual(@as(u8, 200), result[j]);
        try std.testing.expectEqual(@as(u8, 100), result[j + 1]);
        try std.testing.expectEqual(@as(u8, 50), result[j + 2]);
        try std.testing.expectEqual(@as(u8, 255), result[j + 3]);
    }
}

test "rgbaToBgra swaps channels correctly" {
    var data = [_]u8{ 10, 20, 30, 40, 50, 60, 70, 80 };
    rgbaToBgra(&data);
    try std.testing.expectEqualSlices(u8, &[_]u8{ 30, 20, 10, 40, 70, 60, 50, 80 }, &data);
}

test "rgbaToBgra round-trips" {
    const original = [_]u8{ 10, 20, 30, 40, 50, 60, 70, 80 };
    var data = original;
    rgbaToBgra(&data);
    rgbaToBgra(&data);
    try std.testing.expectEqualSlices(u8, &original, &data);
}

test "validateIconSource rejects non-square" {
    try std.testing.expectError(error.IconNotSquare, validateIconSource(512, 256));
}

test "validateIconSource rejects too small" {
    try std.testing.expectError(error.IconTooSmall, validateIconSource(8, 8));
}

test "validateIconSource accepts valid dimensions" {
    try validateIconSource(16, 16);
    try validateIconSource(512, 512);
    try validateIconSource(1024, 1024);
}
