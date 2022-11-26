const Allocator = std.mem.Allocator;
const File = std.fs.File;
const FormatInterface = @import("../format_interface.zig").FormatInterface;
const PixelFormat = @import("../pixel_format.zig").PixelFormat;
const color = @import("../color.zig");
const Image = @import("../Image.zig");
const ImageError = Image.Error;
const ImageReadError = Image.ReadError;
const fs = std.fs;
const io = std.io;
const mem = std.mem;
const path = std.fs.path;
const std = @import("std");
const utils = @import("../utils.zig");

const BitmapMagicHeader = [_]u8{ 'B', 'M' };

pub const BitmapFileHeader = extern struct {
    magic_header: [2]u8,
    size: u32 align(1),
    reserved: u32 align(1),
    pixel_offset: u32 align(1),
};

pub const CompressionMethod = enum(u32) {
    none = 0,
    rle8 = 1,
    rle4 = 2,
    bitfields = 3,
    jpg = 4,
    png = 5,
    alpha_bit_fields = 6,
    cmyk = 11,
    cmyk_rle8 = 12,
    cmyk_rle4 = 13,
};

pub const BitmapColorSpace = enum(u32) {
    calibrated_rgb = 0,
    srgb = utils.toMagicNumberBig("sRGB"),
    windows_color_space = utils.toMagicNumberBig("Win "),
    profile_linked = utils.toMagicNumberBig("LINK"),
    profile_embedded = utils.toMagicNumberBig("MBED"),
};

pub const BitmapIntent = enum(u32) {
    business = 1,
    graphics = 2,
    images = 4,
    absolute_colorimetric = 8,
};

pub const CieXyz = extern struct {
    x: u32 = 0, // TODO: Use FXPT2DOT30
    y: u32 = 0,
    z: u32 = 0,
};

pub const CieXyzTriple = extern struct {
    red: CieXyz = CieXyz{},
    green: CieXyz = CieXyz{},
    blue: CieXyz = CieXyz{},
};

pub const BitmapInfoHeaderWindows31 = extern struct {
    header_size: u32 = 0,
    width: i32 = 0,
    height: i32 = 0,
    color_plane: u16 = 0,
    bit_count: u16 = 0,
    compression_method: CompressionMethod = CompressionMethod.none,
    image_raw_size: u32 = 0,
    horizontal_resolution: u32 = 0,
    vertical_resolution: u32 = 0,
    palette_size: u32 = 0,
    important_colors: u32 = 0,

    pub const HeaderSize = @sizeOf(@This());
};

pub const BitmapInfoHeaderV4 = extern struct {
    header_size: u32 = 0,
    width: i32 = 0,
    height: i32 = 0,
    color_plane: u16 align(1) = 0,
    bit_count: u16 align(1) = 0,
    compression_method: CompressionMethod = CompressionMethod.none,
    image_raw_size: u32 = 0,
    horizontal_resolution: u32 = 0,
    vertical_resolution: u32 = 0,
    palette_size: u32 = 0,
    important_colors: u32 = 0,
    red_mask: u32 = 0,
    green_mask: u32 = 0,
    blue_mask: u32 = 0,
    alpha_mask: u32 = 0,
    color_space: BitmapColorSpace = BitmapColorSpace.srgb,
    cie_end_points: CieXyzTriple = CieXyzTriple{},
    gamma_red: u32 = 0,
    gamma_green: u32 = 0,
    gamma_blue: u32 = 0,

    pub const HeaderSize = @sizeOf(@This());
};

pub const BitmapInfoHeaderV5 = extern struct {
    header_size: u32 = 0,
    width: i32 = 0,
    height: i32 = 0,
    color_plane: u16 align(1) = 0,
    bit_count: u16 align(1) = 0,
    compression_method: CompressionMethod = CompressionMethod.none,
    image_raw_size: u32 = 0,
    horizontal_resolution: u32 = 0,
    vertical_resolution: u32 = 0,
    palette_size: u32 = 0,
    important_colors: u32 = 0,
    red_mask: u32 = 0,
    green_mask: u32 = 0,
    blue_mask: u32 = 0,
    alpha_mask: u32 = 0,
    color_space: BitmapColorSpace = BitmapColorSpace.srgb,
    cie_end_points: CieXyzTriple = CieXyzTriple{},
    gamma_red: u32 = 0,
    gamma_green: u32 = 0,
    gamma_blue: u32 = 0,
    intent: BitmapIntent = BitmapIntent.graphics,
    profile_data: u32 = 0,
    profile_size: u32 = 0,
    reserved: u32 = 0,

    pub const HeaderSize = @sizeOf(@This());
};

pub const BitmapInfoHeader = union(enum) {
    windows31: BitmapInfoHeaderWindows31,
    v4: BitmapInfoHeaderV4,
    v5: BitmapInfoHeaderV5,
};

pub const Bitmap = struct {
    file_header: BitmapFileHeader = undefined,
    info_header: BitmapInfoHeader = undefined,

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
        return Image.Format.bmp;
    }

    pub fn formatDetect(stream: *Image.Stream) Image.Stream.ReadError!bool {
        var magic_number_buffer: [2]u8 = undefined;
        _ = try stream.read(magic_number_buffer[0..]);
        if (std.mem.eql(u8, magic_number_buffer[0..], BitmapMagicHeader[0..])) {
            return true;
        }

        return false;
    }

    pub fn readImage(allocator: Allocator, stream: *Image.Stream) ImageReadError!Image {
        var result = Image.init(allocator);
        errdefer result.deinit();

        var bmp = Self{};
        const pixels = try bmp.read(allocator, stream);

        result.width = @intCast(usize, bmp.width());
        result.height = @intCast(usize, bmp.height());
        result.pixels = pixels;

        return result;
    }

    pub fn writeImage(allocator: Allocator, write_stream: *Image.Stream, image: Image, encoder_options: Image.EncoderOptions) Image.Stream.WriteError!void {
        _ = allocator;
        _ = write_stream;
        _ = image;
        _ = encoder_options;
    }

    pub fn width(self: Self) i32 {
        return switch (self.info_header) {
            .windows31 => |win31| {
                return win31.width;
            },
            .v4 => |v4Header| {
                return v4Header.width;
            },
            .v5 => |v5Header| {
                return v5Header.width;
            },
        };
    }

    pub fn height(self: Self) i32 {
        return switch (self.info_header) {
            .windows31 => |win31| {
                return win31.height;
            },
            .v4 => |v4Header| {
                return v4Header.height;
            },
            .v5 => |v5Header| {
                return v5Header.height;
            },
        };
    }

    pub fn pixelFormat(self: Self) ImageReadError!PixelFormat {
        return switch (self.info_header) {
            .v4 => |v4Header| try findPixelFormat(v4Header.bit_count, v4Header.compression_method),
            .v5 => |v5Header| try findPixelFormat(v5Header.bit_count, v5Header.compression_method),
            else => return ImageError.Unsupported,
        };
    }

    pub fn read(self: *Self, allocator: Allocator, stream: *Image.Stream) ImageReadError!color.PixelStorage {
        // Read file header
        const reader = stream.reader();
        self.file_header = try utils.readStructLittle(reader, BitmapFileHeader);
        if (!mem.eql(u8, self.file_header.magic_header[0..], BitmapMagicHeader[0..])) {
            return ImageReadError.InvalidData;
        }

        // Read header size to figure out the header type, also TODO: Use PeekableStream when I understand how to use it
        const current_header_pos = try stream.getPos();
        var header_size = try reader.readIntLittle(u32);
        try stream.seekTo(current_header_pos);

        // Read info header
        self.info_header = switch (header_size) {
            BitmapInfoHeaderWindows31.HeaderSize => BitmapInfoHeader{ .windows31 = try utils.readStructLittle(reader, BitmapInfoHeaderWindows31) },
            BitmapInfoHeaderV4.HeaderSize => BitmapInfoHeader{ .v4 = try utils.readStructLittle(reader, BitmapInfoHeaderV4) },
            BitmapInfoHeaderV5.HeaderSize => BitmapInfoHeader{ .v5 = try utils.readStructLittle(reader, BitmapInfoHeaderV5) },
            else => return ImageError.Unsupported,
        };

        var pixels: color.PixelStorage = undefined;

        // Read pixel data
        _ = switch (self.info_header) {
            .v4 => |v4Header| {
                const pixel_width = v4Header.width;
                const pixel_height = v4Header.height;
                const pixel_format = try findPixelFormat(v4Header.bit_count, v4Header.compression_method);

                pixels = try color.PixelStorage.init(allocator, pixel_format, @intCast(usize, pixel_width * pixel_height));
                errdefer pixels.deinit(allocator);

                try readPixels(reader, pixel_width, pixel_height, pixel_format, &pixels);
            },
            .v5 => |v5Header| {
                const pixel_width = v5Header.width;
                const pixel_height = v5Header.height;
                const pixel_format = try findPixelFormat(v5Header.bit_count, v5Header.compression_method);

                pixels = try color.PixelStorage.init(allocator, pixel_format, @intCast(usize, pixel_width * pixel_height));
                errdefer pixels.deinit(allocator);

                try readPixels(reader, pixel_width, pixel_height, pixel_format, &pixels);
            },
            else => return ImageError.Unsupported,
        };

        return pixels;
    }

    fn findPixelFormat(bit_count: u32, compression: CompressionMethod) ImageError!PixelFormat {
        if (bit_count == 32 and compression == CompressionMethod.bitfields) {
            return PixelFormat.bgra32;
        } else if (bit_count == 24 and compression == CompressionMethod.none) {
            return PixelFormat.bgr24;
        } else {
            return ImageError.Unsupported;
        }
    }

    fn readPixels(reader: Image.Stream.Reader, pixel_width: i32, pixel_height: i32, pixel_format: PixelFormat, pixels: *color.PixelStorage) ImageReadError!void {
        return switch (pixel_format) {
            PixelFormat.bgr24 => {
                return readPixelsInternal(pixels.bgr24, reader, pixel_width, pixel_height);
            },
            PixelFormat.bgra32 => {
                return readPixelsInternal(pixels.bgra32, reader, pixel_width, pixel_height);
            },
            else => {
                return ImageError.Unsupported;
            },
        };
    }

    fn readPixelsInternal(pixels: anytype, reader: Image.Stream.Reader, pixel_width: i32, pixel_height: i32) ImageReadError!void {
        const ColorBufferType = @typeInfo(@TypeOf(pixels)).Pointer.child;

        var x: i32 = 0;
        var y: i32 = pixel_height - 1;
        while (y >= 0) : (y -= 1) {
            const scanline = y * pixel_width;

            x = 0;
            while (x < pixel_width) : (x += 1) {
                pixels[@intCast(usize, scanline + x)] = try utils.readStructLittle(reader, ColorBufferType);
            }
        }
    }
};
