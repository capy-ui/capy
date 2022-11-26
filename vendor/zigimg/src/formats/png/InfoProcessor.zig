const std = @import("std");
const Image = @import("../../Image.zig");
const png_reader = @import("reader.zig");
const png = @import("types.zig");
const PixelFormat = @import("../../pixel_format.zig").PixelFormat;
const ReaderProcessor = png_reader.ReaderProcessor;
const ChunkProcessData = png_reader.ChunkProcessData;
const PaletteProcessData = png_reader.PaletteProcessData;
const isChunkCritical = png_reader.isChunkCritical;

pub const PngInfoOptions = struct {
    processor: Self,
    processors: [1]png_reader.ReaderProcessor = undefined,
    tmp_buffer: [png_reader.required_temp_bytes]u8 = undefined,
    fb_allocator: std.heap.FixedBufferAllocator = undefined,

    pub fn get(self: *@This()) png_reader.ReaderOptions {
        self.fb_allocator = std.heap.FixedBufferAllocator.init(self.tmp_buffer[0..]);
        self.processors[0] = self.processor.processor();
        return .{ .temp_allocator = self.fb_allocator.allocator(), .processors = self.processors[0..] };
    }
};

const Self = @This();

writer: std.io.StreamSource.Writer,
idat_count: u32 = 0,
idat_size: u64 = 0,

pub fn init(writer: std.io.StreamSource.Writer) Self {
    return .{ .writer = writer };
}

pub fn processor(self: *Self) ReaderProcessor {
    return ReaderProcessor.init(
        png.Chunks.Any.id,
        self,
        processChunk,
        processPalette,
        null,
    );
}

fn processChunk(self: *Self, data: *ChunkProcessData) Image.ReadError!PixelFormat {
    // This is critical chunk so it is already read and there is no need to read it here
    var result_format = data.current_format;

    var reader = data.stream.reader();
    var buffer: [1024]u8 = undefined;

    if (!isChunkCritical(data.chunk_id)) {
        switch (data.chunk_id) {
            png.Chunks.gAMA.id => {
                if (data.chunk_length != 4) {
                    try data.stream.seekBy(data.chunk_length);
                    self.writer.print("gAMA: Invalid Length {}\n", .{data.chunk_length}) catch return result_format;
                } else {
                    var gama = try reader.readIntBig(u32);
                    self.writer.print("gAMA: {}\n", .{gama}) catch return result_format;
                }
            },
            png.Chunks.sBIT.id => {
                if (data.chunk_length > 4) {
                    try data.stream.seekBy(data.chunk_length);
                    self.writer.print("sBIT: Invalid length {}\n", .{data.chunk_length}) catch return result_format;
                } else {
                    var vals = buffer[0..data.chunk_length];
                    try reader.readNoEof(vals);
                    self.writer.print("sBIT (significant bits): ", .{}) catch return result_format;
                    switch (data.chunk_length) {
                        1 => self.writer.print("Grayscale => {}\n", .{vals[0]}) catch return result_format,
                        2 => self.writer.print("Grayscale => {}, A => {}\n", .{ vals[0], vals[1] }) catch return result_format,
                        3 => self.writer.print("R => {}, G => {}, B => {}\n", .{ vals[0], vals[1], vals[2] }) catch return result_format,
                        4 => self.writer.print("R => {}, G => {}, B => {}, A => {}\n", .{ vals[0], vals[1], vals[2], vals[3] }) catch return result_format,
                        else => self.writer.print("Invalid length {}\n", .{data.chunk_length}) catch return result_format,
                    }
                }
            },
            png.Chunks.tEXt.id => {
                var to_read = if (data.chunk_length <= buffer.len) data.chunk_length else buffer.len;
                var txt = buffer[0..to_read];
                try reader.readNoEof(txt);
                if (data.chunk_length > buffer.len) try data.stream.seekBy(@as(i64, data.chunk_length) - buffer.len);
                self.writer.print("tEXt Length {s}:\n", .{std.fmt.fmtIntSizeBin(data.chunk_length)}) catch return result_format;
                var strEnd = std.mem.indexOfScalar(u8, txt, 0).?;
                self.writer.print("               Keyword: {s}\n", .{txt[0..strEnd]}) catch return result_format;
                txt = txt[strEnd + 1 ..];
                self.writer.print("                  Text: {s}\n", .{txt[0..]}) catch return result_format;
            },
            png.Chunks.zTXt.id => {
                const to_read = if (data.chunk_length > 81) 81 else data.chunk_length;
                var txt = buffer[0..to_read];
                try reader.readNoEof(txt);
                self.writer.print("zTXt Length {s}:\n", .{std.fmt.fmtIntSizeBin(data.chunk_length)}) catch return result_format;
                var strEnd = std.mem.indexOfScalar(u8, txt, 0).?;
                self.writer.print("               Keyword: {s}\n", .{txt[0..strEnd]}) catch return result_format;
                if (txt[strEnd + 1] == 0) {
                    self.writer.print("           Compression: Zlib Deflate\n", .{}) catch return result_format;
                    self.writer.print("                  Text: ", .{}) catch return result_format;
                    try data.stream.seekBy(@intCast(i64, strEnd) + 2 - to_read);
                    var decompressStream = std.compress.zlib.zlibStream(data.temp_allocator, reader) catch return error.InvalidData;
                    var print_buf: [1024]u8 = undefined;
                    var got = decompressStream.read(print_buf[0..]) catch return error.InvalidData;
                    while (got > 0) {
                        self.writer.print("{s}", .{print_buf[0..got]}) catch return result_format;
                        got = decompressStream.read(print_buf[0..]) catch return error.InvalidData;
                    }
                    self.writer.print("\n", .{}) catch return result_format;
                } else {
                    self.writer.print("           Compression: Unknown\n", .{}) catch return result_format;
                }
            },
            png.Chunks.iTXt.id => {
                var to_read = if (data.chunk_length <= buffer.len) data.chunk_length else buffer.len;
                var txt = buffer[0..to_read];
                try reader.readNoEof(txt);
                if (data.chunk_length > buffer.len) try data.stream.seekBy(@as(i64, data.chunk_length) - buffer.len);
                self.writer.print("iTXt Length {s}:\n", .{std.fmt.fmtIntSizeBin(data.chunk_length)}) catch return result_format;
                var strEnd = std.mem.indexOfScalar(u8, txt, 0).?;
                self.writer.print("               Keyword: {s}\n", .{txt[0..strEnd]}) catch return result_format;
                txt = txt[strEnd + 1 ..];
                if (txt[0] == 1) {
                    self.writer.print("            Compressed: {s}\n", .{if (txt[1] == 0) "Zlib Deflate  " else "Unknown Method"}) catch return result_format;
                } else {
                    self.writer.print("            Compressed: No\n", .{}) catch return result_format;
                }
                txt = txt[2..];
                strEnd = std.mem.indexOfScalar(u8, txt, 0).?;
                self.writer.print("          Language Tag: {s}\n", .{txt[0..strEnd]}) catch return result_format;
                txt = txt[strEnd + 1 ..];
                strEnd = std.mem.indexOfScalar(u8, txt, 0).?;
                self.writer.print("    Translated Keyword: {s}\n", .{txt[0..strEnd]}) catch return result_format;
                txt = txt[strEnd + 1 ..];
                self.writer.print("                  Text: {s}\n", .{txt[0..]}) catch return result_format;
            },
            png.Chunks.cHRM.id => {
                if (data.chunk_length != 32) {
                    try data.stream.seekBy(data.chunk_length);
                    self.writer.print("cHRM: Invalid Length {}\n", .{data.chunk_length}) catch return result_format;
                } else {
                    self.writer.print("cHRM:\n", .{}) catch return result_format;
                    var x = try reader.readIntBig(u32);
                    var y = try reader.readIntBig(u32);
                    self.writer.print("    White x,y: {}, {}\n", .{ x, y }) catch return result_format;
                    x = try reader.readIntBig(u32);
                    y = try reader.readIntBig(u32);
                    self.writer.print("      Red x,y: {}, {}\n", .{ x, y }) catch return result_format;
                    x = try reader.readIntBig(u32);
                    y = try reader.readIntBig(u32);
                    self.writer.print("    Green x,y: {}, {}\n", .{ x, y }) catch return result_format;
                    x = try reader.readIntBig(u32);
                    y = try reader.readIntBig(u32);
                    self.writer.print("     Blue x,y: {}, {}\n", .{ x, y }) catch return result_format;
                }
            },
            png.Chunks.pHYs.id => {
                if (data.chunk_length != 9) {
                    try data.stream.seekBy(data.chunk_length);
                    self.writer.print("pHYs: Invalid Length {}\n", .{data.chunk_length}) catch return result_format;
                } else {
                    self.writer.print("pHYs: ", .{}) catch return result_format;
                    var x = try reader.readIntBig(u32);
                    var y = try reader.readIntBig(u32);
                    self.writer.print("{} x {}", .{ x, y }) catch return result_format;
                    if ((try reader.readIntBig(u8)) == 1) {
                        self.writer.print(" metres\n", .{}) catch return result_format;
                    } else {
                        self.writer.print("\n", .{}) catch return result_format;
                    }
                }
            },
            png.Chunks.tRNS.id => {
                self.writer.print("tRNS Length {s}: ", .{std.fmt.fmtIntSizeBin(data.chunk_length)}) catch return result_format;
                if (data.chunk_length == 2 and data.header.color_type != .indexed) {
                    var val = try reader.readIntBig(u16);
                    self.writer.print("{}\n", .{val}) catch return result_format;
                } else if (data.chunk_length == 6 and data.header.color_type != .indexed) {
                    var r = try reader.readIntBig(u16);
                    var g = try reader.readIntBig(u16);
                    var b = try reader.readIntBig(u16);
                    self.writer.print("RGB {}, {}, {}\n", .{ r, g, b }) catch return result_format;
                } else {
                    const to_print = if (data.chunk_length > 20) 20 else data.chunk_length;
                    var vals = buffer[0..to_print];
                    try reader.readNoEof(vals);
                    self.writer.print("{d}", .{vals}) catch return result_format;
                    if (data.chunk_length > 20) {
                        self.writer.print(" ...\n", .{}) catch return result_format;
                        try data.stream.seekBy(data.chunk_length - 20);
                    } else self.writer.print("\n", .{}) catch return result_format;
                }
            },
            png.Chunks.bKGD.id => {
                self.writer.print("bKGD Length {s}: ", .{std.fmt.fmtIntSizeBin(data.chunk_length)}) catch return result_format;
                if (data.chunk_length == 1) {
                    var val = try reader.readIntBig(u8);
                    self.writer.print("Index {}\n", .{val}) catch return result_format;
                } else if (data.chunk_length == 2) {
                    var val = try reader.readIntBig(u16);
                    self.writer.print("{}\n", .{val}) catch return result_format;
                } else if (data.chunk_length == 6) {
                    var r = try reader.readIntBig(u16);
                    var g = try reader.readIntBig(u16);
                    var b = try reader.readIntBig(u16);
                    self.writer.print("RGB {}, {}, {}\n", .{ r, g, b }) catch return result_format;
                } else {
                    self.writer.print("Invalid Length\n", .{}) catch return result_format;
                    try data.stream.seekBy(data.chunk_length);
                }
            },
            png.Chunks.tIME.id => {
                if (data.chunk_length != 7) {
                    try data.stream.seekBy(data.chunk_length);
                    self.writer.print("tIME: Invalid Length {}: ", .{data.chunk_length}) catch return result_format;
                } else {
                    self.writer.print("tIME: ", .{}) catch return result_format;
                    var year = try reader.readIntBig(u16);
                    var rest = buffer[0 .. data.chunk_length - 2];
                    try reader.readNoEof(rest);
                    self.writer.print("{}-{}-{} {}:{}:{}\n", .{ year, rest[0], rest[1], rest[2], rest[3], rest[4] }) catch return result_format;
                }
            },
            png.Chunks.iCCP.id => {
                if (data.chunk_length > buffer.len) {
                    try data.stream.seekBy(data.chunk_length);
                    self.writer.print("iCCP: Invalid Length {}: ", .{data.chunk_length}) catch return result_format;
                } else {
                    self.writer.print("iCCP Length {s}: ", .{std.fmt.fmtIntSizeBin(data.chunk_length)}) catch return result_format;

                    var iccp = buffer[0..data.chunk_length];
                    try reader.readNoEof(iccp);
                    if (std.mem.indexOfScalar(u8, iccp, 0)) |str_end| {
                        self.writer.print("Profile Name: {s}\n", .{iccp[0..str_end]}) catch return result_format;
                    } else {
                        self.writer.print("Invalid Data\n", .{}) catch return result_format;
                    }
                }
            },
            png.Chunks.sRGB.id => {
                if (data.chunk_length != 1) {
                    try data.stream.seekBy(data.chunk_length);
                    self.writer.print("sRGB: Invalid Length {}: ", .{data.chunk_length}) catch return result_format;
                } else {
                    self.writer.print("sRGB: ", .{}) catch return result_format;
                    var srgb = try reader.readByte();
                    switch (srgb) {
                        0 => self.writer.print("Perceptual\n", .{}) catch return result_format,
                        1 => self.writer.print("Relative colorimetric\n", .{}) catch return result_format,
                        2 => self.writer.print("Saturation\n", .{}) catch return result_format,
                        3 => self.writer.print("Absolute colorimetric\n", .{}) catch return result_format,
                        else => self.writer.print("Uknown Intent\n", .{}) catch return result_format,
                    }
                }
            },
            else => {
                try data.stream.seekBy(data.chunk_length);
                var chunk_name = std.mem.bigToNative(u32, data.chunk_id);
                self.writer.print("{s} Length {s}\n", .{ std.mem.asBytes(&chunk_name), std.fmt.fmtIntSizeBin(data.chunk_length) }) catch return result_format;
            },
        }
        try data.stream.seekBy(@sizeOf(u32));
    } else if (data.chunk_id == png.Chunks.IHDR.id) {
        self.writer.print("Dimensions: {}x{}\n", .{ data.header.width, data.header.height }) catch return result_format;
        self.writer.print("Bit Depth: {}\n", .{data.header.bit_depth}) catch return result_format;
        self.writer.print("Color Type: {s}\n", .{@tagName(data.header.color_type)}) catch return result_format;
        self.writer.print("Compression Method: {s}\n", .{@tagName(data.header.compression_method)}) catch return result_format;
        self.writer.print("Filter Method: {s}\n", .{@tagName(data.header.filter_method)}) catch return result_format;
        self.writer.print("Interlace Method: {s}\n\n", .{@tagName(data.header.interlace_method)}) catch return result_format;
    } else if (data.chunk_id == png.Chunks.IDAT.id) {
        self.idat_count += 1;
        self.idat_size += data.chunk_length;
    } else if (data.chunk_id == png.Chunks.IEND.id) {
        self.writer.print("IDAT Count: {}, Total Size: {s}\n", .{ self.idat_count, std.fmt.fmtIntSizeBin(self.idat_size) }) catch return result_format;
        self.writer.print("────────────────────────────────────────────────\n", .{}) catch return result_format;
    }

    return result_format;
}

fn processPalette(self: *Self, data: *PaletteProcessData) Image.ReadError!void {
    self.writer.print("PLTE with {} entries\n", .{data.palette.len}) catch return;
}
