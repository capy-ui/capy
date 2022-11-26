/// The values for this enum are chosen so that:
/// 1. value & 0xFF gives number of bits per channel
/// 2. value & 0xF00 gives number of channels
/// 3. value & 0xF000 gives a special variant number, 1 for Bgr, 2 for Float and 3 for special Rgb 565
/// Note that palette index formats have number of channels set to 0.
pub const PixelFormat = enum(u32) {
    invalid = 0,
    indexed1 = 1,
    indexed2 = 2,
    indexed4 = 4,
    indexed8 = 8,
    indexed16 = 16,
    grayscale1 = 0x101,
    grayscale2 = 0x102,
    grayscale4 = 0x104,
    grayscale8 = 0x108,
    grayscale16 = 0x110,
    grayscale8Alpha = 0x208,
    grayscale16Alpha = 0x210,
    rgb565 = 0x3305,
    rgb555 = 0x305,
    rgb24 = 0x308,
    rgba32 = 0x408,
    bgr24 = 0x1308,
    bgra32 = 0x1408,
    rgb48 = 0x310,
    rgba64 = 0x410,
    float32 = 0x2420,

    const Self = @This();

    pub fn isJustGrayscale(self: Self) bool {
        return @enumToInt(self) & 0xf00 == 0x100;
    }

    pub fn isIndex(self: Self) bool {
        return @enumToInt(self) <= @enumToInt(PixelFormat.indexed16);
    }

    pub fn isStandardRgb(self: Self) bool {
        return self == .rgb24 or self == .rgb48;
    }

    pub fn isRgba(self: Self) bool {
        return self == .rgba32 or self == .rgba64;
    }

    pub fn is16Bit(self: Self) bool {
        return @enumToInt(self) & 0xff == 0x10;
    }

    pub fn pixelStride(self: Self) u8 {
        // Using bit manipulations of values is not really faster than this switch
        return switch (self) {
            .invalid => 0,
            .indexed1, .indexed2, .indexed4, .indexed8, .grayscale1, .grayscale2, .grayscale4, .grayscale8 => 1,
            .indexed16, .grayscale16, .grayscale8Alpha, .rgb565, .rgb555 => 2,
            .rgb24, .bgr24 => 3,
            .grayscale16Alpha, .rgba32, .bgra32 => 4,
            .rgb48 => 6,
            .rgba64 => 8,
            .float32 => 16,
        };
    }

    pub fn bitsPerChannel(self: Self) u8 {
        return switch (self) {
            .invalid => 0,
            .rgb565 => unreachable, // TODO: what to do in that case?
            .indexed1, .grayscale1 => 1,
            .indexed2, .grayscale2 => 2,
            .indexed4, .grayscale4 => 4,
            .rgb555 => 5,
            .indexed8, .grayscale8, .grayscale8Alpha, .rgb24, .rgba32, .bgr24, .bgra32 => 8,
            .indexed16, .grayscale16, .grayscale16Alpha, .rgb48, .rgba64 => 16,
            .float32 => 32,
        };
    }

    pub fn channelCount(self: Self) u8 {
        return switch (self) {
            .invalid => 0,
            .grayscale8Alpha, .grayscale16Alpha => 2,
            .rgb565, .rgb555, .rgb24, .bgr24, .rgb48 => 3,
            .rgba32, .bgra32, .rgba64, .float32 => 4,
            else => 1,
        };
    }
};
