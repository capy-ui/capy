pub const PixelFormatVariant = enum(u4) {
    none = 0,
    bgr = 1,
    float = 2,
    rgb565 = 3,
    _,
};

/// The values for this enum are chosen so that:
/// 1. value & 0xFF gives number of bits per channel
/// 2. value & 0xF00 gives number of channels
/// 3. value & 0xF000 gives a special variant number, 1 for Bgr, 2 for Float and 3 for special Rgb 565
/// Note that palette index formats have number of channels set to 0.
pub const PixelFormatInfo = packed struct {
    bits_per_channel: u8 = 0,
    channel_count: u4 = 0,
    variant: PixelFormatVariant = .none,
    padding: u16 = 0,
};

pub inline fn toPixelFormatValue(comptime pixel_format: PixelFormatInfo) u32 {
    return @bitCast(pixel_format);
}

pub const PixelFormat = enum(u32) {
    invalid = 0,
    indexed1 = toPixelFormatValue(.{ .bits_per_channel = 1 }),
    indexed2 = toPixelFormatValue(.{ .bits_per_channel = 2 }),
    indexed4 = toPixelFormatValue(.{ .bits_per_channel = 4 }),
    indexed8 = toPixelFormatValue(.{ .bits_per_channel = 8 }),
    indexed16 = toPixelFormatValue(.{ .bits_per_channel = 16 }),
    grayscale1 = toPixelFormatValue(.{ .channel_count = 1, .bits_per_channel = 1 }),
    grayscale2 = toPixelFormatValue(.{ .channel_count = 1, .bits_per_channel = 2 }),
    grayscale4 = toPixelFormatValue(.{ .channel_count = 1, .bits_per_channel = 4 }),
    grayscale8 = toPixelFormatValue(.{ .channel_count = 1, .bits_per_channel = 8 }),
    grayscale16 = toPixelFormatValue(.{ .channel_count = 1, .bits_per_channel = 16 }),
    grayscale8Alpha = toPixelFormatValue(.{ .channel_count = 2, .bits_per_channel = 8 }),
    grayscale16Alpha = toPixelFormatValue(.{ .channel_count = 2, .bits_per_channel = 16 }),
    rgb555 = toPixelFormatValue(.{ .channel_count = 3, .bits_per_channel = 5 }),
    rgb565 = toPixelFormatValue(.{ .variant = .rgb565, .channel_count = 3, .bits_per_channel = 5 }),
    rgb24 = toPixelFormatValue(.{ .channel_count = 3, .bits_per_channel = 8 }),
    rgba32 = toPixelFormatValue(.{ .channel_count = 4, .bits_per_channel = 8 }),
    bgr555 = toPixelFormatValue(.{ .variant = .bgr, .channel_count = 3, .bits_per_channel = 5 }),
    bgr24 = toPixelFormatValue(.{ .variant = .bgr, .channel_count = 3, .bits_per_channel = 8 }),
    bgra32 = toPixelFormatValue(.{ .variant = .bgr, .channel_count = 4, .bits_per_channel = 8 }),
    rgb48 = toPixelFormatValue(.{ .channel_count = 3, .bits_per_channel = 16 }),
    rgba64 = toPixelFormatValue(.{ .channel_count = 4, .bits_per_channel = 16 }),
    float32 = toPixelFormatValue(.{ .variant = .float, .channel_count = 4, .bits_per_channel = 32 }),

    pub inline fn info(self: PixelFormat) PixelFormatInfo {
        return @as(PixelFormatInfo, @bitCast(@intFromEnum(self)));
    }

    pub fn isGrayscale(self: PixelFormat) bool {
        return switch (self) {
            .grayscale1, .grayscale2, .grayscale4, .grayscale8, .grayscale16, .grayscale8Alpha, .grayscale16Alpha => true,
            else => false,
        };
    }

    pub fn isIndexed(self: PixelFormat) bool {
        return info(self).channel_count == 0;
    }

    pub fn isStandardRgb(self: PixelFormat) bool {
        return self == .rgb24 or self == .rgb48;
    }

    pub fn isRgba(self: PixelFormat) bool {
        return self == .rgba32 or self == .rgba64;
    }

    pub fn is16Bit(self: PixelFormat) bool {
        return info(self).bits_per_channel == 16;
    }

    pub fn pixelStride(self: PixelFormat) u8 {
        if (self.isIndexed()) {
            return (info(self).bits_per_channel + 7) / 8;
        }

        return switch (self) {
            inline else => |value| (info(value).channel_count * info(value).bits_per_channel + 7) / 8,
        };
    }

    pub fn bitsPerChannel(self: PixelFormat) u8 {
        return switch (self) {
            .rgb565 => unreachable, // TODO: what to do in that case?
            inline else => |value| info(value).bits_per_channel,
        };
    }

    pub fn channelCount(self: PixelFormat) u8 {
        if (self.isIndexed()) {
            return 1;
        }

        return switch (self) {
            inline else => |value| info(value).channel_count,
        };
    }
};

comptime {
    const std = @import("std");

    std.debug.assert(@intFromEnum(PixelFormat.grayscale1) == 0x101);
    std.debug.assert(@intFromEnum(PixelFormat.grayscale16) == 0x110);
    std.debug.assert(@intFromEnum(PixelFormat.grayscale8Alpha) == 0x208);
    std.debug.assert(@intFromEnum(PixelFormat.rgb555) == 0x305);
    std.debug.assert(@intFromEnum(PixelFormat.rgb565) == 0x3305);
    std.debug.assert(@intFromEnum(PixelFormat.rgba32) == 0x408);
    std.debug.assert(@intFromEnum(PixelFormat.bgr24) == 0x1308);
    std.debug.assert(@intFromEnum(PixelFormat.bgra32) == 0x1408);
    std.debug.assert(@intFromEnum(PixelFormat.float32) == 0x2420);
}
