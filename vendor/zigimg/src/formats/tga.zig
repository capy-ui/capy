const FormatInterface = @import("../FormatInterface.zig");
const PixelFormat = @import("../pixel_format.zig").PixelFormat;
const buffered_stream_source = @import("../buffered_stream_source.zig");
const color = @import("../color.zig");
const Image = @import("../Image.zig");
const std = @import("std");
const simd = @import("../simd.zig");
const utils = @import("../utils.zig");

pub const TGAImageType = packed struct(u8) {
    indexed: bool = false,
    truecolor: bool = false,
    pad0: bool = false,
    run_length: bool = false,
    pad1: u4 = 0,
};

pub const TGAColorMapSpec = extern struct {
    first_entry_index: u16 align(1) = 0,
    length: u16 align(1) = 0,
    bit_depth: u8 align(1) = 0,
};

pub const TGADescriptor = packed struct(u8) {
    num_attributes_bit: u4 = 0,
    right_to_left: bool = false,
    top_to_bottom: bool = false,
    pad: u2 = 0,
};

pub const TGAImageSpec = extern struct {
    origin_x: u16 align(1) = 0,
    origin_y: u16 align(1) = 0,
    width: u16 align(1) = 0,
    height: u16 align(1) = 0,
    bit_per_pixel: u8 align(1) = 0,
    descriptor: TGADescriptor align(1) = .{},
};

pub const TGAHeader = extern struct {
    id_length: u8 align(1) = 0,
    has_color_map: u8 align(1) = 0,
    image_type: TGAImageType align(1) = .{},
    color_map_spec: TGAColorMapSpec align(1) = .{},
    image_spec: TGAImageSpec align(1) = .{},

    pub fn isValid(self: TGAHeader) bool {
        if (self.has_color_map != 0 and self.has_color_map != 1) {
            return false;
        }

        if (self.image_type.pad0) {
            return false;
        }

        if (self.image_type.pad1 != 0) {
            return false;
        }

        switch (self.color_map_spec.bit_depth) {
            0, 15, 16, 24, 32 => {},
            else => {
                return false;
            },
        }

        return true;
    }
};

pub const TGAExtensionComment = extern struct {
    lines: [4][80:0]u8 = [_][80:0]u8{[_:0]u8{0} ** 80} ** 4,
};

pub const TGAExtensionSoftwareVersion = extern struct {
    number: u16 align(1) = 0,
    letter: u8 align(1) = ' ',
};

pub const TGAExtensionTimestamp = extern struct {
    month: u16 align(1) = 0,
    day: u16 align(1) = 0,
    year: u16 align(1) = 0,
    hour: u16 align(1) = 0,
    minute: u16 align(1) = 0,
    second: u16 align(1) = 0,
};

pub const TGAExtensionJobTime = extern struct {
    hours: u16 align(1) = 0,
    minutes: u16 align(1) = 0,
    seconds: u16 align(1) = 0,
};

pub const TGAExtensionRatio = extern struct {
    numerator: u16 align(1) = 0,
    denominator: u16 align(1) = 0,
};

pub const TGAAttributeType = enum(u8) {
    no_alpha = 0,
    undefined_alpha_ignore = 1,
    undefined_alpha_retained = 2,
    useful_alpha_channel = 3,
    premultipled_alpha = 4,
};

pub const TGAExtension = extern struct {
    extension_size: u16 align(1) = @sizeOf(TGAExtension),
    author_name: [40:0]u8 align(1) = [_:0]u8{0} ** 40,
    author_comment: TGAExtensionComment align(1) = .{},
    timestamp: TGAExtensionTimestamp align(1) = .{},
    job_id: [40:0]u8 align(1) = [_:0]u8{0} ** 40,
    job_time: TGAExtensionJobTime align(1) = .{},
    software_id: [40:0]u8 align(1) = [_:0]u8{0} ** 40,
    software_version: TGAExtensionSoftwareVersion align(1) = .{},
    key_color: color.Bgra32 align(1) = .{ .r = 0, .g = 0, .b = 0, .a = 0 },
    pixel_aspect: TGAExtensionRatio align(1) = .{},
    gamma_value: TGAExtensionRatio align(1) = .{},
    color_correction_offset: u32 align(1) = 0,
    postage_stamp_offset: u32 align(1) = 0,
    scanline_offset: u32 align(1) = 0,
    attributes: TGAAttributeType align(1) = .no_alpha,
};

pub const TGAFooter = extern struct {
    extension_offset: u32 align(1) = 0,
    dev_area_offset: u32 align(1) = 0,
    signature: [16]u8 align(1) = undefined,
    dot: u8 align(1) = '.',
    null_value: u8 align(1) = 0,
};

pub const TGASignature = "TRUEVISION-XFILE";

comptime {
    std.debug.assert(@sizeOf(TGAHeader) == 18);
    std.debug.assert(@sizeOf(TGAExtension) == 495);
}

const RLEPacketType = enum(u1) {
    raw = 0,
    repeated = 1,
};

const RLEPacketHeader = packed struct {
    count: u7,
    packet_type: RLEPacketType,
};

const TargaRLEDecoder = struct {
    source_reader: buffered_stream_source.DefaultBufferedStreamSourceReader.Reader,
    allocator: std.mem.Allocator,
    bytes_per_pixel: usize,

    state: State = .read_header,
    repeat_count: usize = 0,
    repeat_data: []u8 = undefined,
    data_stream: std.io.FixedBufferStream([]u8) = undefined,

    pub const Reader = std.io.Reader(*TargaRLEDecoder, Image.ReadError, read);

    const State = enum {
        read_header,
        repeated,
        raw,
    };

    pub fn init(allocator: std.mem.Allocator, source_reader: buffered_stream_source.DefaultBufferedStreamSourceReader.Reader, bytes_per_pixels: usize) !TargaRLEDecoder {
        var result = TargaRLEDecoder{
            .allocator = allocator,
            .source_reader = source_reader,
            .bytes_per_pixel = bytes_per_pixels,
        };

        result.repeat_data = try allocator.alloc(u8, bytes_per_pixels);
        result.data_stream = std.io.fixedBufferStream(result.repeat_data);
        return result;
    }

    pub fn deinit(self: TargaRLEDecoder) void {
        self.allocator.free(self.repeat_data);
    }

    pub fn read(self: *TargaRLEDecoder, dest: []u8) Image.ReadError!usize {
        var read_count: usize = 0;

        if (self.state == .read_header) {
            const packet_header = try utils.readStruct(self.source_reader, RLEPacketHeader, .little);

            if (packet_header.packet_type == .repeated) {
                self.state = .repeated;

                self.repeat_count = @as(usize, @intCast(packet_header.count)) + 1;

                _ = try self.source_reader.read(self.repeat_data);

                self.data_stream.reset();
            } else if (packet_header.packet_type == .raw) {
                self.state = .raw;

                self.repeat_count = (@as(usize, @intCast(packet_header.count)) + 1) * self.bytes_per_pixel;
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
                return Image.ReadError.InvalidData;
            },
        }

        if (self.repeat_count == 0) {
            self.state = .read_header;
        }

        return read_count;
    }

    pub fn reader(self: *TargaRLEDecoder) Reader {
        return .{ .context = self };
    }
};

pub const TargaStream = union(enum) {
    image: buffered_stream_source.DefaultBufferedStreamSourceReader.Reader,
    rle: TargaRLEDecoder,

    pub const Reader = std.io.Reader(*TargaStream, Image.ReadError, read);

    pub fn read(self: *TargaStream, dest: []u8) Image.ReadError!usize {
        switch (self.*) {
            .image => |*x| return x.read(dest),
            .rle => |*x| return x.read(dest),
        }
    }

    pub fn reader(self: *TargaStream) Reader {
        return .{ .context = self };
    }
};

const RLEPacketMask = 1 << 7;
const RLEMinLength = 2;
const RLEMaxLength = RLEPacketMask;

const RunLengthEncoderCommon = struct {
    pub fn flush(comptime IntType: type, writer: anytype, value: IntType, count: usize) !void {
        var current_count = count;
        while (current_count > 0) {
            const length_to_write = @min(current_count, RLEMaxLength);

            if (length_to_write >= RLEMinLength) {
                try flushRLE(IntType, writer, value, length_to_write);
            } else {
                try flushRaw(IntType, writer, value, length_to_write);
            }

            current_count -= length_to_write;
        }
    }

    pub inline fn flushRLE(comptime IntType: type, writer: anytype, value: IntType, count: usize) !void {
        const rle_packet_header = RLEPacketHeader{
            .count = @truncate(count - 1),
            .packet_type = .repeated,
        };
        try writer.writeByte(@bitCast(rle_packet_header));
        try writer.writeInt(IntType, value, .little);
    }

    pub inline fn flushRaw(comptime IntType: type, writer: anytype, value: IntType, count: usize) !void {
        const rle_packet_header = RLEPacketHeader{
            .count = @truncate(count - 1),
            .packet_type = .raw,
        };
        try writer.writeByte(@bitCast(rle_packet_header));

        for (0..count) |_| {
            try writer.writeInt(IntType, value, .little);
        }
    }
};

fn RunLengthSimpleEncoder(comptime IntType: type) type {
    return struct {
        pub fn encode(source_data: []const u8, writer: anytype) !void {
            if (source_data.len == 0) {
                return;
            }

            var fixed_stream = std.io.fixedBufferStream(source_data);
            const reader = fixed_stream.reader();

            var total_similar_count: usize = 0;
            var compared_value = try reader.readInt(IntType, .little);
            total_similar_count = 1;

            while ((try fixed_stream.getPos()) < (try fixed_stream.getEndPos())) {
                const read_value = try reader.readInt(IntType, .little);
                if (read_value == compared_value) {
                    total_similar_count += 1;
                } else {
                    try RunLengthEncoderCommon.flush(IntType, writer, compared_value, total_similar_count);

                    compared_value = read_value;
                    total_similar_count = 1;
                }
            }

            try RunLengthEncoderCommon.flush(IntType, writer, compared_value, total_similar_count);
        }
    };
}

fn RunLengthSIMDEncoder(comptime IntType: type) type {
    return struct {
        const VectorLength = std.simd.suggestVectorSize(IntType) orelse 4;
        const VectorType = @Vector(VectorLength, IntType);
        const BytesPerPixels = (@typeInfo(IntType).Int.bits + 7) / 8;
        const IndexStep = VectorLength * BytesPerPixels;
        const MaskType = std.meta.Int(.unsigned, VectorLength);

        comptime {
            if (!std.math.isPowerOfTwo(@typeInfo(IntType).Int.bits)) {
                @compileError("Only power of two integers are supported by the run-length SIMD encoder");
            }
        }

        pub fn encode(source_data: []const u8, writer: anytype) !void {
            if (source_data.len == 0) {
                return;
            }

            var index: usize = 0;

            var total_similar_count: usize = 0;

            var fixed_stream = std.io.fixedBufferStream(source_data);
            const reader = fixed_stream.reader();

            var compared_value = try reader.readInt(IntType, .little);
            try fixed_stream.seekTo(0);

            while (index < source_data.len and ((index + IndexStep) <= source_data.len)) {
                const read_value = try reader.readInt(IntType, .little);

                const current_byte_splatted: VectorType = @splat(read_value);
                const compare_chunk = simd.load(source_data[index..], VectorType, 0);

                const compare_mask = (current_byte_splatted == compare_chunk);
                const inverted_mask = ~@as(MaskType, @bitCast(compare_mask));
                const current_similar_count = @ctz(inverted_mask);

                if (current_similar_count == VectorLength) {
                    total_similar_count += current_similar_count;
                    index += current_similar_count * BytesPerPixels;

                    try reader.skipBytes((current_similar_count - 1) * BytesPerPixels, .{});

                    compared_value = read_value;
                } else {
                    if (compared_value == read_value) {
                        total_similar_count += current_similar_count;
                        try RunLengthEncoderCommon.flush(IntType, writer, compared_value, total_similar_count);

                        compared_value = read_value;
                        total_similar_count = 0;
                    } else {
                        try RunLengthEncoderCommon.flush(IntType, writer, compared_value, total_similar_count);

                        compared_value = read_value;
                        total_similar_count = current_similar_count;
                    }

                    index += current_similar_count * BytesPerPixels;

                    try reader.skipBytes((current_similar_count - 1) * BytesPerPixels, .{});
                }
            }

            try RunLengthEncoderCommon.flush(IntType, writer, compared_value, total_similar_count);

            // Process the rest sequentially
            if (index < source_data.len) {
                try RunLengthSimpleEncoder(IntType).encode(source_data[index..], writer);
            }
        }
    };
}

fn RLEStreamEncoder(comptime ColorType: type) type {
    return struct {
        rle_value: ?ColorType = null,
        length: usize = 0,

        const IntType = switch (ColorType) {
            color.Bgr24 => u24,
            color.Bgra32 => u32,
            else => @compileError("Not supported color format"),
        };

        pub fn encode(self: *@This(), writer: anytype, value: ColorType) !void {
            if (self.rle_value == null) {
                self.rle_value = value;
                self.length = 1;
                return;
            }

            if (self.rle_value) |rle_value| {
                if (std.mem.eql(u8, std.mem.asBytes(&rle_value), std.mem.asBytes(&value))) {
                    self.length += 1;
                } else {
                    try RunLengthEncoderCommon.flush(IntType, writer, @as(IntType, @bitCast(rle_value)), self.length);

                    self.length = 1;
                    self.rle_value = value;
                }
            }
        }

        pub fn flush(self: *@This(), writer: anytype) !void {
            if (self.length == 0) {
                return;
            }

            if (self.rle_value) |rle_value| {
                try RunLengthEncoderCommon.flush(IntType, writer, @as(IntType, @bitCast(rle_value)), self.length);
            }
        }
    };
}

test "TGA RLE SIMD u8 (bytes) encoder" {
    const uncompressed_data = [_]u8{ 1, 1, 1, 1, 1, 1, 1, 1, 1, 64, 64, 2, 2, 2, 2, 2, 215, 215, 215, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 200, 200, 200, 200, 210, 210 };
    const compressed_data = [_]u8{ 0x88, 0x01, 0x81, 0x40, 0x84, 0x02, 0x82, 0xD7, 0x89, 0x03, 0x83, 0xC8, 0x81, 0xD2 };

    var result_list = std.ArrayList(u8).init(std.testing.allocator);
    defer result_list.deinit();

    const writer = result_list.writer();

    try RunLengthSIMDEncoder(u8).encode(uncompressed_data[0..], writer);

    try std.testing.expectEqualSlices(u8, compressed_data[0..], result_list.items);
}

test "TGA RLE SIMD u8 (bytes) encoder should encore more than 128 bytes similar" {
    const first_uncompressed_part = [_]u8{0x45} ** 135;
    const second_uncompresse_part = [_]u8{ 0x1, 0x1, 0x1, 0x1 };
    const uncompressed_data = first_uncompressed_part ++ second_uncompresse_part;

    const compressed_data = [_]u8{ 0xFF, 0x45, 0x86, 0x45, 0x83, 0x1 };

    var result_list = std.ArrayList(u8).init(std.testing.allocator);
    defer result_list.deinit();

    const writer = result_list.writer();

    try RunLengthSIMDEncoder(u8).encode(uncompressed_data[0..], writer);

    try std.testing.expectEqualSlices(u8, compressed_data[0..], result_list.items);
}

test "TGA RLE SIMD u16 encoder" {
    const uncompressed_source = [_]u16{ 0x301, 0x301, 0x301, 0x301, 0x301, 0x301, 0x301, 0x301, 0x1, 0x2, 0x3, 0x4, 0x5, 0x6, 0x7, 0x8 };
    const uncompressed_data = std.mem.sliceAsBytes(uncompressed_source[0..]);

    const compressed_data = [_]u8{ 0x87, 0x01, 0x03, 0x00, 0x01, 0x00, 0x00, 0x02, 0x00, 0x00, 0x03, 0x00, 0x00, 0x04, 0x00, 0x00, 0x05, 0x00, 0x00, 0x06, 0x00, 0x00, 0x07, 0x00, 0x00, 0x08, 0x00 };

    var result_list = std.ArrayList(u8).init(std.testing.allocator);
    defer result_list.deinit();

    const writer = result_list.writer();

    try RunLengthSIMDEncoder(u16).encode(uncompressed_data[0..], writer);

    try std.testing.expectEqualSlices(u8, compressed_data[0..], result_list.items);
}

test "TGA RLE SIMD u32 encoder" {
    const uncompressed_source = [_]u32{ 0xFFABCDEF, 0xFFABCDEF, 0xFFABCDEF, 0xFFABCDEF, 0xFFABCDEF, 0xFFABCDEF, 0xFFABCDEF, 0xFFABCDEF, 0x1, 0x2, 0x3, 0x4, 0x5, 0x6, 0x7, 0x8 };
    const uncompressed_data = std.mem.sliceAsBytes(uncompressed_source[0..]);

    const compressed_data = [_]u8{ 0x87, 0xEF, 0xCD, 0xAB, 0xFF, 0x00, 0x01, 0x00, 0x00, 0x00, 0x00, 0x02, 0x00, 0x00, 0x00, 0x00, 0x03, 0x00, 0x00, 0x00, 0x00, 0x04, 0x00, 0x00, 0x00, 0x00, 0x05, 0x00, 0x00, 0x00, 0x00, 0x06, 0x00, 0x00, 0x00, 0x00, 0x07, 0x00, 0x00, 0x00, 0x00, 0x08, 0x00, 0x00, 0x00 };

    var result_list = std.ArrayList(u8).init(std.testing.allocator);
    defer result_list.deinit();

    const writer = result_list.writer();

    try RunLengthSIMDEncoder(u32).encode(uncompressed_data[0..], writer);

    try std.testing.expectEqualSlices(u8, compressed_data[0..], result_list.items);
}

test "TGA RLE simple u24 encoder" {
    const uncompressed_source = [_]color.Rgb24{
        .{ .r = 0xEF, .g = 0xCD, .b = 0xAB },
        .{ .r = 0xEF, .g = 0xCD, .b = 0xAB },
        .{ .r = 0xEF, .g = 0xCD, .b = 0xAB },
        .{ .r = 0xEF, .g = 0xCD, .b = 0xAB },
        .{ .r = 0xEF, .g = 0xCD, .b = 0xAB },
        .{ .r = 0xEF, .g = 0xCD, .b = 0xAB },
        .{ .r = 0xEF, .g = 0xCD, .b = 0xAB },
        .{ .r = 0xEF, .g = 0xCD, .b = 0xAB },
        .{ .r = 0x1, .g = 0x2, .b = 0x3 },
        .{ .r = 0x4, .g = 0x5, .b = 0x6 },
        .{ .r = 0x7, .g = 0x8, .b = 0x9 },
    };
    const uncompressed_data = std.mem.sliceAsBytes(uncompressed_source[0..]);

    const compressed_data = [_]u8{
        0x87, 0xEF, 0xCD, 0xAB,
        0x00, 0x01, 0x02, 0x03,
        0x00, 0x04, 0x05, 0x06,
        0x00, 0x07, 0x08, 0x09,
    };

    var result_list = std.ArrayList(u8).init(std.testing.allocator);
    defer result_list.deinit();

    const writer = result_list.writer();

    try RunLengthSimpleEncoder(u24).encode(uncompressed_data[0..], writer);

    try std.testing.expectEqualSlices(u8, compressed_data[0..], result_list.items);
}

pub const TGA = struct {
    header: TGAHeader = .{},
    id: utils.FixedStorage(u8, 256) = .{},
    extension: ?TGAExtension = null,

    pub const EncoderOptions = struct {
        rle_compressed: bool = true,
        top_to_bottom_image: bool = true,
        color_map_depth: u8 = 24,
        image_id: []const u8 = &.{},
        author_name: [:0]const u8 = &.{},
        author_comment: TGAExtensionComment = .{},
        timestamp: TGAExtensionTimestamp = .{},
        job_id: [:0]const u8 = &.{},
        job_time: TGAExtensionJobTime = .{},
        software_id: [:0]const u8 = &.{},
        software_version: TGAExtensionSoftwareVersion = .{},
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
        return Image.Format.tga;
    }

    pub fn formatDetect(stream: *Image.Stream) Image.ReadError!bool {
        var buffered_stream = buffered_stream_source.bufferedStreamSourceReader(stream);

        const end_pos = try buffered_stream.getEndPos();

        const is_valid_tga_v2: bool = blk: {
            if (@sizeOf(TGAFooter) < end_pos) {
                const footer_position = end_pos - @sizeOf(TGAFooter);

                try buffered_stream.seekTo(footer_position);
                const footer = try utils.readStruct(buffered_stream.reader(), TGAFooter, .little);

                if (footer.dot != '.') {
                    break :blk false;
                }

                if (footer.null_value != 0) {
                    break :blk false;
                }

                if (std.mem.eql(u8, footer.signature[0..], TGASignature[0..])) {
                    break :blk true;
                }
            }

            break :blk false;
        };

        // Not a TGA 2.0 file, try to detect an TGA 1.0 image
        const is_valid_tga_v1: bool = blk: {
            if (!is_valid_tga_v2 and @sizeOf(TGAHeader) < end_pos) {
                try buffered_stream.seekTo(0);

                const header = try utils.readStruct(buffered_stream.reader(), TGAHeader, .little);
                break :blk header.isValid();
            }

            break :blk false;
        };

        return is_valid_tga_v2 or is_valid_tga_v1;
    }

    pub fn readImage(allocator: std.mem.Allocator, stream: *Image.Stream) Image.ReadError!Image {
        var result = Image.init(allocator);
        errdefer result.deinit();
        var tga = TGA{};

        const pixels = try tga.read(allocator, stream);

        result.width = tga.width();
        result.height = tga.height();
        result.pixels = pixels;

        return result;
    }

    pub fn writeImage(allocator: std.mem.Allocator, write_stream: *Image.Stream, image: Image, encoder_options: Image.EncoderOptions) Image.WriteError!void {
        _ = allocator;

        const tga_encoder_options = encoder_options.tga;

        const image_width = image.width;
        const image_height = image.height;

        if (image_width > std.math.maxInt(u16)) {
            return Image.WriteError.Unsupported;
        }

        if (image_height > std.math.maxInt(u16)) {
            return Image.WriteError.Unsupported;
        }

        if (!(tga_encoder_options.color_map_depth == 16 or tga_encoder_options.color_map_depth == 24)) {
            return Image.WriteError.Unsupported;
        }

        var tga = TGA{};
        tga.header.image_spec.width = @truncate(image_width);
        tga.header.image_spec.height = @truncate(image_height);
        tga.extension = TGAExtension{};

        if (tga_encoder_options.rle_compressed) {
            tga.header.image_type.run_length = true;
        }
        if (tga_encoder_options.top_to_bottom_image) {
            tga.header.image_spec.descriptor.top_to_bottom = true;
        }

        if (tga_encoder_options.image_id.len > 0) {
            if (tga_encoder_options.image_id.len > tga.id.storage.len) {
                return Image.WriteError.Unsupported;
            }

            tga.header.id_length = @truncate(tga_encoder_options.image_id.len);
            tga.id.resize(tga_encoder_options.image_id.len);

            @memcpy(tga.id.data[0..], tga_encoder_options.image_id[0..]);
        }

        if (tga.extension) |*extension| {
            if (tga_encoder_options.author_name.len >= extension.author_name.len) {
                return Image.WriteError.Unsupported;
            }
            if (tga_encoder_options.job_id.len >= extension.job_id.len) {
                return Image.WriteError.Unsupported;
            }
            if (tga_encoder_options.software_id.len >= extension.software_id.len) {
                return Image.WriteError.Unsupported;
            }

            std.mem.copyForwards(u8, extension.author_name[0..], tga_encoder_options.author_name[0..]);
            extension.author_comment = tga_encoder_options.author_comment;

            extension.timestamp = tga_encoder_options.timestamp;

            std.mem.copyForwards(u8, extension.job_id[0..], tga_encoder_options.job_id[0..]);
            extension.job_time = tga_encoder_options.job_time;

            std.mem.copyForwards(u8, extension.software_id[0..], tga_encoder_options.software_id[0..]);
            extension.software_version = tga_encoder_options.software_version;
        }

        switch (image.pixels) {
            .grayscale8 => {
                tga.header.image_type.indexed = true;
                tga.header.image_type.truecolor = true;

                tga.header.image_spec.bit_per_pixel = 8;
            },
            .indexed8 => |indexed| {
                tga.header.image_type.indexed = true;

                tga.header.image_spec.bit_per_pixel = 8;

                tga.header.color_map_spec.bit_depth = tga_encoder_options.color_map_depth;
                tga.header.color_map_spec.first_entry_index = 0;
                tga.header.color_map_spec.length = @truncate(indexed.palette.len);

                tga.header.has_color_map = 1;
            },
            .rgb555 => {
                tga.header.image_type.indexed = false;
                tga.header.image_type.truecolor = true;
                tga.header.image_spec.bit_per_pixel = 16;
            },
            .rgb24, .bgr24 => {
                tga.header.image_type.indexed = false;
                tga.header.image_type.truecolor = true;

                tga.header.image_spec.bit_per_pixel = 24;
            },
            .rgba32, .bgra32 => {
                tga.header.image_type.indexed = false;
                tga.header.image_type.truecolor = true;

                tga.header.image_spec.bit_per_pixel = 32;

                tga.header.image_spec.descriptor.num_attributes_bit = 8;

                tga.extension.?.attributes = .useful_alpha_channel;
            },
            else => {
                return Image.WriteError.Unsupported;
            },
        }

        try tga.write(write_stream, image.pixels);
    }

    pub fn width(self: TGA) usize {
        return self.header.image_spec.width;
    }

    pub fn height(self: TGA) usize {
        return self.header.image_spec.height;
    }

    pub fn pixelFormat(self: TGA) Image.ReadError!PixelFormat {
        if (self.header.image_type.indexed) {
            if (self.header.image_type.truecolor) {
                return PixelFormat.grayscale8;
            }

            return PixelFormat.indexed8;
        } else if (self.header.image_type.truecolor) {
            switch (self.header.image_spec.bit_per_pixel) {
                16 => return PixelFormat.rgb555,
                24 => return PixelFormat.bgr24,
                32 => return PixelFormat.bgra32,
                else => {},
            }
        }

        return Image.Error.Unsupported;
    }

    pub fn read(self: *TGA, allocator: std.mem.Allocator, stream: *Image.Stream) !color.PixelStorage {
        var buffered_stream = buffered_stream_source.bufferedStreamSourceReader(stream);

        // Read footage
        const end_pos = try buffered_stream.getEndPos();

        if (@sizeOf(TGAFooter) > end_pos) {
            return Image.ReadError.InvalidData;
        }

        const reader = buffered_stream.reader();
        try buffered_stream.seekTo(end_pos - @sizeOf(TGAFooter));
        const footer = try utils.readStruct(reader, TGAFooter, .little);

        var is_tga_version2 = true;

        if (!std.mem.eql(u8, footer.signature[0..], TGASignature[0..])) {
            is_tga_version2 = false;
        }

        // Read extension
        if (is_tga_version2 and footer.extension_offset > 0) {
            const extension_pos: u64 = @intCast(footer.extension_offset);
            try buffered_stream.seekTo(extension_pos);
            self.extension = try utils.readStruct(reader, TGAExtension, .little);
        }

        // Read header
        try buffered_stream.seekTo(0);
        self.header = try utils.readStruct(reader, TGAHeader, .little);

        if (!self.header.isValid()) {
            return Image.ReadError.InvalidData;
        }

        // Read ID
        if (self.header.id_length > 0) {
            self.id.resize(self.header.id_length);

            const read_id_size = try buffered_stream.read(self.id.data[0..]);

            if (read_id_size != self.header.id_length) {
                return Image.ReadError.InvalidData;
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
            const bytes_per_pixel = (self.header.image_spec.bit_per_pixel + 7) / 8;

            rle_decoder = try TargaRLEDecoder.init(allocator, reader, bytes_per_pixel);
            if (rle_decoder) |rle| {
                targa_stream = TargaStream{ .rle = rle };
            }
        }

        const top_to_bottom_image = self.header.image_spec.descriptor.top_to_bottom;

        switch (pixel_format) {
            .grayscale8 => {
                if (top_to_bottom_image) {
                    try self.readGrayscale8TopToBottom(pixels.grayscale8, targa_stream.reader());
                } else {
                    try self.readGrayscale8BottomToTop(pixels.grayscale8, targa_stream.reader());
                }
            },
            .indexed8 => {
                // Read color map, it is not compressed by RLE so always use the original reader
                switch (self.header.color_map_spec.bit_depth) {
                    15, 16 => {
                        try self.readColorMap16(pixels.indexed8, reader);
                    },
                    24 => {
                        try self.readColorMap24(pixels.indexed8, reader);
                    },
                    else => {
                        return Image.Error.Unsupported;
                    },
                }

                // Read indices
                if (top_to_bottom_image) {
                    try self.readIndexed8TopToBottom(pixels.indexed8, targa_stream.reader());
                } else {
                    try self.readIndexed8BottomToTop(pixels.indexed8, targa_stream.reader());
                }
            },
            .rgb555 => {
                if (top_to_bottom_image) {
                    try self.readTruecolor16TopToBottom(pixels.rgb555, targa_stream.reader());
                } else {
                    try self.readTruecolor16BottomToTop(pixels.rgb555, targa_stream.reader());
                }
            },
            .bgr24 => {
                if (top_to_bottom_image) {
                    try self.readTruecolor24TopToBottom(pixels.bgr24, targa_stream.reader());
                } else {
                    try self.readTruecolor24BottomTopTop(pixels.bgr24, targa_stream.reader());
                }
            },
            .bgra32 => {
                if (top_to_bottom_image) {
                    try self.readTruecolor32TopToBottom(pixels.bgra32, targa_stream.reader());
                } else {
                    try self.readTruecolor32BottomToTop(pixels.bgra32, targa_stream.reader());
                }
            },
            else => {
                return Image.Error.Unsupported;
            },
        }

        return pixels;
    }

    fn readGrayscale8TopToBottom(self: *TGA, data: []color.Grayscale8, stream: TargaStream.Reader) Image.ReadError!void {
        var data_index: usize = 0;
        const data_end: usize = self.width() * self.height();

        while (data_index < data_end) : (data_index += 1) {
            data[data_index] = color.Grayscale8{ .value = try stream.readByte() };
        }
    }

    fn readGrayscale8BottomToTop(self: *TGA, data: []color.Grayscale8, stream: TargaStream.Reader) Image.ReadError!void {
        for (0..self.height()) |y| {
            const inverted_y = self.height() - y - 1;

            const stride = inverted_y * self.width();

            for (0..self.width()) |x| {
                const data_index = stride + x;
                data[data_index] = color.Grayscale8{ .value = try stream.readByte() };
            }
        }
    }

    fn readIndexed8TopToBottom(self: *TGA, data: color.IndexedStorage8, stream: TargaStream.Reader) Image.ReadError!void {
        var data_index: usize = 0;
        const data_end: usize = self.width() * self.height();

        while (data_index < data_end) : (data_index += 1) {
            data.indices[data_index] = try stream.readByte();
        }
    }

    fn readIndexed8BottomToTop(self: *TGA, data: color.IndexedStorage8, stream: TargaStream.Reader) Image.ReadError!void {
        for (0..self.height()) |y| {
            const inverted_y = self.height() - y - 1;

            const stride = inverted_y * self.width();

            for (0..self.width()) |x| {
                const data_index = stride + x;
                data.indices[data_index] = try stream.readByte();
            }
        }
    }

    fn readColorMap16(self: *TGA, data: color.IndexedStorage8, reader: buffered_stream_source.DefaultBufferedStreamSourceReader.Reader) Image.ReadError!void {
        var data_index: usize = self.header.color_map_spec.first_entry_index;
        const data_end: usize = self.header.color_map_spec.first_entry_index + self.header.color_map_spec.length;

        while (data_index < data_end) : (data_index += 1) {
            const read_color = try utils.readStruct(reader, color.Rgb555, .little);

            data.palette[data_index].r = color.scaleToIntColor(u8, read_color.r);
            data.palette[data_index].g = color.scaleToIntColor(u8, read_color.g);
            data.palette[data_index].b = color.scaleToIntColor(u8, read_color.b);
            data.palette[data_index].a = 255;
        }
    }

    fn readColorMap24(self: *TGA, data: color.IndexedStorage8, stream: buffered_stream_source.DefaultBufferedStreamSourceReader.Reader) Image.ReadError!void {
        var data_index: usize = self.header.color_map_spec.first_entry_index;
        const data_end: usize = self.header.color_map_spec.first_entry_index + self.header.color_map_spec.length;

        while (data_index < data_end) : (data_index += 1) {
            data.palette[data_index].b = try stream.readByte();
            data.palette[data_index].g = try stream.readByte();
            data.palette[data_index].r = try stream.readByte();
            data.palette[data_index].a = 255;
        }
    }

    fn readTruecolor16TopToBottom(self: *TGA, data: []color.Rgb555, stream: TargaStream.Reader) Image.ReadError!void {
        var data_index: usize = 0;
        const data_end: usize = self.width() * self.height();

        while (data_index < data_end) : (data_index += 1) {
            const raw_color = try stream.readInt(u16, .little);

            data[data_index].r = @truncate(raw_color >> 10);
            data[data_index].g = @truncate(raw_color >> 5);
            data[data_index].b = @truncate(raw_color);
        }
    }

    fn readTruecolor16BottomToTop(self: *TGA, data: []color.Rgb555, stream: TargaStream.Reader) Image.ReadError!void {
        for (0..self.height()) |y| {
            const inverted_y = self.height() - y - 1;

            const stride = inverted_y * self.width();

            for (0..self.width()) |x| {
                const data_index = stride + x;

                const raw_color = try stream.readInt(u16, .little);

                data[data_index].r = @truncate(raw_color >> (5 * 2));
                data[data_index].g = @truncate(raw_color >> 5);
                data[data_index].b = @truncate(raw_color);
            }
        }
    }

    fn readTruecolor24TopToBottom(self: *TGA, data: []color.Bgr24, stream: TargaStream.Reader) Image.ReadError!void {
        var data_index: usize = 0;
        const data_end: usize = self.width() * self.height();

        while (data_index < data_end) : (data_index += 1) {
            data[data_index].b = try stream.readByte();
            data[data_index].g = try stream.readByte();
            data[data_index].r = try stream.readByte();
        }
    }

    fn readTruecolor24BottomTopTop(self: *TGA, data: []color.Bgr24, stream: TargaStream.Reader) Image.ReadError!void {
        for (0..self.height()) |y| {
            const inverted_y = self.height() - y - 1;

            const stride = inverted_y * self.width();

            for (0..self.width()) |x| {
                const data_index = stride + x;
                data[data_index].b = try stream.readByte();
                data[data_index].g = try stream.readByte();
                data[data_index].r = try stream.readByte();
            }
        }
    }

    fn readTruecolor32TopToBottom(self: *TGA, data: []color.Bgra32, stream: TargaStream.Reader) Image.ReadError!void {
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

    fn readTruecolor32BottomToTop(self: *TGA, data: []color.Bgra32, stream: TargaStream.Reader) Image.ReadError!void {
        for (0..self.height()) |y| {
            const inverted_y = self.height() - y - 1;

            const stride = inverted_y * self.width();

            for (0..self.width()) |x| {
                const data_index = stride + x;

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
    }

    pub fn write(self: TGA, stream: *Image.Stream, pixels: color.PixelStorage) Image.WriteError!void {
        var buffered_stream = buffered_stream_source.bufferedStreamSourceWriter(stream);
        const writer = buffered_stream.writer();

        try utils.writeStruct(writer, self.header, .little);

        if (self.header.id_length > 0) {
            if (self.id.data.len != self.header.id_length) {
                return Image.WriteError.Unsupported;
            }

            _ = try writer.write(self.id.data);
        }

        switch (pixels) {
            .indexed8 => {
                try self.writeIndexed8(writer, pixels);
            },
            .grayscale8,
            .rgb555,
            .bgr24,
            .bgra32,
            => {
                try self.writePixels(writer, pixels);
            },
            .rgb24 => {
                try self.writeRgb24(writer, pixels);
            },
            .rgba32 => {
                try self.writeRgba32(writer, pixels);
            },
            else => {
                return Image.WriteError.Unsupported;
            },
        }

        var extension_offset: u32 = 0;
        if (self.extension) |extension| {
            extension_offset = @truncate(try buffered_stream.getPos());

            try utils.writeStruct(writer, extension, .little);
        }

        var footer = TGAFooter{};
        footer.extension_offset = extension_offset;
        std.mem.copyForwards(u8, footer.signature[0..], TGASignature[0..]);
        try utils.writeStruct(writer, footer, .little);

        try buffered_stream.flush();
    }

    fn writePixels(self: TGA, writer: buffered_stream_source.DefaultBufferedStreamSourceWriter.Writer, pixels: color.PixelStorage) Image.WriteError!void {
        const bytes = pixels.asConstBytes();

        const effective_height = self.height();
        const effective_width = self.width();
        const bytes_per_pixel = std.meta.activeTag(pixels).pixelStride();
        const pixel_stride = effective_width * bytes_per_pixel;

        if (self.header.image_type.run_length) {
            // The TGA spec recommend that the RLE compression should be done on scanline per scanline basis
            inline for (1..(4 + 1)) |bpp| {
                const IntType = std.meta.Int(.unsigned, bpp * 8);

                if (bytes_per_pixel == bpp) {
                    if (comptime std.math.isPowerOfTwo(bpp)) {
                        if (self.header.image_spec.descriptor.top_to_bottom) {
                            for (0..effective_height) |y| {
                                const current_scanline = y * pixel_stride;

                                try RunLengthSIMDEncoder(IntType).encode(bytes[current_scanline..(current_scanline + pixel_stride)], writer);
                            }
                        } else {
                            for (0..effective_height) |y| {
                                const flipped_y = effective_height - y - 1;
                                const current_scanline = flipped_y * pixel_stride;

                                try RunLengthSIMDEncoder(IntType).encode(bytes[current_scanline..(current_scanline + pixel_stride)], writer);
                            }
                        }
                    } else {
                        if (self.header.image_spec.descriptor.top_to_bottom) {
                            for (0..effective_height) |y| {
                                const current_scanline = y * pixel_stride;

                                try RunLengthSimpleEncoder(IntType).encode(bytes[current_scanline..(current_scanline + pixel_stride)], writer);
                            }
                        } else {
                            for (0..effective_height) |y| {
                                const flipped_y = effective_height - y - 1;
                                const current_scanline = flipped_y * pixel_stride;

                                try RunLengthSimpleEncoder(IntType).encode(bytes[current_scanline..(current_scanline + pixel_stride)], writer);
                            }
                        }
                    }
                }
            }
        } else {
            if (self.header.image_spec.descriptor.top_to_bottom) {
                _ = try writer.write(bytes);
            } else {
                for (0..effective_height) |y| {
                    const flipped_y = effective_height - y - 1;
                    const current_scanline = flipped_y * pixel_stride;

                    _ = try writer.write(bytes[current_scanline..(current_scanline + pixel_stride)]);
                }
            }
        }
    }

    fn writeRgb24(self: TGA, writer: buffered_stream_source.DefaultBufferedStreamSourceWriter.Writer, pixels: color.PixelStorage) Image.WriteError!void {
        const image_width = self.width();
        const image_height = self.height();

        if (self.header.image_type.run_length) {
            var rle_encoder = RLEStreamEncoder(color.Bgr24){};

            if (self.header.image_spec.descriptor.top_to_bottom) {
                for (0..image_height) |y| {
                    const stride = y * image_width;

                    for (0..image_width) |x| {
                        const current_color = pixels.rgb24[stride + x];

                        const bgr_color = color.Bgr24{ .r = current_color.r, .g = current_color.g, .b = current_color.b };

                        try rle_encoder.encode(writer, bgr_color);
                    }
                }
            } else {
                for (0..image_height) |y| {
                    const flipped_y = image_height - y - 1;
                    const stride = flipped_y * image_width;

                    for (0..image_width) |x| {
                        const current_color = pixels.rgb24[stride + x];

                        const bgr_color = color.Bgr24{ .r = current_color.r, .g = current_color.g, .b = current_color.b };

                        try rle_encoder.encode(writer, bgr_color);
                    }
                }
            }

            try rle_encoder.flush(writer);
        } else {
            if (self.header.image_spec.descriptor.top_to_bottom) {
                for (0..image_height) |y| {
                    const stride = y * image_width;

                    for (0..image_width) |x| {
                        const current_color = pixels.rgb24[stride + x];
                        try writer.writeByte(current_color.b);
                        try writer.writeByte(current_color.g);
                        try writer.writeByte(current_color.r);
                    }
                }
            } else {
                for (0..image_height) |y| {
                    const flipped_y = image_height - y - 1;
                    const stride = flipped_y * image_width;

                    for (0..image_width) |x| {
                        const current_color = pixels.rgb24[stride + x];
                        try writer.writeByte(current_color.b);
                        try writer.writeByte(current_color.g);
                        try writer.writeByte(current_color.r);
                    }
                }
            }
        }
    }

    fn writeRgba32(self: TGA, writer: buffered_stream_source.DefaultBufferedStreamSourceWriter.Writer, pixels: color.PixelStorage) Image.WriteError!void {
        const image_width = self.width();
        const image_height = self.height();

        if (self.header.image_type.run_length) {
            var rle_encoder = RLEStreamEncoder(color.Bgra32){};

            if (self.header.image_spec.descriptor.top_to_bottom) {
                for (0..image_height) |y| {
                    const stride = y * image_width;

                    for (0..image_width) |x| {
                        const current_color = pixels.rgba32[stride + x];

                        const bgra_color = color.Bgra32{ .r = current_color.r, .g = current_color.g, .b = current_color.b, .a = current_color.a };

                        try rle_encoder.encode(writer, bgra_color);
                    }
                }
            } else {
                for (0..image_height) |y| {
                    const flipped_y = image_height - y - 1;
                    const stride = flipped_y * image_width;

                    for (0..image_width) |x| {
                        const current_color = pixels.rgba32[stride + x];

                        const bgra_color = color.Bgra32{ .r = current_color.r, .g = current_color.g, .b = current_color.b, .a = current_color.a };

                        try rle_encoder.encode(writer, bgra_color);
                    }
                }
            }

            try rle_encoder.flush(writer);
        } else {
            if (self.header.image_spec.descriptor.top_to_bottom) {
                for (0..image_height) |y| {
                    const stride = y * image_width;

                    for (0..image_width) |x| {
                        const current_color = pixels.rgba32[stride + x];
                        try writer.writeByte(current_color.b);
                        try writer.writeByte(current_color.g);
                        try writer.writeByte(current_color.r);
                        try writer.writeByte(current_color.a);
                    }
                }
            } else {
                for (0..image_height) |y| {
                    const flipped_y = image_height - y - 1;
                    const stride = flipped_y * image_width;

                    for (0..image_width) |x| {
                        const current_color = pixels.rgba32[stride + x];
                        try writer.writeByte(current_color.b);
                        try writer.writeByte(current_color.g);
                        try writer.writeByte(current_color.r);
                        try writer.writeByte(current_color.a);
                    }
                }
            }
        }
    }

    fn writeIndexed8(self: TGA, writer: buffered_stream_source.DefaultBufferedStreamSourceWriter.Writer, pixels: color.PixelStorage) Image.WriteError!void {
        // First write color map, the color map needs to be written uncompressed
        switch (self.header.color_map_spec.bit_depth) {
            15, 16 => {
                try self.writeColorMap16(writer, pixels.indexed8);
            },
            24 => {
                try self.writeColorMap24(writer, pixels.indexed8);
            },
            else => {
                return Image.Error.Unsupported;
            },
        }

        // Then write the indice data, compressed or uncompressed
        try self.writePixels(writer, pixels);
    }

    fn writeColorMap16(self: TGA, writer: buffered_stream_source.DefaultBufferedStreamSourceWriter.Writer, indexed: color.IndexedStorage8) Image.WriteError!void {
        var data_index: usize = self.header.color_map_spec.first_entry_index;
        const data_end: usize = self.header.color_map_spec.first_entry_index + self.header.color_map_spec.length;

        while (data_index < data_end) : (data_index += 1) {
            const converted_color = color.Rgb555{
                .r = color.scaleToIntColor(u5, indexed.palette[data_index].r),
                .g = color.scaleToIntColor(u5, indexed.palette[data_index].g),
                .b = color.scaleToIntColor(u5, indexed.palette[data_index].b),
            };

            try writer.writeInt(u16, @as(u15, @bitCast(converted_color)), .little);
        }
    }

    fn writeColorMap24(self: TGA, writer: buffered_stream_source.DefaultBufferedStreamSourceWriter.Writer, indexed: color.IndexedStorage8) Image.WriteError!void {
        var data_index: usize = self.header.color_map_spec.first_entry_index;
        const data_end: usize = self.header.color_map_spec.first_entry_index + self.header.color_map_spec.length;

        while (data_index < data_end) : (data_index += 1) {
            const converted_color = color.Bgr24{
                .r = indexed.palette[data_index].r,
                .g = indexed.palette[data_index].g,
                .b = indexed.palette[data_index].b,
            };

            try utils.writeStruct(writer, converted_color, .little);
        }
    }
};
