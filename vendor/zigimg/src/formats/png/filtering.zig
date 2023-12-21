const std = @import("std");
const color = @import("../../color.zig");
const PixelFormat = @import("../../pixel_format.zig").PixelFormat;
const Image = @import("../../Image.zig");
const HeaderData = @import("types.zig").HeaderData;
const builtin = @import("builtin");

pub const FilterType = enum(u8) {
    none = 0,
    sub = 1,
    up = 2,
    average = 3,
    paeth = 4,
};

pub const FilterChoiceStrategies = enum {
    try_all,
    heuristic,
    specified,
};

pub const FilterChoice = union(FilterChoiceStrategies) {
    try_all,
    heuristic,
    specified: FilterType,
};

pub fn filter(writer: anytype, pixels: color.PixelStorage, filter_choice: FilterChoice, header: HeaderData) Image.WriteError!void {
    var scanline: color.PixelStorage = undefined;
    var previous_scanline: ?color.PixelStorage = null;

    const format: PixelFormat = pixels;

    if (format.bitsPerChannel() < 8)
        return Image.WriteError.Unsupported;

    const pixel_len = format.pixelStride();

    var y: usize = 0;
    while (y < header.height) : (y += 1) {
        scanline = pixels.slice(y * header.width, (y + 1) * header.width);

        const filter_type: FilterType = switch (filter_choice) {
            .try_all => @panic("Unimplemented"),
            .heuristic => filterChoiceHeuristic(scanline, previous_scanline),
            .specified => |f| f,
        };

        try writer.writeByte(@intFromEnum(filter_type));

        for (0..scanline.asBytes().len) |byte_index| {
            const i = if (builtin.target.cpu.arch.endian() == .little) pixelByteSwappedIndex(scanline, byte_index) else byte_index;

            const sample = scanline.asBytes()[i];
            const previous: u8 = if (byte_index >= pixel_len) scanline.asBytes()[i - pixel_len] else 0;
            const above: u8 = if (previous_scanline) |b| b.asBytes()[i] else 0;
            const above_previous = if (previous_scanline) |b| (if (byte_index >= pixel_len) b.asBytes()[i - pixel_len] else 0) else 0;

            const byte: u8 = switch (filter_type) {
                .none => sample,
                .sub => sample -% previous,
                .up => sample -% above,
                .average => sample -% average(previous, above),
                .paeth => sample -% paeth(previous, above, above_previous),
            };

            try writer.writeByte(byte);
        }
        previous_scanline = scanline;
    }
}

// Map the index of a byte to what it would be if each struct element was byte swapped
fn pixelByteSwappedIndex(storage: color.PixelStorage, index: usize) usize {
    return switch (storage) {
        .invalid => index,
        inline .indexed1, .indexed2, .indexed4, .indexed8, .indexed16 => |data| byteSwappedIndex(@typeInfo(@TypeOf(data.indices)).Pointer.child, index),
        inline else => |data| byteSwappedIndex(@typeInfo(@TypeOf(data)).Pointer.child, index),
    };
}

// Map the index of a byte to what it would be if each struct element was byte swapped
fn byteSwappedIndex(comptime T: type, byte_index: usize) usize {
    const element_index = byte_index / @sizeOf(T);
    const element_offset = element_index * @sizeOf(T);
    const index = byte_index % @sizeOf(T);
    switch (@typeInfo(T)) {
        .Int => {
            if (@sizeOf(T) == 1) return byte_index;
            return element_offset + @sizeOf(T) - 1 - index;
        },
        .Struct => |info| {
            inline for (info.fields) |field| {
                if (index >= @offsetOf(T, field.name) or index <= @offsetOf(T, field.name) + @sizeOf(field.type)) {
                    if (@sizeOf(field.type) == 1) return byte_index;
                    return element_offset + @sizeOf(field.type) - 1 - index;
                }
            }
        },
        else => @compileError("type " ++ @typeName(T) ++ " not supported"),
    }
}

fn filterChoiceHeuristic(scanline: color.PixelStorage, previous_scanline: ?color.PixelStorage) FilterType {
    const pixel_len = @as(PixelFormat, scanline).pixelStride();

    const filter_types = [_]FilterType{ .none, .sub, .up, .average, .paeth };

    var previous_bytes: [filter_types.len]u8 = [_]u8{0} ** filter_types.len;
    var combos: [filter_types.len]usize = [_]usize{0} ** filter_types.len;
    var scores: [filter_types.len]usize = [_]usize{0} ** filter_types.len;

    for (scanline.asBytes(), 0..) |sample, i| {
        const previous: u8 = if (i >= pixel_len) scanline.asBytes()[i - pixel_len] else 0;
        const above: u8 = if (previous_scanline) |b| b.asBytes()[i] else 0;
        const above_previous = if (previous_scanline) |b| (if (i >= pixel_len) b.asBytes()[i - pixel_len] else 0) else 0;

        inline for (filter_types, &previous_bytes, &combos, &scores) |filter_type, *previous_byte, *combo, *score| {
            const byte: u8 = switch (filter_type) {
                .none => sample,
                .sub => sample -% previous,
                .up => sample -% above,
                .average => sample -% average(previous, above),
                .paeth => sample -% paeth(previous, above, above_previous),
            };

            if (byte == previous_byte.*) {
                combo.* += 1;
            } else {
                score.* += combo.* * combo.*;
                combo.* = 0;
                previous_byte.* = byte;
            }
        }
    }

    var best: FilterType = .none;
    var max_score: usize = 0;
    inline for (filter_types, scores) |filter_type, score| {
        if (score > max_score) {
            max_score = score;
            best = filter_type;
        }
    }
    return best;
}

fn average(a: u9, b: u9) u8 {
    return @truncate((a + b) / 2);
}

fn paeth(b4: u8, up: u8, b4_up: u8) u8 {
    const p: i16 = @as(i16, @intCast(b4)) + up - b4_up;
    const pa = @abs(p - b4);
    const pb = @abs(p - up);
    const pc = @abs(p - b4_up);

    if (pa <= pb and pa <= pc) {
        return b4;
    } else if (pb <= pc) {
        return up;
    } else {
        return b4_up;
    }
}

test "filtering 16-bit grayscale pixels uses correct endianess" {
    var output_bytes = std.ArrayList(u8).init(std.testing.allocator);
    defer output_bytes.deinit();

    const pixels = try std.testing.allocator.dupe(color.Grayscale16, &.{
        .{ .value = 0xF },
        .{ .value = 0xFF },
        .{ .value = 0xFFF },
        .{ .value = 0xFFFF },
        .{ .value = 0xF },
        .{ .value = 0xFF },
        .{ .value = 0xFFF },
        .{ .value = 0xFFFF },
    });
    defer std.testing.allocator.free(pixels);

    // We specify the endianess as none to simplify the test
    try filter(output_bytes.writer(), .{ .grayscale16 = pixels }, .{ .specified = .none }, .{
        .width = 4,
        .height = 2,
        .bit_depth = 16,
        .color_type = .grayscale,
        .compression_method = .deflate,
        .filter_method = .adaptive,
        .interlace_method = .none,
    });

    try std.testing.expectEqualSlices(u8, &.{
        0x00, 0x00, 0x0F, 0x00, 0xFF, 0x0F, 0xFF, 0xFF, 0xFF, //
        0x00, 0x00, 0x0F, 0x00, 0xFF, 0x0F, 0xFF, 0xFF, 0xFF, //
    }, output_bytes.items);
}
