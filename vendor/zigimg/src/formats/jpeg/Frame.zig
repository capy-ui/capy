const std = @import("std");
const Allocator = std.mem.Allocator;

const buffered_stream_source = @import("../../buffered_stream_source.zig");
const Image = @import("../../Image.zig");
const ImageReadError = Image.ReadError;

const Markers = @import("utils.zig").Markers;
const FrameHeader = @import("FrameHeader.zig");
const QuantizationTable = @import("quantization.zig").Table;
const HuffmanTable = @import("huffman.zig").Table;
const color = @import("../../color.zig");

const IDCTMultipliers = @import("utils.zig").IDCTMultipliers;
const MAX_COMPONENTS = @import("utils.zig").MAX_COMPONENTS;
const MAX_BLOCKS = @import("utils.zig").MAX_BLOCKS;
const MCU = @import("utils.zig").MCU;

const Self = @This();
allocator: Allocator,
frame_header: FrameHeader,
quantization_tables: *[4]?QuantizationTable,
dc_huffman_tables: [2]?HuffmanTable,
ac_huffman_tables: [2]?HuffmanTable,

const JPEG_DEBUG = false;

pub fn read(allocator: Allocator, quantization_tables: *[4]?QuantizationTable, buffered_stream: *buffered_stream_source.DefaultBufferedStreamSourceReader) ImageReadError!Self {
    const reader = buffered_stream.reader();
    const frame_header = try FrameHeader.read(allocator, reader);

    var self = Self{
        .allocator = allocator,
        .frame_header = frame_header,
        .quantization_tables = quantization_tables,
        .dc_huffman_tables = [_]?HuffmanTable{null} ** 2,
        .ac_huffman_tables = [_]?HuffmanTable{null} ** 2,
    };
    errdefer self.deinit();

    var marker = try reader.readInt(u16, .big);
    while (marker != @intFromEnum(Markers.start_of_scan)) : (marker = try reader.readInt(u16, .big)) {
        if (JPEG_DEBUG) std.debug.print("Frame: Parsing marker value: 0x{X}\n", .{marker});

        switch (@as(Markers, @enumFromInt(marker))) {
            .define_huffman_tables => {
                try self.parseDefineHuffmanTables(reader);
            },
            else => {
                return ImageReadError.InvalidData;
            },
        }
    }

    // Undo the last marker read
    try buffered_stream.seekBy(-2);

    return self;
}

pub fn deinit(self: *Self) void {
    for (&self.dc_huffman_tables) |*maybe_huffman_table| {
        if (maybe_huffman_table.*) |*huffman_table| {
            huffman_table.deinit();
        }
    }

    for (&self.ac_huffman_tables) |*maybe_huffman_table| {
        if (maybe_huffman_table.*) |*huffman_table| {
            huffman_table.deinit();
        }
    }

    self.frame_header.deinit();
}

fn parseDefineHuffmanTables(self: *Self, reader: buffered_stream_source.DefaultBufferedStreamSourceReader.Reader) ImageReadError!void {
    var segment_size = try reader.readInt(u16, .big);
    if (JPEG_DEBUG) std.debug.print("DefineHuffmanTables: segment size = 0x{X}\n", .{segment_size});
    segment_size -= 2;

    while (segment_size > 0) {
        const class_and_destination = try reader.readByte();
        const table_class = class_and_destination >> 4;
        const table_destination = class_and_destination & 0b1;

        const huffman_table = try HuffmanTable.read(self.allocator, table_class, reader);

        if (table_class == 0) {
            if (self.dc_huffman_tables[table_destination]) |*old_huffman_table| {
                old_huffman_table.deinit();
            }
            self.dc_huffman_tables[table_destination] = huffman_table;
        } else {
            if (self.ac_huffman_tables[table_destination]) |*old_huffman_table| {
                old_huffman_table.deinit();
            }
            self.ac_huffman_tables[table_destination] = huffman_table;
        }

        if (JPEG_DEBUG) std.debug.print("  Table with class {} installed at {}\n", .{ table_class, table_destination });

        // Class+Destination + code counts + code table
        segment_size -= 1 + 16 + @as(u16, @intCast(huffman_table.code_map.count()));
    }
}

pub fn renderToPixels(self: *const Self, mcu_storage: *[MAX_COMPONENTS][MAX_BLOCKS]MCU, mcu_id: usize, pixels: *color.PixelStorage) ImageReadError!void {
    switch (self.frame_header.components.len) {
        1 => try self.renderToPixelsGrayscale(&mcu_storage[0][0], mcu_id, pixels.grayscale8), // Grayscale images is non-interleaved
        3 => try self.renderToPixelsRgb(mcu_storage, mcu_id, pixels.rgb24),
        else => unreachable,
    }
}

fn renderToPixelsGrayscale(self: *const Self, mcu_storage: *MCU, mcu_id: usize, pixels: []color.Grayscale8) ImageReadError!void {
    const mcu_width = 8;
    const mcu_height = 8;
    const width = self.frame_header.samples_per_row;
    const height = pixels.len / width;
    const mcus_per_row = (width + mcu_width - 1) / mcu_width;
    const mcu_origin_x = (mcu_id % mcus_per_row) * mcu_width;
    const mcu_origin_y = (mcu_id / mcus_per_row) * mcu_height;

    for (0..mcu_height) |mcu_y| {
        const y = mcu_origin_y + mcu_y;
        if (y >= height) continue;

        // y coordinates in the block
        const block_y = mcu_y % 8;

        const stride = y * width;

        for (0..mcu_width) |mcu_x| {
            const x = mcu_origin_x + mcu_x;
            if (x >= width) continue;

            // x coordinates in the block
            const block_x = mcu_x % 8;

            const reconstructed_Y = idct(mcu_storage, @as(u3, @intCast(block_x)), @as(u3, @intCast(block_y)), mcu_id, 0);
            const Y: f32 = @floatFromInt(reconstructed_Y);
            pixels[stride + x] = .{
                .value = @as(u8, @intFromFloat(std.math.clamp(Y + 128.0, 0.0, 255.0))),
            };
        }
    }
}

fn renderToPixelsRgb(self: *const Self, mcu_storage: *[MAX_COMPONENTS][MAX_BLOCKS]MCU, mcu_id: usize, pixels: []color.Rgb24) ImageReadError!void {
    const max_horizontal_sampling_factor = self.frame_header.getMaxHorizontalSamplingFactor();
    const max_vertical_sampling_factor = self.frame_header.getMaxVerticalSamplingFactor();
    const mcu_width = 8 * max_horizontal_sampling_factor;
    const mcu_height = 8 * max_vertical_sampling_factor;
    const width = self.frame_header.samples_per_row;
    const height = pixels.len / width;
    const mcus_per_row = (width + mcu_width - 1) / mcu_width;

    const mcu_origin_x = (mcu_id % mcus_per_row) * mcu_width;
    const mcu_origin_y = (mcu_id / mcus_per_row) * mcu_height;

    for (0..mcu_height) |mcu_y| {
        const y = mcu_origin_y + mcu_y;
        if (y >= height) continue;

        // y coordinates of each component applied to the sampling factor
        const y_sampled_y = (mcu_y * self.frame_header.components[0].vertical_sampling_factor) / max_vertical_sampling_factor;
        const cb_sampled_y = (mcu_y * self.frame_header.components[1].vertical_sampling_factor) / max_vertical_sampling_factor;
        const cr_sampled_y = (mcu_y * self.frame_header.components[2].vertical_sampling_factor) / max_vertical_sampling_factor;

        // y coordinates of each component in the block
        const y_block_y = y_sampled_y % 8;
        const cb_block_y = cb_sampled_y % 8;
        const cr_block_y = cr_sampled_y % 8;

        const stride = y * width;

        for (0..mcu_width) |mcu_x| {
            const x = mcu_origin_x + mcu_x;
            if (x >= width) continue;

            // x coordinates of each component applied to the sampling factor
            const y_sampled_x = (mcu_x * self.frame_header.components[0].horizontal_sampling_factor) / max_horizontal_sampling_factor;
            const cb_sampled_x = (mcu_x * self.frame_header.components[1].horizontal_sampling_factor) / max_horizontal_sampling_factor;
            const cr_sampled_x = (mcu_x * self.frame_header.components[2].horizontal_sampling_factor) / max_horizontal_sampling_factor;

            // x coordinates of each component in the block
            const y_block_x = y_sampled_x % 8;
            const cb_block_x = cb_sampled_x % 8;
            const cr_block_x = cr_sampled_x % 8;

            const y_block_ind = (y_sampled_y / 8) * self.frame_header.components[0].horizontal_sampling_factor + (y_sampled_x / 8);
            const cb_block_ind = (cb_sampled_y / 8) * self.frame_header.components[1].horizontal_sampling_factor + (cb_sampled_x / 8);
            const cr_block_ind = (cr_sampled_y / 8) * self.frame_header.components[2].horizontal_sampling_factor + (cr_sampled_x / 8);

            const mcu_Y = &mcu_storage[0][y_block_ind];
            const mcu_Cb = &mcu_storage[1][cb_block_ind];
            const mcu_Cr = &mcu_storage[2][cr_block_ind];

            const reconstructed_Y = idct(mcu_Y, @as(u3, @intCast(y_block_x)), @as(u3, @intCast(y_block_y)), mcu_id, 0);
            const reconstructed_Cb = idct(mcu_Cb, @as(u3, @intCast(cb_block_x)), @as(u3, @intCast(cb_block_y)), mcu_id, 1);
            const reconstructed_Cr = idct(mcu_Cr, @as(u3, @intCast(cr_block_x)), @as(u3, @intCast(cr_block_y)), mcu_id, 2);

            const Y: f32 = @floatFromInt(reconstructed_Y);
            const Cb: f32 = @floatFromInt(reconstructed_Cb);
            const Cr: f32 = @floatFromInt(reconstructed_Cr);

            const Co_red = 0.299;
            const Co_green = 0.587;
            const Co_blue = 0.114;

            const r = Cr * (2 - 2 * Co_red) + Y;
            const b = Cb * (2 - 2 * Co_blue) + Y;
            const g = (Y - Co_blue * b - Co_red * r) / Co_green;

            pixels[stride + x] = .{
                .r = @intFromFloat(std.math.clamp(r + 128.0, 0.0, 255.0)),
                .g = @intFromFloat(std.math.clamp(g + 128.0, 0.0, 255.0)),
                .b = @intFromFloat(std.math.clamp(b + 128.0, 0.0, 255.0)),
            };
        }
    }
}

fn idct(mcu: *const MCU, x: u3, y: u3, mcu_id: usize, component_id: usize) i8 {
    // TODO(angelo): if Ns > 1 it is not interleaved, so the order this should be fixed...
    // FIXME is wrong for Ns > 1
    var reconstructed_pixel: f32 = 0.0;

    var u: usize = 0;
    while (u < 8) : (u += 1) {
        var v: usize = 0;
        while (v < 8) : (v += 1) {
            const mcu_value = mcu[v * 8 + u];
            reconstructed_pixel += IDCTMultipliers[y][x][u][v] * @as(f32, @floatFromInt(mcu_value));
        }
    }

    const scaled_pixel = @round(reconstructed_pixel / 4.0);
    if (JPEG_DEBUG) {
        if (scaled_pixel < -128.0 or scaled_pixel > 127.0) {
            std.debug.print("Pixel at mcu={} x={} y={} component_id={} is out of bounds with DCT: {d}!\n", .{ mcu_id, x, y, component_id, scaled_pixel });
        }
    }

    return @intFromFloat(std.math.clamp(scaled_pixel, -128.0, 127.0));
}
