//! This module contains implementation of huffman table encodings
//! as specified by section 2.4.2 in t-81 1992

const std = @import("std");
const Allocator = std.mem.Allocator;

const buffered_stream_source = @import("../../buffered_stream_source.zig");
const Image = @import("../../Image.zig");
const ImageReadError = Image.ReadError;

const HuffmanCode = struct { length_minus_one: u4, code: u16 };
const HuffmanCodeMap = std.AutoArrayHashMap(HuffmanCode, u8);

const JPEG_DEBUG = false;
const JPEG_VERY_DEBUG = false;

pub const Table = struct {
    const Self = @This();

    allocator: Allocator,

    code_counts: [16]u8,
    code_map: HuffmanCodeMap,

    table_class: u8,

    pub fn read(allocator: Allocator, table_class: u8, reader: buffered_stream_source.DefaultBufferedStreamSourceReader.Reader) ImageReadError!Self {
        if (table_class & 1 != table_class)
            return ImageReadError.InvalidData;

        var code_counts: [16]u8 = undefined;
        if ((try reader.read(code_counts[0..])) < 16) {
            return ImageReadError.InvalidData;
        }

        if (JPEG_DEBUG) std.debug.print("  Code counts: {any}\n", .{code_counts});

        var total_huffman_codes: usize = 0;
        for (code_counts) |count| total_huffman_codes += count;

        var huffman_code_map = HuffmanCodeMap.init(allocator);
        errdefer huffman_code_map.deinit();

        if (JPEG_VERY_DEBUG) std.debug.print("  Decoded huffman codes map:\n", .{});

        var code: u16 = 0;
        for (code_counts, 0..) |count, i| {
            if (JPEG_VERY_DEBUG) {
                std.debug.print("    Length {}: ", .{i + 1});
                if (count == 0) {
                    std.debug.print("(none)\n", .{});
                } else {
                    std.debug.print("\n", .{});
                }
            }

            var j: usize = 0;
            while (j < count) : (j += 1) {
                // Check if we hit all 1s, i.e. 111111 for i == 6, which is an invalid value
                if (code == (@as(u17, @intCast(1)) << (@as(u5, @intCast(i)) + 1)) - 1) {
                    return ImageReadError.InvalidData;
                }

                const byte = try reader.readByte();
                try huffman_code_map.put(.{ .length_minus_one = @as(u4, @intCast(i)), .code = code }, byte);

                if (JPEG_VERY_DEBUG) std.debug.print("      {b} => 0x{X}\n", .{ code, byte });
                code += 1;
            }

            code <<= 1;
        }

        return Self{
            .allocator = allocator,
            .code_counts = code_counts,
            .code_map = huffman_code_map,
            .table_class = table_class,
        };
    }

    pub fn deinit(self: *Self) void {
        self.code_map.deinit();
    }
};

pub const Reader = struct {
    const Self = @This();

    table: ?*const Table = null,
    reader: buffered_stream_source.DefaultBufferedStreamSourceReader.Reader,
    byte_buffer: u8 = 0,
    bits_left: u4 = 0,
    last_byte_was_ff: bool = false,

    pub fn init(reader: buffered_stream_source.DefaultBufferedStreamSourceReader.Reader) Self {
        return .{
            .reader = reader,
        };
    }

    pub fn setHuffmanTable(self: *Self, table: *const Table) void {
        self.table = table;
    }

    fn readBit(self: *Self) ImageReadError!u1 {
        if (self.bits_left == 0) {
            self.byte_buffer = try self.reader.readByte();

            if (self.byte_buffer == 0 and self.last_byte_was_ff) {
                // This was a stuffed byte, read one more.
                self.byte_buffer = try self.reader.readByte();
            }
            self.last_byte_was_ff = self.byte_buffer == 0xFF;
            self.bits_left = 8;
        }

        const bit: u1 = @intCast(self.byte_buffer >> 7);
        self.byte_buffer <<= 1;
        self.bits_left -= 1;

        return bit;
    }

    pub fn readCode(self: *Self) ImageReadError!u8 {
        var code: u16 = 0;

        var i: u5 = 0;
        while (i < 16) : (i += 1) {
            // NOTE: if the table is stored as a tree, this is O(1) to update the new node,
            // instead of O(log n), so should be faster.
            code = (code << 1) | (try self.readBit());
            if (self.table.?.code_map.get(.{ .length_minus_one = @intCast(i), .code = code })) |value| {
                return value;
            }
        }

        if (JPEG_DEBUG) std.debug.print("found unknown code: {x}\n", .{code});
        return ImageReadError.InvalidData;
    }

    pub fn readLiteralBits(self: *Self, bitsNeeded: u8) ImageReadError!u32 {
        var bits: u32 = 0;

        var i: usize = 0;
        while (i < bitsNeeded) : (i += 1) {
            bits = (bits << 1) | (try self.readBit());
        }

        return bits;
    }

    /// This function implements T.81 section F1.2.1, Huffman encoding of DC coefficients.
    pub fn readMagnitudeCoded(self: *Self, magnitude: u5) ImageReadError!i32 {
        if (magnitude == 0)
            return 0;

        const bits = try self.readLiteralBits(magnitude);

        // The sign of the read bits value.
        const bits_sign = (bits >> (magnitude - 1)) & 1;
        // The mask for clearing the sign bit.
        const bits_mask = (@as(u32, 1) << (magnitude - 1)) - 1;
        // The bits without the sign bit.
        const unsigned_bits = bits & bits_mask;

        // The magnitude base value. This is -2^n+1 when bits_sign == 0, and
        // 2^(n-1) when bits_sign == 1.
        const base = if (bits_sign == 0)
            -(@as(i32, 1) << magnitude) + 1
        else
            (@as(i32, 1) << (magnitude - 1));

        return base + @as(i32, @bitCast(unsigned_bits));
    }
};
