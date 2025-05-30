const std = @import("std");

pub const Colorspace = enum {
    RGB,
    RGBA,
    pub fn byteCount(self: Colorspace) u8 {
        return switch (self) {
            .RGB => 3,
            .RGBA => 4,
        };
    }
};

/// 8-bit sRGB color with transparency as 32 bits ordered RGBA
pub const Color = packed struct {
    // Due to packed struct ordering, fields are ordered from the least significant bit to the
    // most significant, which means that this struct represented as an hex number is 0xRRGGBBAA
    // (matching the fromString methods)
    alpha: u8 = 255,
    blue: u8,
    green: u8,
    red: u8,

    pub fn fromString(string: []const u8) !Color {
        if (string[0] != '#') {
            return error.NotSupported;
        }
        if (string.len != 7 and string.len != 9) {
            return error.InvalidLength;
        }

        const r = try std.fmt.parseInt(u8, string[1..3], 16);
        const g = try std.fmt.parseInt(u8, string[3..5], 16);
        const b = try std.fmt.parseInt(u8, string[5..7], 16);
        var a: u8 = 255;
        if (string.len == 9) {
            a = try std.fmt.parseInt(u8, string[7..9], 16);
        }
        return Color{ .red = r, .green = g, .blue = b, .alpha = a };
    }

    /// Creates a color during compile-time (meaning there's no parsing during runtime)
    /// This means that if the color is wrong, a compile error will be thrown.
    pub fn comptimeFromString(comptime string: []const u8) Color {
        return comptime fromString(string) catch
            @compileError("'" ++ string ++ "' is not a valid color");
    }

    pub fn fromARGB(alpha_value: u8, red_value: u8, green_value: u8, blue_value: u8) Color {
        return Color{ .red = red_value, .green = green_value, .blue = blue_value, .alpha = alpha_value };
    }

    pub fn fromRGB(red_value: u8, green_value: u8, blue_value: u8) Color {
        return fromARGB(255, red_value, green_value, blue_value);
    }

    fn lerpByte(a: u8, b: u8, t: f64) u8 {
        return @as(u8, @intFromFloat(@as(f64, @floatFromInt(a)) * (1 - t) + @as(f64, @floatFromInt(b)) * t));
    }

    pub fn toLinear(component: u8) u8 {
        var float = @as(f32, @floatFromInt(component));
        float = std.math.pow(f32, float / 255, 1.0 / 2.2) * 255;
        return @as(u8, @intFromFloat(float));
    }

    pub fn toSRGB(component: u8) u8 {
        var float = @as(f32, @floatFromInt(component));
        float = std.math.pow(f32, float / 255, 2.2) * 255;
        return @as(u8, @intFromFloat(float));
    }

    // TODO: interpolate between colors in linear RGB space
    pub fn lerp(a: Color, b: Color, t: f64) Color {
        return Color{
            .red = toSRGB(lerpByte(toLinear(a.red), toLinear(b.red), t)),
            .green = toSRGB(lerpByte(toLinear(a.green), toLinear(b.green), t)),
            .blue = toSRGB(lerpByte(toLinear(a.blue), toLinear(b.blue), t)),
            .alpha = lerpByte(a.alpha, b.alpha, t),
        };
    }

    pub fn srgbLerp(a: Color, b: Color, t: f64) Color {
        return Color{
            .red = lerpByte(a.red, b.red, t),
            .green = lerpByte(a.green, b.green, t),
            .blue = lerpByte(a.blue, b.blue, t),
            .alpha = lerpByte(a.alpha, b.alpha, t),
        };
    }

    pub fn toBytes(self: Color, dest: []u8) void {
        std.mem.bytesAsSlice(Color, dest)[0] = self;
    }
};

/// Standard color values. Those are the same as the CSS level 2 revision 1 colors.
pub const Colors = struct {
    // CSS level 2 revision 1 colors
    pub const maroon = Color.comptimeFromString("#800000");
    pub const red = Color.comptimeFromString("#ff0000");
    pub const orange = Color.comptimeFromString("#ffa500");
    pub const yellow = Color.comptimeFromString("#ffff00");
    pub const lime = Color.comptimeFromString("#00ff00");
    pub const green = Color.comptimeFromString("#008000");
    pub const olive = Color.comptimeFromString("#808000");
    pub const aqua = Color.comptimeFromString("#00ffff");
    pub const teal = Color.comptimeFromString("#008080");
    pub const blue = Color.comptimeFromString("#0000ff");
    pub const navy = Color.comptimeFromString("#000080");
    pub const fuchsia = Color.comptimeFromString("#ff00ff");
    pub const purple = Color.comptimeFromString("#800080");

    pub const black = Color.comptimeFromString("#000000");
    pub const gray = Color.comptimeFromString("#808080");
    pub const silver = Color.comptimeFromString("#c0c0c0");
    pub const white = Color.comptimeFromString("#ffffff");

    pub const transparent = Color.comptimeFromString("#00000000");
};

const expectEqual = std.testing.expectEqual;

test "color parse" {
    const color = try Color.fromString("#2d4a3b");
    try expectEqual(@as(u8, 0x2d), color.red);
    try expectEqual(@as(u8, 0x4a), color.green);
    try expectEqual(@as(u8, 0x3b), color.blue);
    try expectEqual(@as(u8, 0xff), color.alpha);

    const color2 = try Color.fromString("#a13d4c89");
    try expectEqual(@as(u8, 0xa1), color2.red);
    try expectEqual(@as(u8, 0x3d), color2.green);
    try expectEqual(@as(u8, 0x4c), color2.blue);
    try expectEqual(@as(u8, 0x89), color2.alpha);
}

test "comptime color parse" {
    const color = Color.comptimeFromString("#3b2d4a");
    try expectEqual(@as(u8, 0x3b), color.red);
    try expectEqual(@as(u8, 0x2d), color.green);
    try expectEqual(@as(u8, 0x4a), color.blue);
    try expectEqual(@as(u8, 0xff), color.alpha);

    const color2 = Color.comptimeFromString("#98a3cdef");
    try expectEqual(@as(u8, 0x98), color2.red);
    try expectEqual(@as(u8, 0xa3), color2.green);
    try expectEqual(@as(u8, 0xcd), color2.blue);
    try expectEqual(@as(u8, 0xef), color2.alpha);
}

test "color sRGB linear interpolation" {
    const a = Color.comptimeFromString("#00ff8844");
    const b = Color.comptimeFromString("#88888888");
    try expectEqual(Color.srgbLerp(a, b, 0.5), Color.srgbLerp(b, a, 0.5));
    try expectEqual(Color.srgbLerp(a, b, 0.75), Color.srgbLerp(b, a, 0.25));
    try expectEqual(Color.srgbLerp(a, b, 1.0), Color.srgbLerp(b, a, 0.0));

    const result = Color.srgbLerp(a, b, 0.5);
    try expectEqual(@as(u8, 0x44), result.red);
    try expectEqual(@as(u8, 0xc3), result.green);
    try expectEqual(@as(u8, 0x88), result.blue);
    try expectEqual(@as(u8, 0x66), result.alpha);
}

test "erroneous colors" {
    try std.testing.expectError(error.InvalidLength, Color.fromString("#00ff8"));
    try std.testing.expectError(error.InvalidLength, Color.fromString("#000"));
    try std.testing.expectError(error.InvalidLength, Color.fromString("#00ff88aaa"));
    try std.testing.expectError(error.NotSupported, Color.fromString("hello"));
}
