const std = @import("std");

const buffered_stream_source = @import("../../buffered_stream_source.zig");
const color = @import("../../color.zig");
const Image = @import("../../Image.zig");
const ImageReadError = Image.ReadError;

const FrameHeader = @import("FrameHeader.zig");
const Frame = @import("Frame.zig");
const HuffmanReader = @import("huffman.zig").Reader;

const MAX_COMPONENTS = @import("utils.zig").MAX_COMPONENTS;
const MAX_BLOCKS = @import("utils.zig").MAX_BLOCKS;
const MCU = @import("utils.zig").MCU;
const ZigzagOffsets = @import("utils.zig").ZigzagOffsets;

const Self = @This();

const JPEG_DEBUG = false;
const JPEG_VERY_DEBUG = false;

frame: *const Frame,
reader: HuffmanReader,
scan_header: ScanHeader,
mcu_storage: [MAX_COMPONENTS][MAX_BLOCKS]MCU,
prediction_values: [3]i12,

pub fn init(frame: *const Frame, reader: buffered_stream_source.DefaultBufferedStreamSourceReader.Reader) ImageReadError!Self {
    const scan_header = try ScanHeader.read(reader);
    return Self{
        .frame = frame,
        .reader = HuffmanReader.init(reader),
        .scan_header = scan_header,
        .mcu_storage = undefined,
        .prediction_values = [3]i12{ 0, 0, 0 },
    };
}

/// Perform the scan operation.
/// We assume the AC and DC huffman tables are already set up, and ready to decode.
/// This should implement section E.2.3 of t-81 1992.
pub fn performScan(frame: *const Frame, reader: buffered_stream_source.DefaultBufferedStreamSourceReader.Reader, pixels_opt: *?color.PixelStorage) ImageReadError!void {
    var self = try Self.init(frame, reader);

    const mcu_count = Self.calculateMCUCountInFrame(&frame.frame_header);
    for (0..mcu_count) |mcu_id| {
        try self.decodeMCU();
        try self.dequantize();
        try frame.renderToPixels(&self.mcu_storage, mcu_id, &pixels_opt.*.?);
    }
}

fn dequantize(self: *Self) !void {
    for (self.frame.frame_header.components, 0..) |component, component_id| {
        const block_count = self.frame.frame_header.getBlockCount(component_id);
        for (0..block_count) |i| {
            const block = &self.mcu_storage[component_id][i];

            if (self.frame.quantization_tables[component.quantization_table_id]) |quantization_table| {
                var sample_id: usize = 0;
                while (sample_id < 64) : (sample_id += 1) {
                    block[sample_id] = block[sample_id] * quantization_table.q8[sample_id];
                }
            } else return ImageReadError.InvalidData;
        }
    }
}

fn calculateMCUCountInFrame(frame_header: *const FrameHeader) usize {
    // FIXME: This is very naive and probably only works for Baseline DCT.
    // MCU of non-interleaved is just one block.
    const horizontal_block_count = if (1 < frame_header.components.len) frame_header.getMaxHorizontalSamplingFactor() else 1;
    const vertical_block_count = if (1 < frame_header.components.len) frame_header.getMaxVerticalSamplingFactor() else 1;
    const mcu_width = 8 * horizontal_block_count;
    const mcu_height = 8 * vertical_block_count;
    const mcu_count_per_row = (frame_header.samples_per_row + mcu_width - 1) / mcu_width;
    const mcu_count_per_column = (frame_header.row_count + mcu_height - 1) / mcu_height;
    return mcu_count_per_row * mcu_count_per_column;
}

fn decodeMCU(self: *Self) ImageReadError!void {
    for (self.scan_header.components, 0..) |maybe_component, component_id| {
        _ = component_id;
        if (maybe_component == null)
            break;

        try self.decodeMCUComponent(maybe_component.?);
    }
}

fn decodeMCUComponent(self: *Self, component: ScanComponentSpec) ImageReadError!void {
    // The encoder might reorder components or omit one if it decides that the
    // file size can be reduced that way. Therefore we need to select the correct
    // destination for this component.
    const component_destination: usize = blk: {
        for (self.frame.frame_header.components, 0..) |frame_component, i| {
            if (frame_component.id == component.component_selector) {
                break :blk i;
            }
        }

        return ImageReadError.InvalidData;
    };

    const block_count = self.frame.frame_header.getBlockCount(component_destination);
    for (0..block_count) |i| {
        const mcu = &self.mcu_storage[component_destination][i];

        // Decode the DC coefficient
        if (self.frame.dc_huffman_tables[component.dc_table_selector] == null) return ImageReadError.InvalidData;

        self.reader.setHuffmanTable(&self.frame.dc_huffman_tables[component.dc_table_selector].?);

        const dc_coefficient = try self.decodeDCCoefficient(component_destination);
        mcu[0] = dc_coefficient;

        // Decode the AC coefficients
        if (self.frame.ac_huffman_tables[component.ac_table_selector] == null)
            return ImageReadError.InvalidData;

        self.reader.setHuffmanTable(&self.frame.ac_huffman_tables[component.ac_table_selector].?);

        try self.decodeACCoefficients(mcu);
    }
}

fn decodeDCCoefficient(self: *Self, component_destination: usize) ImageReadError!i12 {
    const maybe_magnitude = try self.reader.readCode();
    if (maybe_magnitude > 11) return ImageReadError.InvalidData;
    const magnitude: u4 = @intCast(maybe_magnitude);

    const diff: i12 = @intCast(try self.reader.readMagnitudeCoded(magnitude));
    // TODO: check correctess after refactor
    const dc_coefficient = diff + self.prediction_values[component_destination];
    self.prediction_values[component_destination] = dc_coefficient;

    return dc_coefficient;
}

fn decodeACCoefficients(self: *Self, mcu: *MCU) ImageReadError!void {
    var ac: usize = 1;
    var did_see_eob = false;
    while (ac < 64) : (ac += 1) {
        if (did_see_eob) {
            mcu[ZigzagOffsets[ac]] = 0;
            continue;
        }

        const zero_run_length_and_magnitude = try self.reader.readCode();
        // 00 == EOB
        if (zero_run_length_and_magnitude == 0x00) {
            did_see_eob = true;
            mcu[ZigzagOffsets[ac]] = 0;
            continue;
        }

        const zero_run_length = zero_run_length_and_magnitude >> 4;

        const maybe_magnitude = zero_run_length_and_magnitude & 0xF;
        if (maybe_magnitude > 10) return ImageReadError.InvalidData;
        const magnitude: u4 = @intCast(maybe_magnitude);

        const ac_coefficient: i11 = @intCast(try self.reader.readMagnitudeCoded(magnitude));

        var i: usize = 0;
        while (i < zero_run_length) : (i += 1) {
            mcu[ZigzagOffsets[ac]] = 0;
            ac += 1;
        }

        mcu[ZigzagOffsets[ac]] = ac_coefficient;
    }
}

pub const ScanComponentSpec = struct {
    component_selector: u8,
    dc_table_selector: u4,
    ac_table_selector: u4,

    pub fn read(reader: buffered_stream_source.DefaultBufferedStreamSourceReader.Reader) ImageReadError!ScanComponentSpec {
        const component_selector = try reader.readByte();
        const entropy_coding_selectors = try reader.readByte();

        const dc_table_selector: u4 = @intCast(entropy_coding_selectors >> 4);
        const ac_table_selector: u4 = @intCast(entropy_coding_selectors & 0b11);

        if (JPEG_VERY_DEBUG) {
            std.debug.print("    Component spec: selector={}, DC table ID={}, AC table ID={}\n", .{ component_selector, dc_table_selector, ac_table_selector });
        }

        return ScanComponentSpec{
            .component_selector = component_selector,
            .dc_table_selector = dc_table_selector,
            .ac_table_selector = ac_table_selector,
        };
    }
};

pub const Header = struct {
    components: [4]?ScanComponentSpec,

    ///  first DCT coefficient in each block in zig-zag order
    start_of_spectral_selection: u8,

    /// last DCT coefficient in each block in zig-zag order
    /// 63 for sequential DCT, 0 for lossless
    /// TODO(angelo) add check for this.
    end_of_spectral_selection: u8,
    approximation_high: u4,
    approximation_low: u4,

    pub fn read(reader: buffered_stream_source.DefaultBufferedStreamSourceReader.Reader) ImageReadError!Header {
        const segment_size = try reader.readInt(u16, .big);
        if (JPEG_DEBUG) std.debug.print("StartOfScan: segment size = 0x{X}\n", .{segment_size});

        const component_count = try reader.readByte();
        if (component_count < 1 or component_count > 4) {
            return ImageReadError.InvalidData;
        }

        if (JPEG_DEBUG) std.debug.print("  Component count: {}\n", .{component_count});

        var components = [_]?ScanComponentSpec{null} ** 4;

        if (JPEG_VERY_DEBUG) std.debug.print("  Components:\n", .{});
        var i: usize = 0;
        while (i < component_count) : (i += 1) {
            components[i] = try ScanComponentSpec.read(reader);
        }

        const start_of_spectral_selection = try reader.readByte();
        const end_of_spectral_selection = try reader.readByte();

        if (start_of_spectral_selection > 63) {
            return ImageReadError.InvalidData;
        }

        if (end_of_spectral_selection < start_of_spectral_selection or end_of_spectral_selection > 63) {
            return ImageReadError.InvalidData;
        }

        // If Ss = 0, then Se = 63.
        if (start_of_spectral_selection == 0 and end_of_spectral_selection != 63) {
            return ImageReadError.InvalidData;
        }

        if (JPEG_VERY_DEBUG) std.debug.print("  Spectral selection: {}-{}\n", .{ start_of_spectral_selection, end_of_spectral_selection });

        const approximation_bits = try reader.readByte();
        const approximation_high: u4 = @intCast(approximation_bits >> 4);
        const approximation_low: u4 = @intCast(approximation_bits & 0b1111);
        if (JPEG_VERY_DEBUG) std.debug.print("  Approximation bit position: high={} low={}\n", .{ approximation_high, approximation_low });

        std.debug.assert(segment_size == 2 * component_count + 1 + 2 + 1 + 2);

        return Header{
            .components = components,
            .start_of_spectral_selection = start_of_spectral_selection,
            .end_of_spectral_selection = end_of_spectral_selection,
            .approximation_high = approximation_high,
            .approximation_low = approximation_low,
        };
    }
};

const ScanHeader = Header;
