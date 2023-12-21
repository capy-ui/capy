const std = @import("std");
const Image = @import("../Image.zig");

// Implement a variable code size LZW decoder with support for clear code and end of information code required for GIF decoding
pub fn Decoder(comptime endian: std.builtin.Endian) type {
    return struct {
        area_allocator: std.heap.ArenaAllocator,
        code_size: u8 = 0,
        clear_code: u13 = 0,
        initial_code_size: u8 = 0,
        end_information_code: u13 = 0,
        next_code: u13 = 0,
        previous_code: ?u13 = null,
        dictionary: std.AutoArrayHashMap(u13, []const u8),

        remaining_data: ?u13 = null,
        remaining_bits: u4 = 0,

        const MaxCodeSize = 12;

        const Self = @This();

        pub fn init(allocator: std.mem.Allocator, initial_code_size: u8) !Self {
            var result = Self{
                .area_allocator = std.heap.ArenaAllocator.init(allocator),
                .code_size = initial_code_size,
                .dictionary = std.AutoArrayHashMap(u13, []const u8).init(allocator),
                .initial_code_size = initial_code_size,
                .clear_code = @as(u13, 1) << @intCast(initial_code_size),
                .end_information_code = (@as(u13, 1) << @intCast(initial_code_size)) + 1,
                .next_code = (@as(u13, 1) << @intCast(initial_code_size)) + 2,
            };

            // Reset dictionary and code to its default state
            try result.resetDictionary();

            return result;
        }

        pub fn deinit(self: *Self) void {
            self.area_allocator.deinit();
            self.dictionary.deinit();
        }

        pub fn decode(self: *Self, reader: Image.Stream.Reader, writer: anytype) !void {
            var bit_reader = std.io.bitReader(endian, reader);

            var bits_to_read = self.code_size + 1;

            var read_size: usize = 0;
            var read_code: u13 = 0;

            if (self.remaining_data) |remaining_data| {
                const rest_of_data = try bit_reader.readBits(u13, self.remaining_bits, &read_size);
                if (read_size > 0) {
                    switch (endian) {
                        .little => {
                            read_code = remaining_data | (rest_of_data << @as(u4, @intCast(bits_to_read - self.remaining_bits)));
                        },
                        .big => {
                            read_code = (remaining_data << self.remaining_bits) | rest_of_data;
                        },
                    }
                }
                self.remaining_data = null;
            } else {
                read_code = try bit_reader.readBits(u13, bits_to_read, &read_size);
            }

            var allocator = self.area_allocator.allocator();

            while (read_size > 0) {
                if (self.dictionary.get(read_code)) |value| {
                    _ = try writer.write(value);

                    if (self.previous_code) |previous_code| {
                        if (self.dictionary.get(previous_code)) |previous_value| {
                            var new_value = try allocator.alloc(u8, previous_value.len + 1);
                            std.mem.copyForwards(u8, new_value, previous_value);
                            new_value[previous_value.len] = value[0];
                            try self.dictionary.put(self.next_code, new_value);

                            self.next_code += 1;

                            const max_code = @as(u13, 1) << @intCast(self.code_size + 1);
                            if (self.next_code == max_code and (self.code_size + 1) < MaxCodeSize) {
                                self.code_size += 1;
                                bits_to_read += 1;
                            }
                        }
                    }
                } else {
                    if (read_code == self.clear_code) {
                        try self.resetDictionary();
                        bits_to_read = self.code_size + 1;
                        self.previous_code = read_code;
                    } else if (read_code == self.end_information_code) {
                        return;
                    } else {
                        if (self.previous_code) |previous_code| {
                            if (self.dictionary.get(previous_code)) |previous_value| {
                                var new_value = try allocator.alloc(u8, previous_value.len + 1);
                                std.mem.copyForwards(u8, new_value, previous_value);
                                new_value[previous_value.len] = previous_value[0];
                                try self.dictionary.put(self.next_code, new_value);

                                _ = try writer.write(new_value);

                                self.next_code += 1;

                                const max_code = @as(u13, 1) << @intCast(self.code_size + 1);
                                if (self.next_code == max_code and (self.code_size + 1) < MaxCodeSize) {
                                    self.code_size += 1;
                                    bits_to_read += 1;
                                }
                            }
                        }
                    }
                }

                self.previous_code = read_code;

                read_code = try bit_reader.readBits(u13, bits_to_read, &read_size);
                if (read_size != bits_to_read) {
                    self.remaining_data = read_code;
                    self.remaining_bits = @intCast(bits_to_read - read_size);
                    return;
                }
            }
        }

        fn resetDictionary(self: *Self) !void {
            self.dictionary.clearRetainingCapacity();
            self.area_allocator.deinit();

            self.code_size = self.initial_code_size;
            self.next_code = (@as(u13, 1) << @intCast(self.initial_code_size)) + 2;

            self.area_allocator = std.heap.ArenaAllocator.init(self.area_allocator.child_allocator);
            var allocator = self.area_allocator.allocator();

            const roots_size = @as(usize, 1) << @intCast(self.code_size);

            var index: u13 = 0;

            while (index < roots_size) : (index += 1) {
                var data = try allocator.alloc(u8, 1);
                data[0] = @as(u8, @truncate(index));

                try self.dictionary.put(index, data);
            }
        }
    };
}

test "Should decode a simple LZW little-endian stream" {
    const initial_code_size = 2;
    const test_data = [_]u8{ 0x4c, 0x01 };

    var reader = Image.Stream{
        .const_buffer = std.io.fixedBufferStream(&test_data),
    };

    var out_data_storage: [256]u8 = undefined;
    var out_data_buffer = Image.Stream{
        .buffer = std.io.fixedBufferStream(&out_data_storage),
    };

    var lzw = try Decoder(.little).init(std.testing.allocator, initial_code_size);
    defer lzw.deinit();

    try lzw.decode(reader.reader(), out_data_buffer.writer());

    try std.testing.expectEqual(@as(usize, 1), out_data_buffer.buffer.pos);
    try std.testing.expectEqual(@as(u8, 1), out_data_storage[0]);
}
