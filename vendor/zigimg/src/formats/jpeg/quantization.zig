//! see section 2.4.1 of the spec t-81 1992

const std = @import("std");

const buffered_stream_source = @import("../../buffered_stream_source.zig");
const Image = @import("../../Image.zig");
const ImageReadError = Image.ReadError;

const ZigzagOffsets = @import("./utils.zig").ZigzagOffsets;

const JPEG_DEBUG = false;

pub const Header = struct {
    // TODO(angelo): ! substitute this implementation to `parseDefineQuantizationTables` in jpeg.zig
    const Self = @This();

    //// Specifies the precision of the quantization table entries.
    ///  - 0 = 8 bits
    /// - 1 = 16 bits
    table_precision: u4,

    /// Specifies one of four possible destinations at the decoder into
    /// which the quantization table shall be installed.
    table_destination: u4,

    table: Table,

    pub fn read(reader: buffered_stream_source.DefaultBufferedStreamSourceReader.Reader) ImageReadError!Self {
        _ = try reader.readInt(u16, .big); // read the size, but we don't need it

        const precision_and_destination = try reader.readByte();
        const table_precision = precision_and_destination >> 4;
        const table_destination = precision_and_destination & 0b11;

        const table = try Table.read(table_precision, reader);

        // TODO: add check for: "An 8-bit DCT-based process shall not use a 16-bit precision quantization table."

        return Self{
            .table_precision = table_precision,
            .table_destination = table_destination,
            .table = table,
        };
    }
};

pub const Table = union(enum) {
    const Self = @This();
    q8: [64]u8,
    q16: [64]u16,

    pub fn read(precision: u8, reader: buffered_stream_source.DefaultBufferedStreamSourceReader.Reader) ImageReadError!Self {
        // 0 = 8 bits, 1 = 16 bits
        switch (precision) {
            0 => {
                var table = Self{ .q8 = undefined };

                var offset: usize = 0;
                while (offset < 64) : (offset += 1) {
                    const value = try reader.readByte();
                    table.q8[ZigzagOffsets[offset]] = value;
                }

                if (JPEG_DEBUG) {
                    var i: usize = 0;
                    while (i < 8) : (i += 1) {
                        var j: usize = 0;
                        while (j < 8) : (j += 1) {
                            std.debug.print("{d:4} ", .{table.q8[i * 8 + j]});
                        }
                        std.debug.print("\n", .{});
                    }
                }

                return table;
            },
            1 => {
                var table = Self{ .q16 = undefined };

                var offset: usize = 0;
                while (offset < 64) : (offset += 1) {
                    const value = try reader.readInt(u16, .big);
                    table.q16[ZigzagOffsets[offset]] = value;
                }

                return table;
            },
            else => return ImageReadError.InvalidData,
        }
    }
};
