// Implement PNG image format according to W3C Portable Network Graphics (PNG) specification second edition (ISO/IEC 15948:2003 (E))
// Last version: https://www.w3.org/TR/PNG/

const std = @import("std");
const types = @import("png/types.zig");
const reader = @import("png/reader.zig");
const chunk_writer = @import("png/chunk_writer.zig");
const filter = @import("png/filtering.zig");
const color = @import("../color.zig");
const PixelFormat = @import("../pixel_format.zig").PixelFormat;
const ZlibCompressor = @import("png/zlib_compressor.zig").ZlibCompressor;
const Image = @import("../Image.zig");
const FormatInterface = @import("../format_interface.zig").FormatInterface;
const ImageReadError = Image.ReadError;
const ImageWriteError = Image.WriteError;
const Allocator = std.mem.Allocator;

pub const HeaderData = types.HeaderData;
pub const ColorType = types.ColorType;
pub const CompressionMethod = types.CompressionMethod;
pub const FilterMethod = types.FilterMethod;
pub const FilterType = types.FilterType;
pub const InterlaceMethod = types.InterlaceMethod;
pub const Chunks = types.Chunks;
pub const isChunkCritical = reader.isChunkCritical;
pub const load = reader.load;
pub const loadHeader = reader.loadHeader;
pub const loadWithHeader = reader.loadWithHeader;
pub const ChunkProcessData = reader.ChunkProcessData;
pub const PaletteProcessData = reader.PaletteProcessData;
pub const RowProcessData = reader.RowProcessData;
pub const ReaderProcessor = reader.ReaderProcessor;
pub const TrnsProcessor = reader.TrnsProcessor;
pub const PlteProcessor = reader.PlteProcessor;
pub const ReaderOptions = reader.ReaderOptions;
pub const DefaultProcessors = reader.DefaultProcessors;
pub const DefaultOptions = reader.DefaultOptions;
pub const required_temp_bytes = reader.required_temp_bytes;

pub const PNG = struct {
    const Self = @This();

    pub const EncoderOptions = struct {
        // For progressive rendering of big images
        interlaced: bool = false,
        // Changing this can affect performance positively or negatively
        filter_choice: filter.FilterChoice = .heuristic,
    };

    pub fn formatInterface() FormatInterface {
        return FormatInterface{
            .format = format,
            .formatDetect = formatDetect,
            .readImage = readImage,
            .writeImage = writeImage,
        };
    }

    pub fn format() Image.Format {
        return Image.Format.png;
    }

    pub fn formatDetect(stream: *Image.Stream) ImageReadError!bool {
        var magic_buffer: [types.magic_header.len]u8 = undefined;

        _ = try stream.reader().readAll(magic_buffer[0..]);

        return std.mem.eql(u8, magic_buffer[0..], types.magic_header[0..]);
    }

    pub fn readImage(allocator: Allocator, stream: *Image.Stream) ImageReadError!Image {
        var default_options = DefaultOptions{};
        return load(stream, allocator, default_options.get());
    }

    pub fn writeImage(allocator: Allocator, write_stream: *Image.Stream, image: Image, encoder_options: Image.EncoderOptions) ImageWriteError!void {
        const options = encoder_options.png;

        try ensureWritable(image);

        const header = HeaderData{
            .width = @truncate(u32, image.width),
            .height = @truncate(u32, image.height),
            .bit_depth = image.pixelFormat().bitsPerChannel(),
            .color_type = try types.ColorType.fromPixelFormat(image.pixelFormat()),
            .compression_method = .deflate,
            .filter_method = .adaptive,
            .interlace_method = if (options.interlaced) .adam7 else .none,
        };

        std.debug.assert(header.isValid());

        try write(allocator, write_stream, image.pixels, header, options.filter_choice);
    }

    pub fn write(allocator: Allocator, write_stream: *Image.Stream, pixels: color.PixelStorage, header: HeaderData, filter_choice: filter.FilterChoice) ImageWriteError!void {
        if (header.interlace_method != .none)
            return ImageWriteError.Unsupported;
        if (header.compression_method != .deflate)
            return ImageWriteError.Unsupported;
        if (header.filter_method != .adaptive)
            return ImageWriteError.Unsupported;

        var writer = write_stream.writer();

        try writeSignature(writer);
        try writeHeader(writer, header);
        if (PixelFormat.isIndex(pixels)) {
            try writePalette(writer, pixels);
            try writeTransparencyInfo(writer, pixels); // TODO: pixel format where there is no transparency
        }
        try writeData(allocator, writer, pixels, header, filter_choice);
        try writeTrailer(writer);
    }

    pub fn ensureWritable(image: Image) !void {
        if (image.width > std.math.maxInt(u31))
            return error.Unsupported;
        if (image.height > std.math.maxInt(u31))
            return error.Unsupported;

        switch (image.pixels) {
            .rgb24, .rgb48, .rgba32, .rgba64, .grayscale8, .grayscale16, .grayscale8Alpha, .grayscale16Alpha, .indexed8 => {},

            .grayscale1, .grayscale2, .grayscale4, .indexed1, .indexed2, .indexed4 => return error.Unsupported, // TODO

            // Should bgr be supported with swapping operations during the filtering?

            else => return error.Unsupported,
        }
    }

    fn writeSignature(writer: anytype) !void {
        try writer.writeAll(types.magic_header);
    }

    // IHDR
    fn writeHeader(writer: anytype, header: HeaderData) ImageWriteError!void {
        var chunk = chunk_writer.chunkWriter(writer, "IHDR");
        var chunk_wr = chunk.writer();

        try chunk_wr.writeIntBig(u32, header.width);
        try chunk_wr.writeIntBig(u32, header.height);
        try chunk_wr.writeIntBig(u8, header.bit_depth);
        try chunk_wr.writeIntBig(u8, @enumToInt(header.color_type));
        try chunk_wr.writeIntBig(u8, @enumToInt(header.compression_method));
        try chunk_wr.writeIntBig(u8, @enumToInt(header.filter_method));
        try chunk_wr.writeIntBig(u8, @enumToInt(header.interlace_method));

        try chunk.flush();
    }

    // IDAT (multiple maybe)
    fn writeData(allocator: Allocator, writer: anytype, pixels: color.PixelStorage, header: HeaderData, filter_choice: filter.FilterChoice) ImageWriteError!void {
        // Note: there may be more than 1 chunk
        // TODO: provide choice of how much it buffers (how much data per idat chunk)
        var chunks = chunk_writer.chunkWriter(writer, "IDAT");
        var chunk_wr = chunks.writer();

        var zlib: ZlibCompressor(@TypeOf(chunk_wr)) = undefined;
        try zlib.init(allocator, chunk_wr);

        try zlib.begin();
        try filter.filter(zlib.writer(), pixels, filter_choice, header);
        try zlib.end();

        try chunks.flush();
    }

    // IEND chunk
    fn writeTrailer(writer: anytype) ImageWriteError!void {
        var chunk = chunk_writer.chunkWriter(writer, "IEND");
        try chunk.flush();
    }

    // PLTE (if indexed storage)
    fn writePalette(writer: anytype, pixels: color.PixelStorage) ImageWriteError!void {
        var chunk = chunk_writer.chunkWriter(writer, "PLTE");
        var chunk_wr = chunk.writer();

        const palette = switch (pixels) {
            .indexed1 => |d| d.palette,
            .indexed2 => |d| d.palette,
            .indexed4 => |d| d.palette,
            .indexed8 => |d| d.palette,
            .indexed16 => return ImageWriteError.Unsupported,
            else => unreachable,
        };

        for (palette) |col| {
            try chunk_wr.writeByte(col.r);
            try chunk_wr.writeByte(col.g);
            try chunk_wr.writeByte(col.b);
        }

        try chunk.flush();
    }

    // tRNS (if indexed storage with transparency (there may be other uses later))
    fn writeTransparencyInfo(writer: anytype, pixels: color.PixelStorage) ImageWriteError!void {
        var chunk = chunk_writer.chunkWriter(writer, "tRNS");
        var chunk_wr = chunk.writer();

        const palette = switch (pixels) {
            .indexed1 => |d| d.palette,
            .indexed2 => |d| d.palette,
            .indexed4 => |d| d.palette,
            .indexed8 => |d| d.palette,
            .indexed16 => return ImageWriteError.Unsupported,
            // TODO: png support transparency info for other formats?
            else => unreachable,
        };

        for (palette) |col| {
            try chunk_wr.writeByte(col.a);
        }

        try chunk.flush();
    }
};
