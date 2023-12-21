const buffered_stream_source = @import("../buffered_stream_source.zig");
const color = @import("../color.zig");
const FormatInterface = @import("../FormatInterface.zig");
const Image = @import("../Image.zig");
const PixelFormat = @import("../pixel_format.zig").PixelFormat;
const std = @import("std");
const utils = @import("../utils.zig");

const BitmapMagicHeader = [_]u8{ 'B', 'M' };

pub const BitmapFileHeader = extern struct {
    magic_header: [2]u8 = BitmapMagicHeader,
    size: u32 align(1) = 0,
    reserved: u32 align(1) = 0,
    pixel_offset: u32 align(1) = 0,
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
    srgb = utils.toMagicNumber("sRGB", .big),
    windows_color_space = utils.toMagicNumber("Win ", .big),
    profile_linked = utils.toMagicNumber("LINK", .big),
    profile_embedded = utils.toMagicNumber("MBED", .big),
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
    compression_method: CompressionMethod = .none,
    image_raw_size: u32 = 0,
    horizontal_resolution: u32 = 0,
    vertical_resolution: u32 = 0,
    palette_size: u32 = 0,
    important_colors: u32 = 0,

    pub const HeaderSize = @sizeOf(BitmapInfoHeaderWindows31);
};

pub const BitmapInfoHeaderV4 = extern struct {
    header_size: u32 = 0,
    width: i32 = 0,
    height: i32 = 0,
    color_plane: u16 align(1) = 0,
    bit_count: u16 align(1) = 0,
    compression_method: CompressionMethod = .none,
    image_raw_size: u32 = 0,
    horizontal_resolution: u32 = 0,
    vertical_resolution: u32 = 0,
    palette_size: u32 = 0,
    important_colors: u32 = 0,
    red_mask: u32 = 0,
    green_mask: u32 = 0,
    blue_mask: u32 = 0,
    alpha_mask: u32 = 0,
    color_space: BitmapColorSpace = .srgb,
    cie_end_points: CieXyzTriple = .{},
    gamma_red: u32 = 0,
    gamma_green: u32 = 0,
    gamma_blue: u32 = 0,

    pub const HeaderSize = @sizeOf(BitmapInfoHeaderV4);
};

pub const BitmapInfoHeaderV5 = extern struct {
    header_size: u32 = 0,
    width: i32 = 0,
    height: i32 = 0,
    color_plane: u16 align(1) = 0,
    bit_count: u16 align(1) = 0,
    compression_method: CompressionMethod = .none,
    image_raw_size: u32 = 0,
    horizontal_resolution: u32 = 0,
    vertical_resolution: u32 = 0,
    palette_size: u32 = 0,
    important_colors: u32 = 0,
    red_mask: u32 = 0,
    green_mask: u32 = 0,
    blue_mask: u32 = 0,
    alpha_mask: u32 = 0,
    color_space: BitmapColorSpace = .srgb,
    cie_end_points: CieXyzTriple = .{},
    gamma_red: u32 = 0,
    gamma_green: u32 = 0,
    gamma_blue: u32 = 0,
    intent: BitmapIntent = .graphics,
    profile_data: u32 = 0,
    profile_size: u32 = 0,
    reserved: u32 = 0,

    pub const HeaderSize = @sizeOf(BitmapInfoHeaderV5);
};

pub const BitmapInfoHeader = union(enum) {
    windows31: BitmapInfoHeaderWindows31,
    v4: BitmapInfoHeaderV4,
    v5: BitmapInfoHeaderV5,
};

// Print resolution of the image,
// 72 DPI × 39.3701 inches per metre yields 2834.6472
const PixelsPerMeterResolution = 2835;

pub const BMP = struct {
    file_header: BitmapFileHeader = undefined,
    info_header: BitmapInfoHeader = undefined,

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

    pub fn readImage(allocator: std.mem.Allocator, stream: *Image.Stream) Image.ReadError!Image {
        var result = Image.init(allocator);
        errdefer result.deinit();

        var bmp = BMP{};
        const pixels = try bmp.read(allocator, stream);

        result.width = @intCast(bmp.width());
        result.height = @intCast(bmp.height());
        result.pixels = pixels;

        return result;
    }

    pub fn writeImage(allocator: std.mem.Allocator, stream: *Image.Stream, image: Image, encoder_options: Image.EncoderOptions) Image.WriteError!void {
        var bmp = BMP{};

        //  Fill header information based on pixel format
        switch (image.pixels) {
            .bgr24 => {
                bmp.file_header = .{
                    .size = @intCast(image.width * image.height * 3 + @sizeOf(BitmapFileHeader) + BitmapInfoHeaderV4.HeaderSize),
                    .pixel_offset = @sizeOf(BitmapFileHeader) + BitmapInfoHeaderV4.HeaderSize,
                };

                bmp.info_header = .{
                    .v4 = .{
                        .header_size = BitmapInfoHeaderV4.HeaderSize,
                        .width = @intCast(image.width),
                        .height = @intCast(image.height),
                        .color_plane = 1,
                        .bit_count = 24,
                        .compression_method = .none,
                        .image_raw_size = @intCast(image.width * image.height * 3),
                        .horizontal_resolution = PixelsPerMeterResolution,
                        .vertical_resolution = PixelsPerMeterResolution,
                        .color_space = .srgb,
                    },
                };
            },
            .bgra32 => {
                bmp.file_header = .{
                    .size = @intCast(image.width * image.height * 4 + @sizeOf(BitmapFileHeader) + BitmapInfoHeaderV5.HeaderSize),
                    .pixel_offset = @sizeOf(BitmapFileHeader) + BitmapInfoHeaderV5.HeaderSize,
                };

                bmp.info_header = .{
                    .v5 = .{
                        .header_size = BitmapInfoHeaderV5.HeaderSize,
                        .width = @intCast(image.width),
                        .height = @intCast(image.height),
                        .color_plane = 1,
                        .bit_count = 32,
                        .compression_method = .bitfields, // We must specify the color mask when using an 32-bpp bmp with V5
                        .image_raw_size = @intCast(image.width * image.height * 4),
                        .horizontal_resolution = PixelsPerMeterResolution,
                        .vertical_resolution = PixelsPerMeterResolution,
                        .color_space = .srgb,
                        .red_mask = 0x0000FF00,
                        .green_mask = 0x00FF0000,
                        .blue_mask = 0xFF000000,
                        .alpha_mask = 0x000000FF,
                    },
                };
            },
            else => {
                return Image.WriteError.InvalidData;
            },
        }

        try bmp.write(stream, image.pixels);

        _ = allocator;
        _ = encoder_options;
    }

    pub fn width(self: BMP) i32 {
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

    pub fn height(self: BMP) i32 {
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

    pub fn pixelFormat(self: BMP) Image.ReadError!PixelFormat {
        return switch (self.info_header) {
            .v4 => |v4Header| try findPixelFormat(v4Header.bit_count, v4Header.compression_method),
            .v5 => |v5Header| try findPixelFormat(v5Header.bit_count, v5Header.compression_method),
            else => return Image.Error.Unsupported,
        };
    }

    pub fn read(self: *BMP, allocator: std.mem.Allocator, stream: *Image.Stream) Image.ReadError!color.PixelStorage {
        var buffered_stream = buffered_stream_source.bufferedStreamSourceReader(stream);

        // Read file header
        const reader = buffered_stream.reader();
        self.file_header = try utils.readStruct(reader, BitmapFileHeader, .little);
        if (!std.mem.eql(u8, self.file_header.magic_header[0..], BitmapMagicHeader[0..])) {
            return Image.ReadError.InvalidData;
        }

        const header_size = try reader.readInt(u32, .little);
        try buffered_stream.seekBy(-@sizeOf(u32));

        // Read info header
        self.info_header = switch (header_size) {
            BitmapInfoHeaderWindows31.HeaderSize => BitmapInfoHeader{ .windows31 = try utils.readStruct(reader, BitmapInfoHeaderWindows31, .little) },
            BitmapInfoHeaderV4.HeaderSize => BitmapInfoHeader{ .v4 = try utils.readStruct(reader, BitmapInfoHeaderV4, .little) },
            BitmapInfoHeaderV5.HeaderSize => BitmapInfoHeader{ .v5 = try utils.readStruct(reader, BitmapInfoHeaderV5, .little) },
            else => return Image.Error.Unsupported,
        };

        var pixels: color.PixelStorage = undefined;

        // Read pixel data
        _ = switch (self.info_header) {
            .v4 => |v4Header| {
                const pixel_width = v4Header.width;
                const pixel_height = v4Header.height;
                const pixel_format = try findPixelFormat(v4Header.bit_count, v4Header.compression_method);

                pixels = try color.PixelStorage.init(allocator, pixel_format, @intCast(pixel_width * pixel_height));
                errdefer pixels.deinit(allocator);

                try readPixels(reader, pixel_width, pixel_height, &pixels);
            },
            .v5 => |v5Header| {
                const pixel_width = v5Header.width;
                const pixel_height = v5Header.height;
                const pixel_format = try findPixelFormat(v5Header.bit_count, v5Header.compression_method);

                pixels = try color.PixelStorage.init(allocator, pixel_format, @intCast(pixel_width * pixel_height));
                errdefer pixels.deinit(allocator);

                try readPixels(reader, pixel_width, pixel_height, &pixels);
            },
            else => return Image.Error.Unsupported,
        };

        return pixels;
    }

    pub fn write(self: BMP, stream: *Image.Stream, pixels: color.PixelStorage) Image.WriteError!void {
        var buffered_stream = buffered_stream_source.bufferedStreamSourceWriter(stream);

        const writer = buffered_stream.writer();

        try utils.writeStruct(writer, self.file_header, .little);

        switch (self.info_header) {
            .v4 => |v4| {
                try utils.writeStruct(writer, v4, .little);
            },
            .v5 => |v5| {
                try utils.writeStruct(writer, v5, .little);
            },
            else => {
                return Image.WriteError.InvalidData;
            },
        }

        try writePixels(writer, pixels, self.width(), self.height());

        try buffered_stream.flush();
    }

    fn findPixelFormat(bit_count: u32, compression: CompressionMethod) Image.Error!PixelFormat {
        if (bit_count == 32 and compression == CompressionMethod.bitfields) {
            return PixelFormat.bgra32;
        } else if (bit_count == 24 and compression == CompressionMethod.none) {
            return PixelFormat.bgr24;
        } else {
            return Image.Error.Unsupported;
        }
    }

    fn readPixels(reader: buffered_stream_source.DefaultBufferedStreamSourceReader.Reader, pixel_width: i32, pixel_height: i32, pixels: *color.PixelStorage) Image.ReadError!void {
        return switch (pixels.*) {
            .bgr24 => {
                return readPixelsInternal(pixels.bgr24, reader, pixel_width, pixel_height);
            },
            .bgra32 => {
                return readPixelsInternal(pixels.bgra32, reader, pixel_width, pixel_height);
            },
            else => {
                return Image.Error.Unsupported;
            },
        };
    }

    fn readPixelsInternal(pixels: anytype, reader: buffered_stream_source.DefaultBufferedStreamSourceReader.Reader, pixel_width: i32, pixel_height: i32) Image.ReadError!void {
        const ColorBufferType = @typeInfo(@TypeOf(pixels)).Pointer.child;

        var x: i32 = 0;
        var y: i32 = pixel_height - 1;
        while (y >= 0) : (y -= 1) {
            const scanline = y * pixel_width;

            x = 0;
            while (x < pixel_width) : (x += 1) {
                pixels[@intCast(scanline + x)] = try utils.readStruct(reader, ColorBufferType, .little);
            }
        }
    }

    fn writePixels(writer: buffered_stream_source.DefaultBufferedStreamSourceWriter.Writer, pixels: color.PixelStorage, pixel_width: i32, pixel_height: i32) Image.WriteError!void {
        return switch (pixels) {
            .bgr24 => {
                return writePixelsInternal(pixels.bgr24, writer, pixel_width, pixel_height);
            },
            .bgra32 => {
                return writePixelsInternal(pixels.bgra32, writer, pixel_width, pixel_height);
            },
            else => {
                return Image.WriteError.InvalidData;
            },
        };
    }

    fn writePixelsInternal(pixels: anytype, writer: buffered_stream_source.DefaultBufferedStreamSourceWriter.Writer, pixel_width: i32, pixel_height: i32) Image.WriteError!void {
        var x: i32 = 0;
        var y: i32 = pixel_height - 1;
        while (y >= 0) : (y -= 1) {
            const scanline = y * pixel_width;

            x = 0;
            while (x < pixel_width) : (x += 1) {
                try utils.writeStruct(writer, pixels[@intCast(scanline + x)], .little);
            }
        }
    }
};
