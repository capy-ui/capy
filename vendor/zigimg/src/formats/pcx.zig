// Adapted from https://github.com/MasterQ32/zig-gamedev-lib/blob/master/src/pcx.zig
// with permission from Felix Queißner
const Allocator = std.mem.Allocator;
const buffered_stream_source = @import("../buffered_stream_source.zig");
const color = @import("../color.zig");
const FormatInterface = @import("../FormatInterface.zig");
const Image = @import("../Image.zig");
const ImageError = Image.Error;
const ImageReadError = Image.ReadError;
const ImageWriteError = Image.WriteError;
const PixelFormat = @import("../pixel_format.zig").PixelFormat;
const std = @import("std");
const utils = @import("../utils.zig");
const simd = @import("../simd.zig");

const MagicHeader: u8 = 0x0A;
const Version: u8 = 5;
const VGAPaletteIdentifier: u8 = 0x0C;

pub const Compression = enum(u8) {
    none,
    rle,
};

pub const PaletteInfo = enum(u16) {
    color = 1,
    grayscale = 2,
    _,
};

pub const PCXHeader = extern struct {
    id: u8 = MagicHeader,
    version: u8 = Version,
    compression: Compression = .rle,
    bpp: u8 = 0,
    xmin: u16 align(1) = 0,
    ymin: u16 align(1) = 0,
    xmax: u16 align(1) = 0,
    ymax: u16 align(1) = 0,
    horizontal_dpi: u16 align(1) = 320, // Default values found in the PCX image in the test suite
    vertical_dpi: u16 align(1) = 200, // Default values found in the PCX image in the test suite
    builtin_palette: [16]color.Rgb24 = [_]color.Rgb24{.{ .r = 0, .g = 0, .b = 0 }} ** 16,
    _reserved0: u8 = 0,
    planes: u8 = 0,
    stride: u16 align(1) = 0,
    palette_information: PaletteInfo align(1) = .color,
    screen_width: u16 align(1) = 0,
    screen_height: u16 align(1) = 0,
    padding: [54]u8 = [_]u8{0} ** 54,

    comptime {
        std.debug.assert(@sizeOf(PCXHeader) == 128);
    }
};

const RLEPairMask = 0xC0;
const RLELengthMask = 0xFF - RLEPairMask;

const RLEDecoder = struct {
    const Run = struct {
        value: u8,
        remaining: usize,
    };

    reader: buffered_stream_source.DefaultBufferedStreamSourceReader.Reader,
    current_run: ?Run,

    fn init(reader: buffered_stream_source.DefaultBufferedStreamSourceReader.Reader) RLEDecoder {
        return RLEDecoder{
            .reader = reader,
            .current_run = null,
        };
    }

    fn readByte(self: *RLEDecoder) ImageReadError!u8 {
        if (self.current_run) |*run| {
            const result = run.value;
            run.remaining -= 1;
            if (run.remaining == 0) {
                self.current_run = null;
            }
            return result;
        } else {
            while (true) {
                const byte = try self.reader.readByte();
                if (byte == RLEPairMask) // skip over "zero length runs"
                    continue;
                if ((byte & RLEPairMask) == RLEPairMask) {
                    const len = byte & RLELengthMask;
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

const RLEPair = packed struct(u8) {
    length: u6 = 0,
    identifier: u2 = (1 << 2) - 1,
};

const RLEMinLength = 2;
const RLEMaxLength = (1 << 6) - 1;

fn flushRLE(writer: anytype, value: u8, count: usize) !void {
    var current_count = count;
    while (current_count > 0) {
        const length_to_write = @min(current_count, RLEMaxLength);

        if (length_to_write >= RLEMinLength) {
            try flushRlePair(writer, value, length_to_write);
        } else {
            try flushRawBytes(writer, value, length_to_write);
        }

        current_count -= length_to_write;
    }
}

inline fn flushRlePair(writer: anytype, value: u8, count: usize) !void {
    const rle_pair = RLEPair{
        .length = @truncate(count),
    };
    try writer.writeByte(@bitCast(rle_pair));
    try writer.writeByte(value);
}

inline fn flushRawBytes(writer: anytype, value: u8, count: usize) !void {
    // Must flush byte greater than 192 (0xC0) as a RLE pair
    if ((value & RLEPairMask) == RLEPairMask) {
        for (0..count) |_| {
            try flushRlePair(writer, value, 1);
        }
    } else {
        for (0..count) |_| {
            try writer.writeByte(value);
        }
    }
}

const RLEFastEncoder = struct {
    const LengthToCheck = 16;
    const VectorType = @Vector(LengthToCheck, u8);

    pub fn encode(source_data: []const u8, writer: anytype) !void {
        if (source_data.len == 0) {
            return;
        }

        var index: usize = 0;

        var total_similar_count: usize = 0;

        var current_byte: u8 = 0;

        while (index < source_data.len and (index + LengthToCheck) <= source_data.len) {
            // Read current byte
            current_byte = source_data[index];

            const current_byte_splatted: VectorType = @splat(current_byte);
            const compare_chunk = simd.load(source_data[index..], VectorType, 0);

            const compare_mask = (current_byte_splatted == compare_chunk);
            const inverted_mask = ~@as(u16, @bitCast(compare_mask));
            const current_similar_count = @ctz(inverted_mask);

            if (current_similar_count == LengthToCheck) {
                total_similar_count += current_similar_count;
                index += current_similar_count;
            } else {
                total_similar_count += current_similar_count;

                try flushRLE(writer, current_byte, total_similar_count);

                total_similar_count = 0;

                index += current_similar_count;
            }
        }

        try flushRLE(writer, current_byte, total_similar_count);

        // Process the rest sequentially
        total_similar_count = 0;
        if (index < source_data.len) {
            current_byte = source_data[index];

            while (index < source_data.len) {
                const read_byte = source_data[index];
                if (read_byte == current_byte) {
                    total_similar_count += 1;
                } else {
                    try flushRLE(writer, current_byte, total_similar_count);

                    current_byte = read_byte;
                    total_similar_count = 1;
                }

                index += 1;
            }

            try flushRLE(writer, current_byte, total_similar_count);
        }
    }
};

test "PCX RLE Fast encoder" {
    const uncompressed_data = [_]u8{ 1, 1, 1, 1, 1, 1, 1, 1, 1, 64, 64, 2, 2, 2, 2, 2, 215, 215, 215, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 200, 200, 200, 200, 210, 210 };
    const compressed_data = [_]u8{ 0xC9, 0x01, 0xC2, 0x40, 0xC5, 0x02, 0xC3, 0xD7, 0xCA, 0x03, 0xC4, 0xC8, 0xC2, 0xD2 };

    var result_list = std.ArrayList(u8).init(std.testing.allocator);
    defer result_list.deinit();

    const writer = result_list.writer();

    try RLEFastEncoder.encode(uncompressed_data[0..], writer);

    try std.testing.expectEqualSlices(u8, compressed_data[0..], result_list.items);
}

test "PCX RLE Fast encoder should encore more than 63 bytes similar" {
    const first_uncompressed_part = [_]u8{0x45} ** 65;
    const second_uncompresse_part = [_]u8{ 0x1, 0x1, 0x1, 0x1 };
    const uncompressed_data = first_uncompressed_part ++ second_uncompresse_part;

    const compressed_data = [_]u8{ 0xFF, 0x45, 0x45, 0x45, 0xC4, 0x1 };

    var result_list = std.ArrayList(u8).init(std.testing.allocator);
    defer result_list.deinit();

    const writer = result_list.writer();

    try RLEFastEncoder.encode(uncompressed_data[0..], writer);

    try std.testing.expectEqualSlices(u8, compressed_data[0..], result_list.items);
}

const RLEStreamEncoder = struct {
    rle_byte: ?u8 = null,
    length: usize = 0,

    pub fn encode(self: *RLEStreamEncoder, writer: anytype, bytes: []const u8) !void {
        for (bytes) |byte| {
            try self.encodeByte(writer, byte);
        }
    }

    pub fn encodeByte(self: *RLEStreamEncoder, writer: anytype, byte: u8) !void {
        if (self.rle_byte == null) {
            self.rle_byte = byte;
            self.length = 1;
            return;
        }

        if (self.rle_byte) |rle_byte| {
            if (rle_byte == byte) {
                self.length += 1;
            } else {
                try flushRLE(writer, rle_byte, self.length);

                self.length = 1;
                self.rle_byte = byte;
            }
        }
    }

    pub fn flush(self: *RLEStreamEncoder, writer: anytype) !void {
        if (self.length == 0) {
            return;
        }

        if (self.rle_byte) |check_byte| {
            try flushRLE(writer, check_byte, self.length);
        }
    }
};

pub const PCX = struct {
    header: PCXHeader = .{},

    pub const EncoderOptions = struct {};

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

        if (magic_number_bufffer[0] != MagicHeader) {
            return false;
        }

        if (magic_number_bufffer[1] > Version) {
            return false;
        }

        return true;
    }

    pub fn readImage(allocator: Allocator, stream: *Image.Stream) ImageReadError!Image {
        var result = Image.init(allocator);
        errdefer result.deinit();
        var pcx = PCX{};

        const pixels = try pcx.read(allocator, stream);

        result.width = pcx.width();
        result.height = pcx.height();
        result.pixels = pixels;

        return result;
    }

    pub fn writeImage(allocator: Allocator, stream: *Image.Stream, image: Image, encoder_options: Image.EncoderOptions) ImageWriteError!void {
        _ = allocator;
        _ = encoder_options;

        var pcx = PCX{};

        if (image.width > std.math.maxInt(u16) or image.height > std.math.maxInt(u16)) {
            return ImageWriteError.Unsupported;
        }

        pcx.header.xmax = @truncate(image.width - 1);
        pcx.header.ymax = @truncate(image.height - 1);

        // Fill header info based on image
        switch (image.pixels) {
            .indexed1 => |pixels| {
                pcx.header.bpp = 1;
                pcx.header.planes = 1;

                pcx.fillPalette(pixels.palette);
            },
            .indexed4 => |pixels| {
                pcx.header.bpp = 4;
                pcx.header.planes = 1;

                pcx.fillPalette(pixels.palette);
            },
            .indexed8 => {
                pcx.header.bpp = 8;
                pcx.header.planes = 1;
            },
            .rgb24 => {
                pcx.header.bpp = 8;
                pcx.header.planes = 3;
            },
            else => {
                return ImageWriteError.Unsupported;
            },
        }

        pcx.header.stride = @as(u16, @intFromFloat((@as(f32, @floatFromInt(image.width)) / 8.0) * @as(f32, @floatFromInt(pcx.header.bpp))));
        // Add one if the result is a odd number
        pcx.header.stride += (pcx.header.stride & 0x1);

        try pcx.write(stream, image.pixels);
    }

    pub fn pixelFormat(self: PCX) ImageReadError!PixelFormat {
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

    pub fn width(self: PCX) usize {
        return self.header.xmax - self.header.xmin + 1;
    }

    pub fn height(self: PCX) usize {
        return self.header.ymax - self.header.ymin + 1;
    }

    pub fn read(self: *PCX, allocator: Allocator, stream: *Image.Stream) ImageReadError!color.PixelStorage {
        var buffered_stream = buffered_stream_source.bufferedStreamSourceReader(stream);
        const reader = buffered_stream.reader();
        self.header = try utils.readStruct(reader, PCXHeader, .little);

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

        const image_width = self.width();
        const image_height = self.height();

        const has_dummy_byte = (@as(i16, @bitCast(self.header.stride)) - @as(isize, @bitCast(image_width))) == 1;
        const actual_width = if (has_dummy_byte) image_width + 1 else image_width;

        var pixels = try color.PixelStorage.init(allocator, pixel_format, image_width * image_height);
        errdefer pixels.deinit(allocator);

        var decoder = RLEDecoder.init(reader);

        const scanline_length = (self.header.stride * self.header.planes);

        var y: usize = 0;
        while (y < image_height) : (y += 1) {
            var offset: usize = 0;
            var x: usize = 0;

            const y_stride = y * image_width;

            // read all pixels from the current row
            while (offset < scanline_length and x < image_width) : (offset += 1) {
                const byte = try decoder.readByte();
                switch (pixels) {
                    .indexed1 => |storage| {
                        var i: usize = 0;
                        while (i < 8) : (i += 1) {
                            if (x < image_width) {
                                storage.indices[y_stride + x] = @intCast((byte >> (7 - @as(u3, @intCast(i)))) & 0x01);
                                x += 1;
                            }
                        }
                    },
                    .indexed4 => |storage| {
                        storage.indices[y_stride + x] = @truncate(byte >> 4);
                        x += 1;
                        if (x < image_width) {
                            storage.indices[y_stride + x] = @truncate(byte);
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
            var palette = switch (pixels) {
                .indexed1 => |*storage| storage.palette[0..],
                .indexed4 => |*storage| storage.palette[0..],
                .indexed8 => |*storage| storage.palette[0..],
                else => undefined,
            };

            const effective_len = @min(palette.len, self.header.builtin_palette.len);
            for (0..effective_len) |index| {
                palette[index].r = self.header.builtin_palette[index].r;
                palette[index].g = self.header.builtin_palette[index].g;
                palette[index].b = self.header.builtin_palette[index].b;
                palette[index].a = 255;
            }

            if (pixels == .indexed8) {
                const end_pos = try buffered_stream.getEndPos();
                try buffered_stream.seekTo(end_pos - 769);

                if ((try reader.readByte()) != VGAPaletteIdentifier) {
                    return ImageReadError.InvalidData;
                }

                for (palette) |*current_entry| {
                    current_entry.r = try reader.readByte();
                    current_entry.g = try reader.readByte();
                    current_entry.b = try reader.readByte();
                    current_entry.a = 255;
                }
            }
        }

        return pixels;
    }

    pub fn write(self: PCX, stream: *Image.Stream, pixels: color.PixelStorage) Image.WriteError!void {
        switch (pixels) {
            .indexed1,
            .indexed4,
            .indexed8,
            .rgb24,
            => {
                // Do nothing
            },
            else => {
                return ImageWriteError.Unsupported;
            },
        }

        var buffered_stream = buffered_stream_source.bufferedStreamSourceWriter(stream);

        const writer = buffered_stream.writer();

        try utils.writeStruct(writer, self.header, .little);

        const actual_width = self.width();
        const is_even = ((actual_width & 0x1) == 0);

        switch (pixels) {
            .indexed1 => |indexed| {
                try self.writeIndexed1(writer, indexed);
            },
            .indexed4 => |indexed| {
                try self.writeIndexed4(writer, indexed);
            },
            .indexed8 => |indexed| {
                if (is_even) {
                    try writeIndexed8Even(writer, indexed);
                } else {
                    try self.writeIndexed8Odd(writer, indexed);
                }

                // Write VGA palette
                try writer.writeByte(VGAPaletteIdentifier);
                for (pixels.indexed8.palette) |current_entry| {
                    const rgb24_color = color.Rgb24.fromU32Rgba(current_entry.toU32Rgba());
                    try utils.writeStruct(writer, rgb24_color, .little);
                }
            },
            .rgb24 => |data| {
                try self.writeRgb24(writer, data);
            },
            else => {
                return ImageWriteError.Unsupported;
            },
        }

        try buffered_stream.flush();
    }

    fn fillPalette(self: *PCX, palette: []const color.Rgba32) void {
        const effective_len = @min(palette.len, self.header.builtin_palette.len);
        for (0..effective_len) |index| {
            self.header.builtin_palette[index].r = palette[index].r;
            self.header.builtin_palette[index].g = palette[index].g;
            self.header.builtin_palette[index].b = palette[index].b;
        }
    }

    fn writeIndexed1(self: *const PCX, writer: buffered_stream_source.DefaultBufferedStreamSourceWriter.Writer, indexed: color.IndexedStorage1) Image.WriteError!void {
        var rle_encoder = RLEStreamEncoder{};

        const image_width = self.width();
        const image_height = self.height();

        const is_even = ((image_width & 0x1) == 0);

        for (0..image_height) |y| {
            const stride = y * image_width;

            var current_byte: u8 = 0;

            for (0..image_width) |x| {
                const pixel = indexed.indices[stride + x];

                const bit = @as(u3, @intCast(7 - (x % 8)));

                current_byte |= @as(u8, pixel) << bit;
                if (bit == 0) {
                    try rle_encoder.encodeByte(writer, current_byte);
                    current_byte = 0;
                }
            }

            if (!is_even) {
                try rle_encoder.encodeByte(writer, current_byte);
            }
        }

        try rle_encoder.flush(writer);
    }

    fn writeIndexed4(self: *const PCX, writer: buffered_stream_source.DefaultBufferedStreamSourceWriter.Writer, indexed: color.IndexedStorage4) Image.WriteError!void {
        var rle_encoder = RLEStreamEncoder{};

        const image_width = self.width();
        const image_height = self.height();

        const is_even = ((image_width & 0x1) == 0);

        var current_byte: u8 = 0;

        for (0..image_height) |y| {
            const stride = y * image_width;

            for (0..image_width) |x| {
                const pixel = indexed.indices[stride + x];

                if ((x & 0x1) == 0x1) {
                    current_byte |= pixel;
                    try rle_encoder.encodeByte(writer, current_byte);
                } else {
                    current_byte = @as(u8, pixel) << 4;
                }
            }

            if (!is_even) {
                try rle_encoder.encodeByte(writer, current_byte);
            }
        }

        try rle_encoder.flush(writer);
    }

    fn writeIndexed8Even(writer: buffered_stream_source.DefaultBufferedStreamSourceWriter.Writer, indexed: color.IndexedStorage8) Image.WriteError!void {
        try RLEFastEncoder.encode(indexed.indices, writer);
    }

    fn writeIndexed8Odd(self: *const PCX, writer: buffered_stream_source.DefaultBufferedStreamSourceWriter.Writer, indexed: color.IndexedStorage8) Image.WriteError!void {
        var rle_encoder = RLEStreamEncoder{};

        const image_width = self.width();
        const image_height = self.height();

        for (0..image_height) |y| {
            const y_stride = y * image_width;

            const pixel_stride = indexed.indices[y_stride..(y_stride + image_width)];
            try rle_encoder.encode(writer, pixel_stride);
            try rle_encoder.encodeByte(writer, 0x00);
        }

        try rle_encoder.flush(writer);
    }

    fn writeRgb24(self: *const PCX, writer: buffered_stream_source.DefaultBufferedStreamSourceWriter.Writer, pixels: []const color.Rgb24) Image.WriteError!void {
        var rle_encoder = RLEStreamEncoder{};

        const image_width = self.width();
        const image_height = self.height();

        const is_even = ((image_width & 0x1) == 0);

        for (0..image_height) |y| {
            const stride = y * image_width;

            for (0..3) |plane| {
                for (0..image_width) |x| {
                    const current_color = pixels[stride + x];
                    switch (plane) {
                        0 => try rle_encoder.encodeByte(writer, current_color.r),
                        1 => try rle_encoder.encodeByte(writer, current_color.g),
                        2 => try rle_encoder.encodeByte(writer, current_color.b),
                        else => {},
                    }
                }

                if (!is_even) {
                    try rle_encoder.encodeByte(writer, 0x00);
                }
            }
        }

        try rle_encoder.flush(writer);
    }
};
