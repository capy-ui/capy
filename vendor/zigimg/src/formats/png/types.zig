const std = @import("std");
const utils = @import("../../utils.zig");
const color = @import("../../color.zig");
const PixelFormat = @import("../../pixel_format.zig").PixelFormat;
const Allocator = std.mem.Allocator;
const Colorf32 = color.Colorf32;

pub const magic_header = "\x89PNG\x0D\x0A\x1A\x0A";

pub const Chunk = struct {
    id: u32,
    name: *const [4:0]u8,

    pub fn init(name: *const [4:0]u8) Chunk {
        return .{ .name = name, .id = std.mem.bigToNative(u32, std.mem.bytesToValue(u32, name)) };
    }
};

pub const Chunks = struct {
    pub const IHDR = Chunk.init("IHDR");
    pub const PLTE = Chunk.init("PLTE");
    pub const IDAT = Chunk.init("IDAT");
    pub const IEND = Chunk.init("IEND");
    pub const gAMA = Chunk.init("gAMA");
    pub const sBIT = Chunk.init("sBIT");
    pub const tEXt = Chunk.init("tEXt");
    pub const zTXt = Chunk.init("zTXt");
    pub const iTXt = Chunk.init("iTXt");
    pub const cHRM = Chunk.init("cHRM");
    pub const pHYs = Chunk.init("pHYs");
    pub const tRNS = Chunk.init("tRNS");
    pub const bKGD = Chunk.init("bKGD");
    pub const tIME = Chunk.init("tIME");
    pub const iCCP = Chunk.init("iCCP");
    pub const sRGB = Chunk.init("sRGB");
    pub const Any = Chunk.init("_ANY");
};

pub const ColorType = enum(u8) {
    grayscale = 0,
    rgb_color = 2,
    indexed = 3,
    grayscale_alpha = 4,
    rgba_color = 6,

    const Self = @This();

    pub fn channelCount(self: Self) u8 {
        return switch (self) {
            .grayscale => 1,
            .rgb_color => 3,
            .indexed => 1,
            .grayscale_alpha => 2,
            .rgba_color => 4,
        };
    }

    pub fn fromPixelFormat(pixel_format: PixelFormat) !Self {
        return switch (pixel_format) {
            .rgb24, .rgb48 => .rgb_color,

            .rgba32, .rgba64 => .rgba_color,

            .grayscale1, .grayscale2, .grayscale4, .grayscale8, .grayscale16 => .grayscale,

            .grayscale8Alpha, .grayscale16Alpha => .grayscale_alpha,

            .indexed1, .indexed2, .indexed4, .indexed8 => .indexed,

            else => return error.Unsupported,
        };
    }
};

pub const FilterType = enum(u8) {
    none = 0,
    sub = 1,
    up = 2,
    average = 3,
    paeth = 4,
};

pub const InterlaceMethod = enum(u8) {
    none = 0,
    adam7 = 1,
};

/// The compression methods supported by PNG
pub const CompressionMethod = enum(u8) { deflate = 0, _ };

/// The filter methods supported by PNG
pub const FilterMethod = enum(u8) { adaptive = 0, _ };

pub const ChunkHeader = extern struct {
    length: u32 align(1),
    type: u32 align(1),

    const Self = @This();

    pub fn name(self: *Self) []const u8 {
        return std.mem.asBytes(&self.type);
    }
};

pub const HeaderData = extern struct {
    width: u32 align(1),
    height: u32 align(1),
    bit_depth: u8,
    color_type: ColorType,
    compression_method: CompressionMethod,
    filter_method: FilterMethod,
    interlace_method: InterlaceMethod,

    const Self = @This();

    pub fn isValid(self: *const Self) bool {
        const max_dim = std.math.maxInt(u32) >> 1;
        const w = self.width;
        const h = self.height;
        if (w == 0 or w > max_dim) return false;
        if (h == 0 or h > max_dim) return false;

        const bd = self.bit_depth;
        return switch (self.color_type) {
            .grayscale => bd == 1 or bd == 2 or bd == 4 or bd == 8 or bd == 16,
            .indexed => bd == 1 or bd == 2 or bd == 4 or bd == 8,
            else => bd == 8 or bd == 16,
        };
    }

    pub fn allowsPalette(self: *const Self) bool {
        return self.color_type == .indexed or
            self.color_type == .rgb_color or
            self.color_type == .rgba_color;
    }

    pub fn maxPaletteSize(self: *const Self) u16 {
        return if (self.bit_depth > 8) 256 else @as(u16, 1) << @truncate(u4, self.bit_depth);
    }

    pub fn channelCount(self: *const Self) u8 {
        return switch (self.color_type) {
            .grayscale => 1,
            .rgb_color => 3,
            .indexed => 1,
            .grayscale_alpha => 2,
            .rgba_color => 4,
        };
    }

    pub fn pixelBits(self: *const Self) u8 {
        return self.bit_depth * self.channelCount();
    }

    pub fn lineBytes(self: *const Self) u32 {
        return (self.pixelBits() * self.width + 7) / 8;
    }

    pub fn getPixelFormat(self: *const Self) PixelFormat {
        return switch (self.color_type) {
            .grayscale => switch (self.bit_depth) {
                1 => PixelFormat.grayscale1,
                2 => PixelFormat.grayscale2,
                4 => PixelFormat.grayscale4,
                8 => PixelFormat.grayscale8,
                16 => PixelFormat.grayscale16,
                else => unreachable,
            },
            .rgb_color => switch (self.bit_depth) {
                8 => PixelFormat.rgb24,
                16 => PixelFormat.rgb48,
                else => unreachable,
            },
            .indexed => switch (self.bit_depth) {
                1 => PixelFormat.indexed1,
                2 => PixelFormat.indexed2,
                4 => PixelFormat.indexed4,
                8 => PixelFormat.indexed8,
                else => unreachable,
            },
            .grayscale_alpha => switch (self.bit_depth) {
                8 => PixelFormat.grayscale8Alpha,
                16 => PixelFormat.grayscale16Alpha,
                else => unreachable,
            },
            .rgba_color => switch (self.bit_depth) {
                8 => PixelFormat.rgba32,
                16 => PixelFormat.rgba64,
                else => unreachable,
            },
        };
    }
};
