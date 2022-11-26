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

pub const TGAImageType = packed struct {
    indexed: bool = false,
    truecolor: bool = false,
    pad0: bool = false,
    run_length: bool = false,
    pad1: u4 = 0,
};

pub const TGAColorMapSpec = extern struct {
    first_entry_index: u16 align(1) = 0,
    color_map_length: u16 align(1) = 0,
    color_map_bit_depth: u8 align(1) = 0,
};

pub const TGAImageSpec = extern struct {
    origin_x: u16 align(1) = 0,
    origin_y: u16 align(1) = 0,
    width: u16 align(1) = 0,
    height: u16 align(1) = 0,
    bit_per_pixel: u8 align(1) = 0,
    descriptor: u8 align(1) = 0,
};

pub const TGAHeader = extern struct {
    id_length: u8 align(1) = 0,
    has_color_map: u8 align(1) = 0,
    image_type: TGAImageType align(1) = .{},

    // BEGIN: TGAColorMapSpec
    first_entry_index: u16 align(1) = 0,
    color_map_length: u16 align(1) = 0,
    color_map_bit_depth: u8 align(1) = 0,
    // END TGAColorMapSpec
    // TODO: Use TGAColorMapSpec once all packed struct bugs are fixed
    // color_map_spec: TGAColorMapSpec,

    // BEGIN TGAImageSpec
    origin_x: u16 align(1) = 0,
    origin_y: u16 align(1) = 0,
    width: u16 align(1) = 0,
    height: u16 align(1) = 0,
    bit_per_pixel: u8 align(1) = 0,
    descriptor: u8 align(1) = 0,
    // END TGAImageSpec
    //TODO: Use TGAImageSpec once all packed struct bugs are fixed
    //image_spec: TGAImageSpec,
};

pub const TGAAttributeType = enum(u8) {
    no_alpha = 0,
    undefined_alpha_ignore = 1,
    undefined_alpha_retained = 2,
    useful_alpha_channel = 3,
    premultipled_alpha = 4,
};

pub const TGAExtension = extern struct {
    extension_size: u16 align(1) = 0,
    author_name: [41]u8 align(1) = undefined,
    author_comment: [324]u8 align(1) = undefined,
    timestamp: [12]u8 align(1) = undefined,
    job_id: [41]u8 align(1) = undefined,
    job_time: [6]u8 align(1) = undefined,
    software_id: [41]u8 align(1) = undefined,
    software_version: [3]u8 align(1) = undefined,
    key_color: [4]u8 align(1) = undefined,
    pixel_aspect: [4]u8 align(1) = undefined,
    gamma_value: [4]u8 align(1) = undefined,
    color_correction_offset: u32 align(1) = 0,
    postage_stamp_offset: u32 align(1) = 0,
    scanline_offset: u32 align(1) = 0,
    attributes: TGAAttributeType align(1) = .no_alpha,
};

pub const TGAFooter = extern struct {
    extension_offset: u32 align(1),
    dev_area_offset: u32 align(1),
    signature: [16]u8 align(1),
    dot: u8 align(1),
    null_value: u8 align(1),
};

pub const TGASignature = "TRUEVISION-XFILE";

comptime {
    std.debug.assert(@sizeOf(TGAExtension) == 495);
}

const TargaRLEDecoder = struct {
    source_reader: Image.Stream.Reader,
    allocator: Allocator,
    bytes_per_pixel: usize,

    state: State = .read_header,
    repeat_count: usize = 0,
    repeat_data: []u8 = undefined,
    data_stream: std.io.FixedBufferStream([]u8) = undefined,

    pub const Reader = std.io.Reader(*TargaRLEDecoder, ImageReadError, read);

    const Self = @This();

    const State = enum {
        read_header,
        repeated,
        raw,
    };

    const PacketType = enum(u1) {
        raw = 0,
        repeated = 1,
    };
    const PacketHeader = packed struct {
        pixel_count: u7,
        packet_type: PacketType,
    };

    pub fn init(allocator: Allocator, source_reader: Image.Stream.Reader, bytes_per_pixels: usize) !Self {
        var result = Self{
            .allocator = allocator,
            .source_reader = source_reader,
            .bytes_per_pixel = bytes_per_pixels,
        };

        result.repeat_data = try allocator.alloc(u8, bytes_per_pixels);
        result.data_stream = std.io.fixedBufferStream(result.repeat_data);
        return result;
    }

    pub fn deinit(self: Self) void {
        self.allocator.free(self.repeat_data);
    }

    pub fn read(self: *Self, dest: []u8) ImageReadError!usize {
        var read_count: usize = 0;

        if (self.state == .read_header) {
            const packet_header = try utils.readStructLittle(self.source_reader, PacketHeader);

            if (packet_header.packet_type == .repeated) {
                self.state = .repeated;

                self.repeat_count = @intCast(usize, packet_header.pixel_count) + 1;

                _ = try self.source_reader.read(self.repeat_data);

                self.data_stream.reset();
            } else if (packet_header.packet_type == .raw) {
                self.state = .raw;

                self.repeat_count = (@intCast(usize, packet_header.pixel_count) + 1) * self.bytes_per_pixel;
            }
        }

        switch (self.state) {
            .repeated => {
                _ = try self.data_stream.read(dest);

                const end_pos = try self.data_stream.getEndPos();
                if (self.data_stream.pos >= end_pos) {
                    self.data_stream.reset();

                    self.repeat_count -= 1;
                }

                read_count = dest.len;
            },
            .raw => {
                const read_bytes = try self.source_reader.read(dest);

                self.repeat_count -= read_bytes;

                read_count = read_bytes;
            },
            else => {
                return ImageReadError.InvalidData;
            },
        }

        if (self.repeat_count == 0) {
            self.state = .read_header;
        }

        return read_count;
    }

    pub fn reader(self: *Self) Reader {
        return .{ .context = self };
    }
};

pub const TargaStream = union(enum) {
    image: Image.Stream.Reader,
    rle: TargaRLEDecoder,

    pub const Reader = std.io.Reader(*TargaStream, ImageReadError, read);

    pub fn read(self: *TargaStream, dest: []u8) ImageReadError!usize {
        switch (self.*) {
            .image => |*x| return x.read(dest),
            .rle => |*x| return x.read(dest),
        }
    }

    pub fn reader(self: *TargaStream) Reader {
        return .{ .context = self };
    }
};

pub const TGA = struct {
    header: TGAHeader = .{},
    extension: ?TGAExtension = null,

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
        return Image.Format.tga;
    }

    noinline fn launder(x: usize) usize {
        // Hacky workaround for https://github.com/ziglang/zig/issues/12626
        return x;
    }

    pub fn formatDetect(stream: *Image.Stream) ImageReadError!bool {
        const end_pos = try stream.getEndPos();

        if (launder(@sizeOf(TGAFooter)) < end_pos) {
            const footer_position = end_pos - launder(@sizeOf(TGAFooter));

            try stream.seekTo(footer_position);
            const footer: TGAFooter = try utils.readStructLittle(stream.reader(), TGAFooter);

            if (footer.dot != '.') {
                return false;
            }

            if (footer.null_value != 0) {
                return false;
            }

            if (std.mem.eql(u8, footer.signature[0..], TGASignature[0..])) {
                return true;
            }
        }

        return false;
    }

    pub fn readImage(allocator: Allocator, stream: *Image.Stream) ImageReadError!Image {
        var result = Image.init(allocator);
        errdefer result.deinit();
        var tga = Self{};

        const pixels = try tga.read(allocator, stream);

        result.width = tga.width();
        result.height = tga.height();
        result.pixels = pixels;

        return result;
    }

    pub fn writeImage(allocator: Allocator, write_stream: *Image.Stream, image: Image, encoder_options: Image.EncoderOptions) ImageWriteError!void {
        _ = allocator;
        _ = write_stream;
        _ = image;
        _ = encoder_options;
    }

    pub fn width(self: Self) usize {
        return self.header.width;
    }

    pub fn height(self: Self) usize {
        return self.header.height;
    }

    pub fn pixelFormat(self: Self) ImageReadError!PixelFormat {
        if (self.header.image_type.indexed) {
            if (self.header.image_type.truecolor) {
                return PixelFormat.grayscale8;
            }

            return PixelFormat.indexed8;
        } else if (self.header.image_type.truecolor) {
            switch (self.header.bit_per_pixel) {
                16 => return PixelFormat.rgb555,
                24 => return PixelFormat.rgb24,
                32 => return PixelFormat.rgba32,
                else => {},
            }
        }

        return ImageError.Unsupported;
    }

    pub fn read(self: *Self, allocator: Allocator, stream: *Image.Stream) !color.PixelStorage {
        // Read footage
        const end_pos = try stream.getEndPos();

        if (launder(@sizeOf(TGAFooter)) > end_pos) {
            return ImageReadError.InvalidData;
        }

        const reader = stream.reader();

        _ = end_pos - @sizeOf(TGAFooter);
        try stream.seekTo(end_pos - @sizeOf(TGAFooter));
        const footer: TGAFooter = try utils.readStructLittle(reader, TGAFooter);

        if (!std.mem.eql(u8, footer.signature[0..], TGASignature[0..])) {
            return ImageReadError.InvalidData;
        }

        // Read extension
        if (footer.extension_offset > 0) {
            const extension_pos = @intCast(u64, footer.extension_offset);
            try stream.seekTo(extension_pos);
            self.extension = try utils.readStructLittle(reader, TGAExtension);
        }

        // Read header
        try stream.seekTo(0);
        self.header = try utils.readStructLittle(reader, TGAHeader);

        // Read ID
        if (self.header.id_length > 0) {
            var id_buffer: [256]u8 = undefined;
            std.mem.set(u8, id_buffer[0..], 0);

            const read_id_size = try stream.read(id_buffer[0..self.header.id_length]);

            if (read_id_size != self.header.id_length) {
                return ImageReadError.InvalidData;
            }
        }

        const pixel_format = try self.pixelFormat();

        var pixels = try color.PixelStorage.init(allocator, pixel_format, self.width() * self.height());
        errdefer pixels.deinit(allocator);

        const is_compressed = self.header.image_type.run_length;

        var targa_stream: TargaStream = TargaStream{ .image = reader };
        var rle_decoder: ?TargaRLEDecoder = null;

        defer {
            if (rle_decoder) |rle| {
                rle.deinit();
            }
        }

        if (is_compressed) {
            const bytes_per_pixel = (self.header.bit_per_pixel + 7) / 8;

            rle_decoder = try TargaRLEDecoder.init(allocator, reader, bytes_per_pixel);
            if (rle_decoder) |rle| {
                targa_stream = TargaStream{ .rle = rle };
            }
        }

        switch (pixel_format) {
            .grayscale8 => {
                try self.readGrayscale8(pixels.grayscale8, targa_stream.reader());
            },
            .indexed8 => {
                // Read color map
                switch (self.header.color_map_bit_depth) {
                    15, 16 => {
                        try self.readColorMap16(pixels.indexed8, (TargaStream{ .image = reader }).reader());
                    },
                    else => {
                        return ImageError.Unsupported;
                    },
                }

                // Read indices
                try self.readIndexed8(pixels.indexed8, targa_stream.reader());
            },
            .rgb555 => {
                try self.readTruecolor16(pixels.rgb555, targa_stream.reader());
            },
            .rgb24 => {
                try self.readTruecolor24(pixels.rgb24, targa_stream.reader());
            },
            .rgba32 => {
                try self.readTruecolor32(pixels.rgba32, targa_stream.reader());
            },
            else => {
                return ImageError.Unsupported;
            },
        }

        return pixels;
    }

    fn readGrayscale8(self: *Self, data: []color.Grayscale8, stream: TargaStream.Reader) ImageReadError!void {
        var data_index: usize = 0;
        const data_end: usize = self.width() * self.height();

        while (data_index < data_end) : (data_index += 1) {
            data[data_index] = color.Grayscale8{ .value = try stream.readByte() };
        }
    }

    fn readIndexed8(self: *Self, data: color.IndexedStorage8, stream: TargaStream.Reader) ImageReadError!void {
        var data_index: usize = 0;
        const data_end: usize = self.width() * self.height();

        while (data_index < data_end) : (data_index += 1) {
            data.indices[data_index] = try stream.readByte();
        }
    }

    fn readColorMap16(self: *Self, data: color.IndexedStorage8, stream: TargaStream.Reader) ImageReadError!void {
        var data_index: usize = self.header.first_entry_index;
        const data_end: usize = self.header.first_entry_index + self.header.color_map_length;

        while (data_index < data_end) : (data_index += 1) {
            const raw_color = try stream.readIntLittle(u16);

            data.palette[data_index].r = color.scaleToIntColor(u8, (@truncate(u5, raw_color >> (5 * 2))));
            data.palette[data_index].g = color.scaleToIntColor(u8, (@truncate(u5, raw_color >> 5)));
            data.palette[data_index].b = color.scaleToIntColor(u8, (@truncate(u5, raw_color)));
            data.palette[data_index].a = 255;
        }
    }

    fn readTruecolor16(self: *Self, data: []color.Rgb555, stream: TargaStream.Reader) ImageReadError!void {
        var data_index: usize = 0;
        const data_end: usize = self.width() * self.height();

        while (data_index < data_end) : (data_index += 1) {
            const raw_color = try stream.readIntLittle(u16);

            data[data_index].r = @truncate(u5, raw_color >> (5 * 2));
            data[data_index].g = @truncate(u5, raw_color >> 5);
            data[data_index].b = @truncate(u5, raw_color);
        }
    }

    fn readTruecolor24(self: *Self, data: []color.Rgb24, stream: TargaStream.Reader) ImageReadError!void {
        var data_index: usize = 0;
        const data_end: usize = self.width() * self.height();

        while (data_index < data_end) : (data_index += 1) {
            data[data_index].b = try stream.readByte();
            data[data_index].g = try stream.readByte();
            data[data_index].r = try stream.readByte();
        }
    }

    fn readTruecolor32(self: *Self, data: []color.Rgba32, stream: TargaStream.Reader) ImageReadError!void {
        var data_index: usize = 0;
        const data_end: usize = self.width() * self.height();

        while (data_index < data_end) : (data_index += 1) {
            data[data_index].b = try stream.readByte();
            data[data_index].g = try stream.readByte();
            data[data_index].r = try stream.readByte();
            data[data_index].a = try stream.readByte();

            if (self.extension) |extended_info| {
                if (extended_info.attributes != TGAAttributeType.useful_alpha_channel) {
                    data[data_index].a = 0xFF;
                }
            }
        }
    }
};
