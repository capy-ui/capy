const std = @import("std");
const buffered_stream_source = @import("../buffered_stream_source.zig");

const Allocator = std.mem.Allocator;

const ImageError = Image.Error;
const ImageReadError = Image.ReadError;
const ImageWriteError = Image.WriteError;
const Image = @import("../Image.zig");
const FormatInterface = @import("../FormatInterface.zig");
const color = @import("../color.zig");
const PixelFormat = @import("../pixel_format.zig").PixelFormat;

const FrameHeader = @import("./jpeg/FrameHeader.zig");
const JFIFHeader = @import("./jpeg/JFIFHeader.zig");

const Markers = @import("./jpeg/utils.zig").Markers;
const ZigzagOffsets = @import("./jpeg/utils.zig").ZigzagOffsets;
const IDCTMultipliers = @import("./jpeg/utils.zig").IDCTMultipliers;
const QuantizationTable = @import("./jpeg/quantization.zig").Table;

const HuffmanReader = @import("./jpeg/huffman.zig").Reader;
const HuffmanTable = @import("./jpeg/huffman.zig").Table;
const Frame = @import("./jpeg/Frame.zig");
const Scan = @import("./jpeg/Scan.zig");

// TODO: Chroma subsampling
// TODO: Progressive scans
// TODO: Non-baseline sequential DCT
// TODO: Precisions other than 8-bit

// TODO: Hierarchical mode of JPEG compression.

const JPEG_DEBUG = false;

pub const JPEG = struct {
    frame: ?Frame = null,
    allocator: Allocator,
    quantization_tables: [4]?QuantizationTable,

    pub fn init(allocator: Allocator) JPEG {
        return .{
            .allocator = allocator,
            .quantization_tables = [_]?QuantizationTable{null} ** 4,
        };
    }

    pub fn deinit(self: *JPEG) void {
        if (self.frame) |*frame| {
            frame.deinit();
        }
    }

    fn parseDefineQuantizationTables(self: *JPEG, reader: buffered_stream_source.DefaultBufferedStreamSourceReader.Reader) ImageReadError!void {
        var segment_size = try reader.readInt(u16, .big);
        if (JPEG_DEBUG) std.debug.print("DefineQuantizationTables: segment size = 0x{X}\n", .{segment_size});
        segment_size -= 2;

        while (segment_size > 0) {
            const precision_and_destination = try reader.readByte();
            const table_precision = precision_and_destination >> 4;
            const table_destination = precision_and_destination & 0b11;

            const quantization_table = try QuantizationTable.read(table_precision, reader);
            switch (quantization_table) {
                .q8 => segment_size -= 64 + 1,
                .q16 => segment_size -= 128 + 1,
            }

            self.quantization_tables[table_destination] = quantization_table;
            if (JPEG_DEBUG) std.debug.print("  Table with precision {} installed at {}\n", .{ table_precision, table_destination });
        }
    }

    fn parseScan(self: *JPEG, reader: buffered_stream_source.DefaultBufferedStreamSourceReader.Reader, pixels_opt: *?color.PixelStorage) ImageReadError!void {
        if (self.frame) |frame| {
            try Scan.performScan(&frame, reader, pixels_opt);
        } else return ImageReadError.InvalidData;
    }

    fn initializePixels(self: *JPEG, pixels_opt: *?color.PixelStorage) ImageReadError!void {
        if (self.frame) |frame| {
            var pixel_format: PixelFormat = undefined;
            switch (frame.frame_header.components.len) {
                1 => pixel_format = .grayscale8,
                3 => pixel_format = .rgb24,
                else => unreachable,
            }

            const pixel_count = @as(usize, @intCast(frame.frame_header.samples_per_row)) * @as(usize, @intCast(frame.frame_header.row_count));
            pixels_opt.* = try color.PixelStorage.init(self.allocator, pixel_format, pixel_count);
        } else return ImageReadError.InvalidData;
    }

    pub fn read(self: *JPEG, stream: *Image.Stream, pixels_opt: *?color.PixelStorage) ImageReadError!Frame {
        var buffered_stream = buffered_stream_source.bufferedStreamSourceReader(stream);

        const jfif_header = JFIFHeader.read(&buffered_stream) catch |err| switch (err) {
            error.App0MarkerDoesNotExist, error.JfifIdentifierNotSet, error.ThumbnailImagesUnsupported, error.ExtraneousApplicationMarker => return ImageReadError.InvalidData,
            else => |e| return e,
        };
        _ = jfif_header;

        errdefer {
            if (pixels_opt.*) |pixels| {
                pixels.deinit(self.allocator);
                pixels_opt.* = null;
            }
        }

        const reader = buffered_stream.reader();
        var marker = try reader.readInt(u16, .big);
        while (marker != @intFromEnum(Markers.end_of_image)) : (marker = try reader.readInt(u16, .big)) {
            if (JPEG_DEBUG) std.debug.print("Parsing marker value: 0x{X}\n", .{marker});

            if (marker >= @intFromEnum(Markers.application0) and marker < @intFromEnum(Markers.application0) + 16) {
                if (JPEG_DEBUG) std.debug.print("Skipping application data segment\n", .{});
                const application_data_length = try reader.readInt(u16, .big);
                try buffered_stream.seekBy(application_data_length - 2);
                continue;
            }

            switch (@as(Markers, @enumFromInt(marker))) {
                // TODO(angelo): this should be moved inside the frameheader, it's part of thet
                // and then the header just dispatches correctly what to do with it.
                // JPEG should be as clear as possible
                .sof0 => { // Baseline DCT
                    if (self.frame != null) {
                        return ImageError.Unsupported;
                    }

                    self.frame = try Frame.read(self.allocator, &self.quantization_tables, &buffered_stream);
                },

                .sof1 => return ImageError.Unsupported, // extended sequential DCT Huffman coding
                .sof2 => return ImageError.Unsupported, // progressive DCT Huffman coding
                .sof3 => return ImageError.Unsupported, // lossless (sequential) Huffman coding
                .sof5 => return ImageError.Unsupported,
                .sof6 => return ImageError.Unsupported,
                .sof7 => return ImageError.Unsupported,
                .sof9 => return ImageError.Unsupported, // extended sequential DCT arithmetic coding
                .sof10 => return ImageError.Unsupported, // progressive DCT arithmetic coding
                .sof11 => return ImageError.Unsupported, // lossless (sequential) arithmetic coding
                .sof13 => return ImageError.Unsupported,
                .sof14 => return ImageError.Unsupported,
                .sof15 => return ImageError.Unsupported,

                .start_of_scan => {
                    try self.initializePixels(pixels_opt);
                    try self.parseScan(reader, pixels_opt);
                },

                .define_quantization_tables => {
                    try self.parseDefineQuantizationTables(reader);
                },

                .comment => {
                    if (JPEG_DEBUG) std.debug.print("Skipping comment segment\n", .{});

                    const comment_length = try reader.readInt(u16, .big);
                    try buffered_stream.seekBy(comment_length - 2);
                },

                else => {
                    // TODO(angelo): raise invalid marker, more precise error.
                    return ImageReadError.InvalidData;
                },
            }
        }

        return if (self.frame) |frame| frame else ImageReadError.InvalidData;
    }

    // Format interface
    pub fn formatInterface() FormatInterface {
        return FormatInterface{
            .format = format,
            .formatDetect = formatDetect,
            .readImage = readImage,
            .writeImage = writeImage,
        };
    }

    fn format() Image.Format {
        return Image.Format.jpg;
    }

    fn formatDetect(stream: *Image.Stream) ImageReadError!bool {
        var buffered_stream = buffered_stream_source.bufferedStreamSourceReader(stream);

        const reader = buffered_stream.reader();
        const maybe_start_of_image = try reader.readInt(u16, .big);
        if (maybe_start_of_image != @intFromEnum(Markers.start_of_image)) {
            return false;
        }

        try buffered_stream.seekTo(6);
        var identifier_buffer: [4]u8 = undefined;
        _ = try buffered_stream.read(identifier_buffer[0..]);

        return std.mem.eql(u8, identifier_buffer[0..], "JFIF");
    }

    fn readImage(allocator: Allocator, stream: *Image.Stream) ImageReadError!Image {
        var result = Image.init(allocator);
        errdefer result.deinit();
        var jpeg = JPEG.init(allocator);
        defer jpeg.deinit();

        var pixels_opt: ?color.PixelStorage = null;

        const frame = try jpeg.read(stream, &pixels_opt);

        result.width = frame.frame_header.samples_per_row;
        result.height = frame.frame_header.row_count;

        if (pixels_opt) |pixels| {
            result.pixels = pixels;
        } else {
            return ImageReadError.InvalidData;
        }

        return result;
    }

    fn writeImage(allocator: Allocator, write_stream: *Image.Stream, image: Image, encoder_options: Image.EncoderOptions) ImageWriteError!void {
        _ = allocator;
        _ = write_stream;
        _ = image;
        _ = encoder_options;
    }
};
