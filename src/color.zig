const std = @import("std");

pub const Colorspace = enum { RGB, RGBA };

/// 8-bit sRGB color with transparency as 32 bits ordered RGBA
pub const Color = packed struct {
    red: u8,
    green: u8,
    blue: u8,
    alpha: u8 = 255,

    pub const black = Color.comptimeFromString("#000000");
    pub const red = Color.comptimeFromString("#ff0000");
    pub const green = Color.comptimeFromString("#00ff00");
    pub const blue = Color.comptimeFromString("#0000ff");
    pub const yellow = Color.comptimeFromString("#ffff00");
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
