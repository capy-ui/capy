const std = @import("std");
const ImageData = @import("image.zig").ImageData;
const Allocator = std.mem.Allocator;

pub const PngError = error {
    InvalidHeader,
    InvalidFilter,
    UnsupportedFormat
};

const ChunkStream = std.io.FixedBufferStream([]u8);

// PNG files are made of chunks which have this structure:
const Chunk = struct {
    length: u32,
    type: []const u8,
    data: []const u8,
    stream: ChunkStream,
    crc: u32,
    allocator: *Allocator,

    pub fn deinit(self: *const Chunk) void {
        self.allocator.free(self.type);
        self.allocator.free(self.data);
    }

    // fancy Zig reflection for basically loading the chunk into a struct
    // for the experienced: this method is necessary instead of a simple @bitCast because of endianess, as
    // PNG uses big-endian.
    pub fn toStruct(self: *Chunk, comptime T: type) T {
        var result: T = undefined;
        var reader = self.stream.reader();
        inline for (@typeInfo(T).Struct.fields) |field| {
            const fieldInfo = @typeInfo(field.field_type);
            switch (fieldInfo) {
                .Int => {
                    const f = reader.readIntBig(field.field_type) catch unreachable;
                    @field(result, field.name) = f;
                },
                .Enum => |e| {
                    const id = reader.readIntBig(e.tag_type) catch unreachable;
                    @field(result, field.name) = @intToEnum(field.field_type, id);
                },
                else => unreachable
            }
        }
        return result;
    }
};

const ColorType = enum(u8) {
    Greyscale = 0,
    Truecolor = 2,
    IndexedColor = 3,
    GreyscaleAlpha = 4,
    TruecolorAlpha = 6
};

const CompressionMethod = enum(u8) {
    Deflate = 0,
};

// Struct for the IHDR chunk, which contains most of metadata about the image.
const IHDR = struct {
    width: u32,
    height: u32,
    bitDepth: u8,
    colorType: ColorType,
    compressionMethod: CompressionMethod,
    filterMethod: u8,
    interlaceMethod: u8
};

fn filterNone(image: []const u8, line: []u8, y: u32, start: usize, bytes: u8) callconv(.Inline) void {
    // line is already pre-filled with original data, so nothing to do
    _ = image; _ = line; _ = y; _ = start; _ = bytes;
}

fn filterSub(image: []const u8, line: []u8, y: u32, start: usize, bytes: u8) callconv(.Inline) void {
    _ = image; _ = y; _ = start;
    var pos: usize = bytes;
    while (pos < line.len) : (pos += 1) {
        line[pos] = line[pos] +% line[pos-bytes];
    }
}

fn filterUp(image: []const u8, line: []u8, y: u32, start: usize, bytes: u8) callconv(.Inline) void {
    _ = y; _ = bytes;
    const width = line.len;
    if (y != 0) {
        var pos: usize = 0;
        while (pos < line.len) : (pos += 1) {
            line[pos] = line[pos] +% image[start+pos-width];
        }
    }
}

fn filterAverage(image: []const u8, line: []u8, y: u32, start: usize, bytes: u8) callconv(.Inline) void {
    const width = line.len;
    var pos: usize = 0;
    while (pos < line.len) : (pos += 1) {
        var val: u9 = if (pos >= bytes) line[pos-bytes] else 0;
        if (y > 0) {
            val += image[pos+start-width]; // val = a + b
        }
        line[pos] = line[pos] +% @truncate(u8, val / 2);
    }
}

fn filterPaeth(image: []const u8, line: []u8, y: u32, start: usize, bytes: u8) callconv(.Inline) void {
    const width = line.len;
    var pos: usize = 0;
    while (pos < line.len) : (pos += 1) {
        const a: isize = if (pos >= bytes) line[pos-bytes] else 0;
        const b: isize = if (y > 0) image[pos+start-width] else 0;
        const c: isize = if (pos >= bytes and y > 0) image[pos+start-width-bytes] else 0;
        const p: isize = a + b - c;
        // the minimum value of p is -255, minus the maximum value of a/b/c, the minimum result is -510, so using unreachable is safe
        const pa = std.math.absInt(p - a) catch unreachable;
        const pb = std.math.absInt(p - b) catch unreachable;
        const pc = std.math.absInt(p - c) catch unreachable;

        if (pa <= pb and pa <= pc) {
            line[pos] = line[pos] +% @truncate(u8, @bitCast(usize, a));
        } else if (pb <= pc) {
            line[pos] = line[pos] +% @truncate(u8, @bitCast(usize, b));
        } else {
            line[pos] = line[pos] +% @truncate(u8, @bitCast(usize, c));
        }
    }
}

fn readChunk(allocator: *Allocator, reader: anytype) !Chunk {
    const length = try reader.readIntBig(u32);
    var chunkType = try allocator.alloc(u8, 4);
    _ = try reader.readAll(chunkType);
    var data = try allocator.alloc(u8, length);
    _ = try reader.readAll(data);

    const crc = try reader.readIntBig(u32);
    var stream = ChunkStream {
        .buffer = data,
        .pos = 0
    };

    return Chunk {
        .length = length,
        .type = chunkType,
        .data = data,
        .stream = stream,
        .crc = crc,
        .allocator = allocator
    };
}

pub fn read(allocator: *Allocator, unbufferedReader: anytype) !ImageData {
    var bufferedReader = std.io.BufferedReader(16*1024, @TypeOf(unbufferedReader)) { 
        .unbuffered_reader = unbufferedReader
    };
    const reader = bufferedReader.reader();

    var signature = reader.readBytesNoEof(8) catch return error.UnsupportedFormat;
    if (!std.mem.eql(u8, signature[0..], "\x89PNG\r\n\x1A\n")) {
        return error.UnsupportedFormat;
    }

    var ihdrChunk = try readChunk(allocator, reader);
    defer ihdrChunk.deinit();
    if (!std.mem.eql(u8, ihdrChunk.type, "IHDR")) {
        return error.InvalidHeader; // first chunk must ALWAYS be IHDR
    }
    const ihdr = ihdrChunk.toStruct(IHDR);

    if (ihdr.filterMethod != 0) {
        // there's only one filter method declared in the PNG specification
        // the error falls under InvalidHeader because InvalidFilter is for
        // the per-scanline filter type.
        return error.InvalidHeader;
    }

    var idatData = try allocator.alloc(u8, 0);
    defer allocator.free(idatData);

    while (true) {
        const chunk = try readChunk(allocator, reader);
        defer chunk.deinit();

        if (std.mem.eql(u8, chunk.type, "IEND")) {
            break;
        } else if (std.mem.eql(u8, chunk.type, "IDAT")) { // image data
            const pos = idatData.len;
            // in PNG files, there can be multiple IDAT chunks, and their data must all be concatenated.
            idatData = try allocator.realloc(idatData, idatData.len + chunk.data.len);
            std.mem.copy(u8, idatData[pos..], chunk.data);
        }
    }

    // the following lines create a zlib stream over our concatenated data from IDAT chunks.
    var idatStream = std.io.fixedBufferStream(idatData);
    var zlibStream = try std.compress.zlib.zlibStream(allocator, idatStream.reader());
    defer zlibStream.deinit();
    var zlibReader = zlibStream.reader();
    var idatBuffer = (std.io.BufferedReader(64*1024, @TypeOf(zlibReader)) { 
        .unbuffered_reader = zlibReader
    });
    const idatReader = idatBuffer.reader();

    // allocate image data (TODO: support more than RGB)
    var bpp: u32 = 3;
    if (ihdr.colorType == .TruecolorAlpha) {
        bpp = 4;
    }
    const imageData = try allocator.alloc(u8, ihdr.width*ihdr.height*bpp);
    var y: u32 = 0;

    const Filter = fn(image: []const u8, line: []u8, y: u32, start: usize, bytes: u8) callconv(.Inline) void;
    const filters = [_]Filter {filterNone, filterSub, filterUp, filterAverage, filterPaeth};

    if (ihdr.colorType == .Truecolor) {
        const bytesPerLine = ihdr.width * bpp;

        while (y < ihdr.height) {
            var x: u32 = 0;
            _ = x;
            // in PNG files, each scanlines have a filter, it is used to have more efficient compression.
            const filterType = try idatReader.readByte();
            const offset = y*bytesPerLine;
            var line = imageData[offset..offset+bytesPerLine];
            _ = try idatReader.readAll(line);

            if (filterType >= filters.len) {
                return error.InvalidFilter;
            }

            inline for (filters) |filter, i| {
                if (filterType == i) {
                    filter(imageData, line, y, offset, 3);
                }
            }
            
            y += 1;
        }

        return ImageData.fromBytes(ihdr.width, ihdr.height, bytesPerLine, .RGB, imageData);
    } else if (ihdr.colorType == .TruecolorAlpha and false) {
        const bytesPerLine = ihdr.width * bpp;
        var line = try allocator.alloc(u8, bytesPerLine);
        defer allocator.free(line);
        while (y < ihdr.height) {
            var x: u32 = 0;
            _ = x;
            const filterType = try idatReader.readByte();
            const offset = y*bytesPerLine;
            _ = try idatReader.readAll(line);

            if (filterType >= filters.len) {
                return error.InvalidFilter;
            }
            inline for (filters) |filter, i| {
                if (filterType == i) {
                    filter(imageData, line, y, offset, 4);
                    std.mem.copy(u8, imageData[offset..offset+bytesPerLine], line);
                }
            }
            y += 1;
        }

        return ImageData.fromBytes(ihdr.width, ihdr.height, ihdr.width, .RGBA, imageData);
    } else {
        std.log.scoped(.png).err("Unsupported PNG format: {}", .{ihdr.colorType});
        return PngError.UnsupportedFormat;
    }
}
