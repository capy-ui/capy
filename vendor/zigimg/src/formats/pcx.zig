// Adapted from https://github.com/MasterQ32/zig-gamedev-lib/blob/master/src/pcx.zig
// with permission from Felix Queißner
const Allocator = std.mem.Allocator;
const FormatInterface = @import("../format_interface.zig").FormatInterface;
const PixelFormat = @import("../pixel_format.zig").PixelFormat;
const color = @import("../color.zig");
const ImageError = Image.Error;
const ImageReadError = Image.ReadError;
const ImageWriteError = Image.WriteError;
const Image = @import("../Image.zig");
const std = @import("std");
const utils = @import("../utils.zig");

pub const PCXHeader = extern struct {
    id: u8 = 0x0A,
    version: u8,
    compression: u8,
    bpp: u8,
    xmin: u16 align(1),
    ymin: u16 align(1),
    xmax: u16 align(1),
    ymax: u16 align(1),
    horizontal_dpi: u16 align(1),
    vertical_dpi: u16 align(1),
    builtin_palette: [48]u8,
    _reserved0: u8 = 0,
    planes: u8,
    stride: u16 align(1),
    palette_information: u16 align(1),
    screen_width: u16 align(1),
    screen_height: u16 align(1),

    // HACK: For some reason, padding as field does not report 128 bytes for the header.
    var padding: [54]u8 = undefined;

    comptime {
        std.debug.assert(@sizeOf(@This()) == 74);
    }
};

const RLEDecoder = struct {
    const Run = struct {
        value: u8,
        remaining: usize,
    };

    reader: Image.Stream.Reader,
    current_run: ?Run,

    fn init(reader: Image.Stream.Reader) RLEDecoder {
        return RLEDecoder{
            .reader = reader,
            .current_run = null,
        };
    }

    fn readByte(self: *RLEDecoder) ImageReadError!u8 {
        if (self.current_run) |*run| {
            var result = run.value;
            run.remaining -= 1;
            if (run.remaining == 0) {
                self.current_run = null;
            }
            return result;
        } else {
            while (true) {
                var byte = try self.reader.readByte();
                if (byte == 0xC0) // skip over "zero length runs"
                    continue;
                if ((byte & 0xC0) == 0xC0) {
                    const len = byte & 0x3F;
                    std.debug.assert(len > 0);
                    const result = try self.reader.readByte();
                    if (len > 1) {
                        // we only need to store a run in the decoder if it is longer than 1
                        self.current_run = .{
                            .value = result,
                            .remaining = len - 1,
                        };
                    }
                    return result;
                } else {
                    return byte;
                }
            }
        }
    }

    fn finish(decoder: RLEDecoder) ImageReadError!void {
        if (decoder.current_run != null) {
            return ImageReadError.InvalidData;
        }
    }
};

pub const PCX = struct {
    header: PCXHeader = undefined,
    width: usize = 0,
    height: usize = 0,

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
        return Image.Format.pcx;
    }

    pub fn formatDetect(stream: *Image.Stream) ImageReadError!bool {
        var magic_number_bufffer: [2]u8 = undefined;
        _ = try stream.read(magic_number_bufffer[0..]);

        if (magic_number_bufffer[0] != 0x0A) {
            return false;
        }

        if (magic_number_bufffer[1] > 0x05) {
            return false;
        }

        return true;
    }

    pub fn readImage(allocator: Allocator, stream: *Image.Stream) ImageReadError!Image {
        var result = Image.init(allocator);
        errdefer result.deinit();
        var pcx = PCX{};

        const pixels = try pcx.read(allocator, stream);

        result.width = pcx.width;
        result.height = pcx.height;
        result.pixels = pixels;

        return result;
    }

    pub fn writeImage(allocator: Allocator, write_stream: *Image.Stream, image: Image, encoder_options: Image.EncoderOptions) ImageWriteError!void {
        _ = allocator;
        _ = write_stream;
        _ = image;
        _ = encoder_options;
    }

    pub fn pixelFormat(self: Self) ImageReadError!PixelFormat {
        if (self.header.planes == 1) {
            switch (self.header.bpp) {
                1 => return PixelFormat.indexed1,
                4 => return PixelFormat.indexed4,
                8 => return PixelFormat.indexed8,
                else => return ImageError.Unsupported,
            }
        } else if (self.header.planes == 3) {
            switch (self.header.bpp) {
                8 => return PixelFormat.rgb24,
                else => return ImageError.Unsupported,
            }
        } else {
            return ImageError.Unsupported;
        }
    }

    pub fn read(self: *Self, allocator: Allocator, stream: *Image.Stream) ImageReadError!color.PixelStorage {
        const reader = stream.reader();
        self.header = try utils.readStructLittle(reader, PCXHeader);
        _ = try stream.read(PCXHeader.padding[0..]);

        if (self.header.id != 0x0A) {
            return ImageReadError.InvalidData;
        }

        if (self.header.version > 0x05) {
            return ImageReadError.InvalidData;
        }

        if (self.header.planes > 3) {
            return ImageError.Unsupported;
        }

        const pixel_format = try self.pixelFormat();

        self.width = @as(usize, self.header.xmax - self.header.xmin + 1);
        self.height = @as(usize, self.header.ymax - self.header.ymin + 1);

        const has_dummy_byte = (@bitCast(i16, self.header.stride) - @bitCast(isize, self.width)) == 1;
        const actual_width = if (has_dummy_byte) self.width + 1 else self.width;

        var pixels = try color.PixelStorage.init(allocator, pixel_format, self.width * self.height);
        errdefer pixels.deinit(allocator);

        var decoder = RLEDecoder.init(reader);

        const scanline_length = (self.header.stride * self.header.planes);

        var y: usize = 0;
        while (y < self.height) : (y += 1) {
            var offset: usize = 0;
            var x: usize = 0;

            const y_stride = y * self.width;

            // read all pixels from the current row
            while (offset < scanline_length and x < self.width) : (offset += 1) {
                const byte = try decoder.readByte();
                switch (pixels) {
                    .indexed1 => |storage| {
                        var i: usize = 0;
                        while (i < 8) : (i += 1) {
                            if (x < self.width) {
                                storage.indices[y_stride + x] = @intCast(u1, (byte >> (7 - @intCast(u3, i))) & 0x01);
                                x += 1;
                            }
                        }
                    },
                    .indexed4 => |storage| {
                        storage.indices[y_stride + x] = @truncate(u4, byte >> 4);
                        x += 1;
                        if (x < self.width) {
                            storage.indices[y_stride + x] = @truncate(u4, byte);
                            x += 1;
                        }
                    },
                    .indexed8 => |storage| {
                        storage.indices[y_stride + x] = byte;
                        x += 1;
                    },
                    .rgb24 => |storage| {
                        if (has_dummy_byte and byte == 0x00) {
                            continue;
                        }
                        const pixel_x = offset % (actual_width);
                        const current_color = offset / (actual_width);
                        switch (current_color) {
                            0 => {
                                storage[y_stride + pixel_x].r = byte;
                            },
                            1 => {
                                storage[y_stride + pixel_x].g = byte;
                            },
                            2 => {
                                storage[y_stride + pixel_x].b = byte;
                            },
                            else => {},
                        }

                        if (pixel_x > 0 and (pixel_x % self.header.planes) == 0) {
                            x += 1;
                        }
                    },
                    else => return ImageError.Unsupported,
                }
            }

            // discard the rest of the bytes in the current row
            while (offset < self.header.stride) : (offset += 1) {
                _ = try decoder.readByte();
            }
        }

        try decoder.finish();

        if (pixel_format == .indexed1 or pixel_format == .indexed4 or pixel_format == .indexed8) {
            var pal = switch (pixels) {
                .indexed1 => |*storage| storage.palette[0..],
                .indexed4 => |*storage| storage.palette[0..],
                .indexed8 => |*storage| storage.palette[0..],
                else => undefined,
            };

            var i: usize = 0;
            while (i < std.math.min(pal.len, self.header.builtin_palette.len / 3)) : (i += 1) {
                pal[i].r = self.header.builtin_palette[3 * i + 0];
                pal[i].g = self.header.builtin_palette[3 * i + 1];
                pal[i].b = self.header.builtin_palette[3 * i + 2];
                pal[i].a = 1.0;
            }

            if (pixels == .indexed8) {
                const end_pos = try stream.getEndPos();
                try stream.seekTo(end_pos - 769);

                if ((try reader.readByte()) != 0x0C)
                    return ImageReadError.InvalidData;

                for (pal) |*c| {
                    c.r = try reader.readByte();
                    c.g = try reader.readByte();
                    c.b = try reader.readByte();
                    c.a = 1.0;
                }
            }
        }

        return pixels;
    }
};
