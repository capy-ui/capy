const std = @import("std");
const testing = std.testing;
const PixelFormat = @import("../src/pixel_format.zig").PixelFormat;
const helpers = @import("helpers.zig");

test "PixelFormat should return the correct pixel stride" {
    try helpers.expectEq(PixelFormat.indexed1.pixelStride(), 1);
    try helpers.expectEq(PixelFormat.indexed2.pixelStride(), 1);
    try helpers.expectEq(PixelFormat.indexed4.pixelStride(), 1);
    try helpers.expectEq(PixelFormat.indexed8.pixelStride(), 1);
    try helpers.expectEq(PixelFormat.indexed16.pixelStride(), 2);
    try helpers.expectEq(PixelFormat.grayscale1.pixelStride(), 1);
    try helpers.expectEq(PixelFormat.grayscale2.pixelStride(), 1);
    try helpers.expectEq(PixelFormat.grayscale4.pixelStride(), 1);
    try helpers.expectEq(PixelFormat.grayscale8.pixelStride(), 1);
    try helpers.expectEq(PixelFormat.grayscale16.pixelStride(), 2);
    try helpers.expectEq(PixelFormat.grayscale8Alpha.pixelStride(), 2);
    try helpers.expectEq(PixelFormat.grayscale16Alpha.pixelStride(), 4);
    try helpers.expectEq(PixelFormat.rgb555.pixelStride(), 2);
    try helpers.expectEq(PixelFormat.rgb565.pixelStride(), 2);
    try helpers.expectEq(PixelFormat.rgb24.pixelStride(), 3);
    try helpers.expectEq(PixelFormat.rgba32.pixelStride(), 4);
    try helpers.expectEq(PixelFormat.bgr555.pixelStride(), 2);
    try helpers.expectEq(PixelFormat.bgr24.pixelStride(), 3);
    try helpers.expectEq(PixelFormat.bgra32.pixelStride(), 4);
    try helpers.expectEq(PixelFormat.rgb48.pixelStride(), 6);
    try helpers.expectEq(PixelFormat.rgba64.pixelStride(), 8);
    try helpers.expectEq(PixelFormat.float32.pixelStride(), 16);
}
