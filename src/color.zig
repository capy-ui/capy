const std = @import("std");

pub const Colorspace = enum {
    RGB,
    RGBA
};

pub const Color = packed struct {
    red: u8,
    green: u8,
    blue: u8,
    alpha: u8 = 255,

    pub const black  = Color.comptimeFromString("#000000");
    pub const red    = Color.comptimeFromString("#ff0000");
    pub const green  = Color.comptimeFromString("#00ff00");
    pub const blue   = Color.comptimeFromString("#0000ff");
    pub const yellow = Color.comptimeFromString("#ffff00");
    pub const white  = Color.comptimeFromString("#ffffff");

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
        return Color { .red = r, .green = g, .blue = b, .alpha = a };
    }

    pub fn comptimeFromString(comptime string: []const u8) Color {
        return comptime fromString(string) catch |err| @compileError(@errorName(err));
    }

    pub fn toBytes(self: Color, dest: []u8) void {
        std.mem.bytesAsSlice(Color, dest).* = self;
    }
};
