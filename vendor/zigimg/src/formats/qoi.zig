// Adapted from https://github.com/MasterQ32/zig-qoi
// with permission from Felix Queißner
const Allocator = std.mem.Allocator;
const FormatInterface = @import("../format_interface.zig").FormatInterface;
const PixelFormat = @import("../pixel_format.zig").PixelFormat;
const color = @import("../color.zig");
const ImageError = Image.Error;
const ImageReadError = Image.ReadError;
const ImageWriteError = Image.WriteError;
const fs = std.fs;
const Image = @import("../Image.zig");
const io = std.io;
const mem = std.mem;
const path = std.fs.path;
const std = @import("std");
const utils = @import("../utils.zig");

pub const QoiColor = extern struct {
    r: u8 align(1),
    g: u8 align(1),
    b: u8 align(1),
    a: u8 align(1) = 0xFF,

    fn hash(c: QoiColor) u6 {
        return @truncate(u6, c.r *% 3 +% c.g *% 5 +% c.b *% 7 +% c.a *% 11);
    }

    pub fn eql(a: QoiColor, b: QoiColor) bool {
        return std.meta.eql(a, b);
    }

    pub fn toRgb24(self: QoiColor) color.Rgb24 {
        return color.Rgb24{
            .r = self.r,
            .g = self.g,
            .b = self.b,
        };
    }

    pub fn toRgba32(self: QoiColor) color.Rgba32 {
        return color.Rgba32{
            .r = self.r,
            .g = self.g,
            .b = self.b,
            .a = self.a,
        };
    }

    pub fn from(pixel: anytype) QoiColor {
        if (@TypeOf(pixel) == color.Rgb24) {
            return QoiColor{
                .r = pixel.r,
                .g = pixel.g,
                .b = pixel.b,
            };
        } else if (@TypeOf(pixel) == color.Rgba32) {
            return QoiColor{
                .r = pixel.r,
                .g = pixel.g,
                .b = pixel.b,
                .a = pixel.a,
            };
        } else {
            unreachable;
        }
    }
};

pub const Colorspace = enum(u8) {
    /// sRGB color, linear alpha
    srgb = 0,

    /// Every channel is linear
    linear = 1,
};

pub const Format = enum(u8) {
    rgb = 3,
    rgba = 4,
};

pub const Header = extern struct {
    const size = 14;
    const correct_magic = [4]u8{ 'q', 'o', 'i', 'f' };

    width: u32 align(1),
    height: u32 align(1),
    format: Format align(1),
    colorspace: Colorspace align(1),

    fn encode(header: Header) [size]u8 {
        var result: [size]u8 = undefined;
        std.mem.copy(u8, result[0..4], &correct_magic);
        std.mem.writeIntBig(u32, result[4..8], header.width);
        std.mem.writeIntBig(u32, result[8..12], header.height);
        result[12] = @enumToInt(header.format);
        result[13] = @enumToInt(header.colorspace);
        return result;
    }

    comptime {
        std.debug.assert((@sizeOf(Header) + Header.correct_magic.len) == Header.size);
    }
};

pub const QOI = struct {
    header: Header = undefined,

    pub const EncoderOptions = struct {
        colorspace: Colorspace = .srgb,
    };

    const Self = @This();

    pub fn formatInterface() FormatInterface {
        return FormatInterface{
            .format = format,
            .formatDetect = formatDetect,
            .readImage = readImage,
            .writeImage = writeImage,
        };
    }

    pub fn format() Image.Format {
        return Image.Format.qoi;
    }

    pub fn formatDetect(stream: *Image.Stream) ImageReadError!bool {
        var magic_buffer: [std.mem.len(Header.correct_magic)]u8 = undefined;

        _ = try stream.read(magic_buffer[0..]);

        return std.mem.eql(u8, magic_buffer[0..], Header.correct_magic[0..]);
    }

    pub fn readImage(allocator: Allocator, stream: *Image.Stream) ImageReadError!Image {
        var result = Image.init(allocator);
        errdefer result.deinit();
        var qoi = Self{};

        const pixels = try qoi.read(allocator, stream);

        result.width = qoi.width();
        result.height = qoi.height();
        result.pixels = pixels;

        return result;
    }

    pub fn writeImage(allocator: Allocator, write_stream: *Image.Stream, image: Image, encoder_options: Image.EncoderOptions) ImageWriteError!void {
        _ = allocator;

        var qoi = Self{};
        qoi.header.width = @truncate(u32, image.width);
        qoi.header.height = @truncate(u32, image.height);
        qoi.header.format = switch (image.pixels) {
            .rgb24 => Format.rgb,
            .rgba32 => Format.rgba,
            else => return ImageError.Unsupported,
        };
        switch (encoder_options) {
            .qoi => |qoi_encode_options| {
                qoi.header.colorspace = qoi_encode_options.colorspace;
            },
            else => {
                qoi.header.colorspace = .srgb;
            },
        }

        try qoi.write(write_stream, image.pixels);
    }

    pub fn width(self: Self) usize {
        return self.header.width;
    }

    pub fn height(self: Self) usize {
        return self.header.height;
    }

    pub fn pixelFormat(self: Self) !PixelFormat {
        return switch (self.header.format) {
            .rgb => PixelFormat.rgb24,
            .rgba => PixelFormat.rgba32,
        };
    }

    pub fn read(self: *Self, allocator: Allocator, stream: *Image.Stream) ImageReadError!color.PixelStorage {
        var magic_buffer: [std.mem.len(Header.correct_magic)]u8 = undefined;

        const reader = stream.reader();

        _ = try stream.read(magic_buffer[0..]);

        if (!std.mem.eql(u8, magic_buffer[0..], Header.correct_magic[0..])) {
            return ImageReadError.InvalidData;
        }

        self.header = utils.readStructBig(reader, Header) catch return ImageReadError.InvalidData;

        const pixel_format = try self.pixelFormat();

        var pixels = try color.PixelStorage.init(allocator, pixel_format, self.width() * self.height());
        errdefer pixels.deinit(allocator);

        var current_color = QoiColor{ .r = 0, .g = 0, .b = 0, .a = 0xFF };
        var color_lut = std.mem.zeroes([64]QoiColor);

        var index: usize = 0;
        const pixels_size: usize = @as(usize, self.header.width) * @as(usize, self.header.height);

        while (index < pixels_size) {
            var byte = try reader.readByte();

            var new_color = current_color;
            var count: usize = 1;

            if (byte == 0b11111110) { // QOI_OP_RGB
                new_color.r = try reader.readByte();
                new_color.g = try reader.readByte();
                new_color.b = try reader.readByte();
            } else if (byte == 0b11111111) { // QOI_OP_RGBA
                new_color.r = try reader.readByte();
                new_color.g = try reader.readByte();
                new_color.b = try reader.readByte();
                new_color.a = try reader.readByte();
            } else if (hasPrefix(byte, u2, 0b00)) { // QOI_OP_INDEX
                const color_index = @truncate(u6, byte);
                new_color = color_lut[color_index];
            } else if (hasPrefix(byte, u2, 0b01)) { // QOI_OP_DIFF
                const diff_r = unmapRange2(byte >> 4);
                const diff_g = unmapRange2(byte >> 2);
                const diff_b = unmapRange2(byte >> 0);

                add8(&new_color.r, diff_r);
                add8(&new_color.g, diff_g);
                add8(&new_color.b, diff_b);
            } else if (hasPrefix(byte, u2, 0b10)) { // QOI_OP_LUMA
                const diff_g = unmapRange6(byte);

                const diff_rg_rb = try reader.readByte();

                const diff_rg = unmapRange4(diff_rg_rb >> 4);
                const diff_rb = unmapRange4(diff_rg_rb >> 0);

                const diff_r = @as(i8, diff_g) + diff_rg;
                const diff_b = @as(i8, diff_g) + diff_rb;

                add8(&new_color.r, diff_r);
                add8(&new_color.g, diff_g);
                add8(&new_color.b, diff_b);
            } else if (hasPrefix(byte, u2, 0b11)) { // QOI_OP_RUN
                count = @as(usize, @truncate(u6, byte)) + 1;
                std.debug.assert(count >= 1 and count <= 62);
            } else {
                // we have covered all possibilities.
                unreachable;
            }

            // this will happen when a file has an invalid run length
            // and we would decode more pixels than there are in the image.
            if (index + count > pixels_size) {
                return ImageReadError.InvalidData;
            }

            while (count > 0) {
                count -= 1;
                switch (pixels) {
                    .rgb24 => |data| {
                        data[index] = new_color.toRgb24();
                    },
                    .rgba32 => |data| {
                        data[index] = new_color.toRgba32();
                    },
                    else => {},
                }
                index += 1;
            }

            color_lut[new_color.hash()] = new_color;
            current_color = new_color;
        }

        return pixels;
    }

    pub fn write(self: Self, write_stream: *Image.Stream, pixels: color.PixelStorage) ImageWriteError!void {
        const writer = write_stream.writer();
        try writer.writeAll(&self.header.encode());

        switch (pixels) {
            .rgb24 => |data| {
                try writeData(writer, data);
            },
            .rgba32 => |data| {
                try writeData(writer, data);
            },
            else => {
                return ImageError.Unsupported;
            },
        }

        try writer.writeAll(&[8]u8{
            0x00,
            0x00,
            0x00,
            0x00,
            0x00,
            0x00,
            0x00,
            0x01,
        });
    }

    fn writeData(write_stream: Image.Stream.Writer, pixels_data: anytype) ImageWriteError!void {
        var color_lut = std.mem.zeroes([64]QoiColor);

        var previous_pixel = QoiColor{ .r = 0, .g = 0, .b = 0, .a = 0xFF };
        var run_length: usize = 0;

        for (pixels_data) |current_color, i| {
            const pixel = QoiColor.from(current_color);

            defer previous_pixel = pixel;

            const same_pixel = pixel.eql(previous_pixel);

            if (same_pixel) {
                run_length += 1;
            }

            if (run_length > 0 and (run_length == 62 or !same_pixel or (i == (pixels_data.len - 1)))) {
                // QOI_OP_RUN
                std.debug.assert(run_length >= 1 and run_length <= 62);
                try write_stream.writeByte(0b1100_0000 | @truncate(u8, run_length - 1));
                run_length = 0;
            }

            if (!same_pixel) {
                const hash = pixel.hash();
                if (color_lut[hash].eql(pixel)) {
                    // QOI_OP_INDEX
                    try write_stream.writeByte(0b0000_0000 | hash);
                } else {
                    color_lut[hash] = pixel;

                    const diff_r = @as(i16, pixel.r) - @as(i16, previous_pixel.r);
                    const diff_g = @as(i16, pixel.g) - @as(i16, previous_pixel.g);
                    const diff_b = @as(i16, pixel.b) - @as(i16, previous_pixel.b);
                    const diff_a = @as(i16, pixel.a) - @as(i16, previous_pixel.a);

                    const diff_rg = diff_r - diff_g;
                    const diff_rb = diff_b - diff_g;

                    if (diff_a == 0 and inRange2(diff_r) and inRange2(diff_g) and inRange2(diff_b)) {
                        // QOI_OP_DIFF
                        const byte = 0b0100_0000 |
                            (mapRange2(diff_r) << 4) |
                            (mapRange2(diff_g) << 2) |
                            (mapRange2(diff_b) << 0);
                        try write_stream.writeByte(byte);
                    } else if (diff_a == 0 and inRange6(diff_g) and inRange4(diff_rg) and inRange4(diff_rb)) {
                        // QOI_OP_LUMA
                        try write_stream.writeAll(&[2]u8{
                            0b1000_0000 | mapRange6(diff_g),
                            (mapRange4(diff_rg) << 4) | (mapRange4(diff_rb) << 0),
                        });
                    } else if (diff_a == 0) {
                        // QOI_OP_RGB
                        try write_stream.writeAll(&[4]u8{
                            0b1111_1110,
                            pixel.r,
                            pixel.g,
                            pixel.b,
                        });
                    } else {
                        // QOI_OP_RGBA
                        try write_stream.writeAll(&[5]u8{
                            0b1111_1111,
                            pixel.r,
                            pixel.g,
                            pixel.b,
                            pixel.a,
                        });
                    }
                }
            }
        }
    }

    fn mapRange2(val: i16) u8 {
        return @intCast(u2, val + 2);
    }
    fn mapRange4(val: i16) u8 {
        return @intCast(u4, val + 8);
    }
    fn mapRange6(val: i16) u8 {
        return @intCast(u6, val + 32);
    }

    fn unmapRange2(val: u32) i2 {
        return @intCast(i2, @as(i8, @truncate(u2, val)) - 2);
    }
    fn unmapRange4(val: u32) i4 {
        return @intCast(i4, @as(i8, @truncate(u4, val)) - 8);
    }
    fn unmapRange6(val: u32) i6 {
        return @intCast(i6, @as(i8, @truncate(u6, val)) - 32);
    }

    fn inRange2(val: i16) bool {
        return (val >= -2) and (val <= 1);
    }
    fn inRange4(val: i16) bool {
        return (val >= -8) and (val <= 7);
    }
    fn inRange6(val: i16) bool {
        return (val >= -32) and (val <= 31);
    }

    fn add8(dst: *u8, diff: i8) void {
        dst.* +%= @bitCast(u8, diff);
    }

    fn hasPrefix(value: u8, comptime T: type, prefix: T) bool {
        return (@truncate(T, value >> (8 - @bitSizeOf(T))) == prefix);
    }
};
