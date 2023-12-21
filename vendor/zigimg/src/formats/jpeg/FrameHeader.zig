//! this module implements the frame header followint the t-81 specs,
//! section b.2.2 Frame Header Syntax

const std = @import("std");

const buffered_stream_source = @import("../../buffered_stream_source.zig");
const Image = @import("../../Image.zig");
const ImageReadError = Image.ReadError;

const Allocator = std.mem.Allocator;

const JPEG_DEBUG = false;

const Component = struct {
    id: u8,
    horizontal_sampling_factor: u4,
    vertical_sampling_factor: u4,
    quantization_table_id: u8,

    pub fn read(reader: buffered_stream_source.DefaultBufferedStreamSourceReader.Reader) ImageReadError!Component {
        const component_id = try reader.readByte();
        const sampling_factors = try reader.readByte();
        const quantization_table_id = try reader.readByte();

        const horizontal_sampling_factor: u4 = @intCast(sampling_factors >> 4);
        const vertical_sampling_factor: u4 = @intCast(sampling_factors & 0xF);

        if (horizontal_sampling_factor < 1 or horizontal_sampling_factor > 4) {
            // TODO(angelo): error, create cusotm error
            return ImageReadError.InvalidData;
        }

        if (vertical_sampling_factor < 1 or vertical_sampling_factor > 4) {
            // TODO(angelo): error, create custom error
            return ImageReadError.InvalidData;
        }

        if (quantization_table_id > 3) {
            // TODO(angelo): error, create custom error
            return ImageReadError.InvalidData;
        }

        return Component{
            .id = component_id,
            .horizontal_sampling_factor = horizontal_sampling_factor,
            .vertical_sampling_factor = vertical_sampling_factor,
            .quantization_table_id = quantization_table_id,
        };
    }
};

const Self = @This();

allocator: Allocator,
sample_precision: u8,
row_count: u16,
samples_per_row: u16,
components: []Component,

pub fn read(allocator: Allocator, reader: buffered_stream_source.DefaultBufferedStreamSourceReader.Reader) ImageReadError!Self {
    const segment_size = try reader.readInt(u16, .big);
    if (JPEG_DEBUG) std.debug.print("StartOfFrame: frame size = 0x{X}\n", .{segment_size});

    const sample_precision = try reader.readByte();
    const row_count = try reader.readInt(u16, .big);
    const samples_per_row = try reader.readInt(u16, .big);

    const component_count = try reader.readByte();

    if (component_count != 1 and component_count != 3) {
        // TODO(angelo): use jpeg error here, for components
        return ImageReadError.InvalidData;
    }

    if (JPEG_DEBUG) std.debug.print("  {}x{}, precision={}, {} components\n", .{ samples_per_row, row_count, sample_precision, component_count });

    var components = try allocator.alloc(Component, component_count);
    errdefer allocator.free(components);

    var i: usize = 0;
    while (i < component_count) : (i += 1) {
        components[i] = try Component.read(reader);
        // TODO(angelo): remove this
        // if (JPEG_VERY_DEBUG) {
        //     std.debug.print("    ID={}, Vfactor={}, Hfactor={} QtableID={}\n", .{
        //         components[i].id, components[i].vertical_sampling_factor, components[i].horizontal_sampling_factor, components[i].quantization_table_id,
        //     });
        // }
    }

    // see B 8.2 table for the meaning of this check.
    std.debug.assert(segment_size == 8 + 3 * component_count);

    return Self{
        .allocator = allocator,
        .sample_precision = sample_precision,
        .row_count = row_count,
        .samples_per_row = samples_per_row,
        .components = components,
    };
}

pub fn deinit(self: *Self) void {
    self.allocator.free(self.components);
}

pub fn getMaxHorizontalSamplingFactor(self: Self) usize {
    var ret: u4 = 0;
    for (self.components) |component| {
        if (ret < component.horizontal_sampling_factor) {
            ret = component.horizontal_sampling_factor;
        }
    }

    return ret;
}

pub fn getMaxVerticalSamplingFactor(self: Self) usize {
    var ret: u4 = 0;
    for (self.components) |component| {
        if (ret < component.vertical_sampling_factor) {
            ret = component.vertical_sampling_factor;
        }
    }

    return ret;
}

pub fn getBlockCount(self: Self, component_id: usize) usize {
    // MCU of non-interleaved is just one block.
    if (self.components.len == 1) {
        return 1;
    }

    const horizontal_block_count = self.components[component_id].horizontal_sampling_factor;
    const vertical_block_count = self.components[component_id].vertical_sampling_factor;
    return horizontal_block_count * vertical_block_count;
}
