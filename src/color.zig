const std = @import("std");

pub const Colorspace = enum { RGB, RGBA };

/// 8-bit sRGB color with transparency as 32 bits ordered RGBA
pub const Color = packed struct {
    red: u8,
    green: u8,
    blue: u8,
    alpha: u8 = 255,

    // The CSS level 2 revision 1 colors
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

    pub fn fromString(string: []const u8) !Color {
        if (string.len != 7 and string.len != 9) {
            return error.InvalidLength;
        }
        if (string[0] != '#') {
            return error.NotSupported;
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

    pub fn comptimeFromString(comptime string: []const u8) Color {
        return comptime fromString(string) catch |err| @compileError(@errorName(err));
    }

    fn lerpByte(a: u8, b: u8, t: f64) u8 {
        return @floatToInt(u8, @intToFloat(f64, a) * (1 - t) + @intToFloat(f64, b) * t);
    }

    pub fn lerp(a: Color, b: Color, t: f64) Color {
        return Color{
            .red = lerpByte(a.red, b.red, t),
            .green = lerpByte(a.green, b.green, t),
            .blue = lerpByte(a.blue, b.blue, t),
            .alpha = lerpByte(a.alpha, b.alpha, t),
        };
    }

    pub fn toBytes(self: Color, dest: []u8) void {
        std.mem.bytesAsSlice(Color, dest).* = self;
    }
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

test "color linear interpolation" {
    const a = Color.comptimeFromString("#00ff8844");
    const b = Color.comptimeFromString("#88888888");
    try expectEqual(Color.lerp(a, b, 0.5), Color.lerp(b, a, 0.5));
    try expectEqual(Color.lerp(a, b, 0.75), Color.lerp(b, a, 0.25));
    try expectEqual(Color.lerp(a, b, 1.0), Color.lerp(b, a, 0.0));

    const result = Color.lerp(a, b, 0.5);
    try expectEqual(@as(u8, 0x44), result.red);
    try expectEqual(@as(u8, 0xc3), result.green);
    try expectEqual(@as(u8, 0x88), result.blue);
    try expectEqual(@as(u8, 0x66), result.alpha);
}
