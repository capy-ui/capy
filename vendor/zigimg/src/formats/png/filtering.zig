const std = @import("std");
const color = @import("../../color.zig");
const PixelFormat = @import("../../pixel_format.zig").PixelFormat;
const Image = @import("../../Image.zig");
const HeaderData = @import("types.zig").HeaderData;

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
    var scanline: []const u8 = undefined;
    var previous_scanline: ?[]const u8 = null;

    const format: PixelFormat = pixels;

    if (format.bitsPerChannel() < 8)
        return Image.WriteError.Unsupported;

    const pixel_len = format.pixelStride();

    const scanline_len = header.lineBytes();

    var y: usize = 0;
    while (y < header.height) : (y += 1) {
        scanline = pixels.asBytes()[(y * scanline_len)..((y + 1) * scanline_len)];

        const filter_type: FilterType = switch (filter_choice) {
            .try_all => @panic("Unimplemented"),
            .heuristic => filterChoiceHeuristic(scanline, previous_scanline, pixel_len),
            .specified => |f| f,
        };

        try writer.writeByte(@enumToInt(filter_type));

        for (scanline) |sample, i| {
            const previous: u8 = if (i >= pixel_len) scanline[i - pixel_len] else 0;
            const above: u8 = if (previous_scanline) |b| b[i] else 0;
            const above_previous = if (previous_scanline) |b| (if (i >= pixel_len) b[i - pixel_len] else 0) else 0;

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

fn filterChoiceHeuristic(scanline: []const u8, previous_scanline: ?[]const u8, pixel_len: u8) FilterType {
    var max_score: usize = 0;
    var best: FilterType = .none;
    inline for ([_]FilterType{ .none, .sub, .up, .average, .paeth }) |filter_type| {
        var previous_byte: u8 = 0;
        var combo: usize = 0;
        var score: usize = 0;

        for (scanline) |sample, i| {
            const previous: u8 = if (i >= pixel_len) scanline[i - pixel_len] else 0;
            const above: u8 = if (previous_scanline) |b| b[i] else 0;
            const above_previous = if (previous_scanline) |b| (if (i >= pixel_len) b[i - pixel_len] else 0) else 0;

            const byte: u8 = switch (filter_type) {
                .none => sample,
                .sub => sample -% previous,
                .up => sample -% above,
                .average => sample -% average(previous, above),
                .paeth => sample -% paeth(previous, above, above_previous),
            };

            if (byte == previous_byte) {
                combo += 1;
            } else {
                score += combo * combo;
                combo = 0;
                previous_byte = byte;
            }
        }

        if (score > max_score) {
            max_score = score;
            best = filter_type;
        }
    }
    return best;
}

fn average(a: u9, b: u9) u8 {
    return @truncate(u8, (a + b) / 2);
}

fn paeth(b4: u8, up: u8, b4_up: u8) u8 {
    const p: i16 = @intCast(i16, b4) + up - b4_up;
    const pa = std.math.absInt(p - b4) catch unreachable;
    const pb = std.math.absInt(p - up) catch unreachable;
    const pc = std.math.absInt(p - b4_up) catch unreachable;

    if (pa <= pb and pa <= pc) {
        return b4;
    } else if (pb <= pc) {
        return up;
    } else {
        return b4_up;
    }
}
