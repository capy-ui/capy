const std = @import("std");
const utils = @import("../../utils.zig");
const png = @import("types.zig");
const color = @import("../../color.zig");
const PixelStorage = color.PixelStorage;
const PixelFormat = @import("../../pixel_format.zig").PixelFormat;
const Image = @import("../../Image.zig");
const mem = std.mem;
const File = std.fs.File;
const Crc32 = std.hash.Crc32;
const Allocator = std.mem.Allocator;

// Png specification: http://www.libpng.org/pub/png/spec/iso/index-object.html

pub fn isChunkCritical(id: u32) bool {
    return (id & 0x20000000) == 0;
}

fn callChunkProcessors(processors: []ReaderProcessor, chunk_process_data: *ChunkProcessData) Image.ReadError!void {
    const id = chunk_process_data.chunk_id;
    // Critical chunks are already processed but we can still notify any number of processors about them
    var processed = isChunkCritical(id);
    for (processors) |*processor| {
        if (processor.id == id or processor.id == png.Chunks.Any.id) {
            const new_format = try processor.processChunk(chunk_process_data);
            std.debug.assert(new_format.pixelStride() >= chunk_process_data.current_format.pixelStride());
            chunk_process_data.current_format = new_format;
            if (!processed) {
                // For non critical chunks we only allow one processor so we break after the first one
                processed = true;
                break;
            }
        }
    }

    // If noone loaded this chunk we need to skip over it
    if (!processed) {
        try chunk_process_data.stream.seekBy(@intCast(i64, chunk_process_data.chunk_length + 4));
    }
}

// Provides reader interface for Zlib stream that knows to read consecutive IDAT chunks.
// The way Zlib is currently implemented it very often reads a byte at a time which is
// slow so we also provide buffering here. We can't used BufferedReader because we need
// more control than it currently provides.
const IDatChunksReader = struct {
    stream: *Image.Stream,
    buffer: [4096]u8 = undefined,
    data: []u8,
    processors: []ReaderProcessor,
    chunk_process_data: *ChunkProcessData,
    remaining_chunk_length: u32,
    crc: Crc32,

    const Self = @This();

    fn init(
        stream: *Image.Stream,
        processors: []ReaderProcessor,
        chunk_process_data: *ChunkProcessData,
    ) Self {
        var crc = Crc32.init();
        crc.update(png.Chunks.IDAT.name);
        return .{
            .stream = stream,
            .data = &[_]u8{},
            .processors = processors,
            .chunk_process_data = chunk_process_data,
            .remaining_chunk_length = chunk_process_data.chunk_length,
            .crc = crc,
        };
    }

    fn fillBuffer(self: *Self, to_read: usize) Image.ReadError!usize {
        std.mem.copy(u8, self.buffer[0..self.data.len], self.data);
        var new_start = self.data.len;
        var max = self.buffer.len;
        if (max - new_start > self.remaining_chunk_length) {
            max = new_start + self.remaining_chunk_length;
        }
        const len = try self.stream.read(self.buffer[new_start..max]);
        self.data = self.buffer[new_start .. new_start + len];
        self.crc.update(self.data);
        return if (len < to_read) len else to_read;
    }

    fn read(self: *Self, dest: []u8) Image.ReadError!usize {
        if (self.remaining_chunk_length == 0) return 0;
        const new_dest = dest;

        var reader = self.stream.reader();
        var to_read = new_dest.len;
        if (to_read > self.remaining_chunk_length) {
            to_read = self.remaining_chunk_length;
        }
        if (to_read > self.data.len) {
            to_read = try self.fillBuffer(to_read);
        }
        std.mem.copy(u8, new_dest[0..to_read], self.data[0..to_read]);
        self.remaining_chunk_length -= @intCast(u32, to_read);
        self.data = self.data[to_read..];

        if (self.remaining_chunk_length == 0) {
            // First read and check CRC of just finished chunk
            const expected_crc = try reader.readIntBig(u32);
            if (self.crc.final() != expected_crc) {
                return Image.ReadError.InvalidData;
            }

            try callChunkProcessors(self.processors, self.chunk_process_data);

            self.crc = Crc32.init();
            self.crc.update(png.Chunks.IDAT.name);

            // Try to load the next IDAT chunk
            const chunk = try utils.readStructBig(reader, png.ChunkHeader);
            if (chunk.type == png.Chunks.IDAT.id) {
                self.remaining_chunk_length = chunk.length;
            } else {
                // Return to the start of the next chunk so code in main struct can read it
                try self.stream.seekBy(-@sizeOf(png.ChunkHeader));
            }
        }

        return to_read;
    }
};

const IDATReader = std.io.Reader(*IDatChunksReader, Image.ReadError, IDatChunksReader.read);

pub fn loadHeader(stream: *Image.Stream) Image.ReadError!png.HeaderData {
    var reader = stream.reader();
    var signature: [png.magic_header.len]u8 = undefined;
    try reader.readNoEof(signature[0..]);
    if (!mem.eql(u8, signature[0..], png.magic_header)) {
        return Image.ReadError.InvalidData;
    }

    const chunk = try utils.readStructBig(reader, png.ChunkHeader);
    if (chunk.type != png.Chunks.IHDR.id) return Image.ReadError.InvalidData;
    if (chunk.length != @sizeOf(png.HeaderData)) return Image.ReadError.InvalidData;

    var header_data: [@sizeOf(png.HeaderData)]u8 = undefined;
    try reader.readNoEof(&header_data);

    var struct_stream = Image.Stream{ .buffer = std.io.fixedBufferStream(&header_data) };

    const header = try utils.readStructBig(struct_stream.reader(), png.HeaderData);
    if (!header.isValid()) return Image.ReadError.InvalidData;

    const expected_crc = try reader.readIntBig(u32);
    var crc = Crc32.init();
    crc.update(png.Chunks.IHDR.name);
    crc.update(&header_data);
    const actual_crc = crc.final();
    if (expected_crc != actual_crc) return Image.ReadError.InvalidData;

    return header;
}

/// Loads the png image using the given allocator and options.
/// The options allow you to pass in a custom allocator for temporary allocations.
/// By default it will use a fixed buffer on stack for temporary allocations.
/// You can also pass in an array of chunk processors. You can use def_processors
/// array if you want to use these default set of processors:
/// 1. tRNS processor that decodes the tRNS chunk if it exists into an alpha channel
/// 2. PLTE processor that decodes the indexed image with a palette into a RGB image.
/// If you want default processors with default temp allocator you can just pass
/// predefined default_options. If you just pass .{} no processors will be used.
pub fn load(stream: *Image.Stream, allocator: Allocator, options: ReaderOptions) Image.ReadError!Image {
    const header = try loadHeader(stream);
    var result = Image.init(allocator);
    errdefer result.deinit();

    result.width = header.width;
    result.height = header.height;
    result.pixels = try loadWithHeader(stream, &header, allocator, options);

    return result;
}

/// Loads the png image for which the header has already been loaded.
/// For options param description look at the load method docs.
pub fn loadWithHeader(
    stream: *Image.Stream,
    header: *const png.HeaderData,
    allocator: Allocator,
    in_options: ReaderOptions,
) Image.ReadError!PixelStorage {
    var options = in_options;
    var temp_allocator = options.temp_allocator;
    var fb_allocator = std.heap.FixedBufferAllocator.init(try temp_allocator.alloc(u8, required_temp_bytes));
    defer temp_allocator.free(fb_allocator.buffer);
    options.temp_allocator = fb_allocator.allocator();

    var palette: []color.Rgb24 = &[_]color.Rgb24{};
    var data_found = false;
    var result: PixelStorage = undefined;

    var chunk_process_data = ChunkProcessData{
        .stream = stream,
        .chunk_id = png.Chunks.IHDR.id,
        .chunk_length = @sizeOf(png.HeaderData),
        .current_format = header.getPixelFormat(),
        .header = header,
        .temp_allocator = options.temp_allocator,
    };
    try callChunkProcessors(options.processors, &chunk_process_data);

    var reader = stream.reader();

    while (true) {
        const chunk = (try utils.readStructBig(reader, png.ChunkHeader));
        chunk_process_data.chunk_id = chunk.type;
        chunk_process_data.chunk_length = chunk.length;

        switch (chunk.type) {
            png.Chunks.IHDR.id => {
                return Image.ReadError.InvalidData; // We already processed IHDR so another one is an error
            },
            png.Chunks.IEND.id => {
                if (!data_found) return Image.ReadError.InvalidData;
                _ = try reader.readIntNative(u32); // Read and ignore the crc
                try callChunkProcessors(options.processors, &chunk_process_data);
                return result;
            },
            png.Chunks.IDAT.id => {
                if (data_found) return Image.ReadError.InvalidData;
                if (header.color_type == .indexed and palette.len == 0) {
                    return Image.ReadError.InvalidData;
                }
                result = try readAllData(stream, header, palette, allocator, &options, &chunk_process_data);
                data_found = true;
            },
            png.Chunks.PLTE.id => {
                if (!header.allowsPalette()) return Image.ReadError.InvalidData;
                if (palette.len > 0) return Image.ReadError.InvalidData;
                // We ignore if tRNS is already found
                if (data_found) {
                    // If IDAT was already processed we skip and ignore this palette
                    try stream.seekBy(chunk.length + @sizeOf(u32));
                } else {
                    if (chunk.length % 3 != 0) return Image.ReadError.InvalidData;
                    const palette_entries = chunk.length / 3;
                    if (palette_entries > header.maxPaletteSize()) {
                        return Image.ReadError.InvalidData;
                    }
                    palette = try options.temp_allocator.alloc(color.Rgb24, palette_entries);
                    var palette_bytes = mem.sliceAsBytes(palette);
                    try reader.readNoEof(palette_bytes);

                    const expected_crc = try reader.readIntBig(u32);
                    var crc = Crc32.init();
                    crc.update(png.Chunks.PLTE.name);
                    crc.update(palette_bytes);
                    const actual_crc = crc.final();
                    if (expected_crc != actual_crc) return Image.ReadError.InvalidData;
                    try callChunkProcessors(options.processors, &chunk_process_data);
                }
            },
            else => {
                try callChunkProcessors(options.processors, &chunk_process_data);
            },
        }
    }
}

fn readAllData(
    stream: *Image.Stream,
    header: *const png.HeaderData,
    palette: []color.Rgb24,
    allocator: Allocator,
    options: *const ReaderOptions,
    chunk_process_data: *ChunkProcessData,
) Image.ReadError!PixelStorage {
    const native_endian = comptime @import("builtin").cpu.arch.endian();
    const is_little_endian = native_endian == .Little;
    const width = header.width;
    const height = header.height;
    const channel_count = header.channelCount();
    const dest_format = chunk_process_data.current_format;
    var result = try PixelStorage.init(allocator, dest_format, width * height);
    errdefer result.deinit(allocator);
    var idat_chunks_reader = IDatChunksReader.init(stream, options.processors, chunk_process_data);
    var idat_reader: IDATReader = .{ .context = &idat_chunks_reader };
    var decompress_stream = std.compress.zlib.zlibStream(options.temp_allocator, idat_reader) catch return Image.ReadError.InvalidData;

    if (palette.len > 0) {
        var destination_palette = if (result.getPalette()) |result_palette|
            result_palette
        else
            try options.temp_allocator.alloc(color.Rgba32, palette.len);
        for (palette) |entry, n| {
            destination_palette[n] = color.Rgba32.initRgb(entry.r, entry.g, entry.b);
        }
        try callPaletteProcessors(options, destination_palette);
    }

    var destination = result.asBytes();

    // For defiltering we need to keep two rows in memory so we allocate space for that
    const filter_stride = (header.bit_depth + 7) / 8 * channel_count; // 1 to 8 bytes
    const line_bytes = header.lineBytes();
    const virtual_line_bytes = line_bytes + filter_stride;
    const result_line_bytes = @intCast(u32, destination.len / height);
    var tmpbytes = 2 * virtual_line_bytes;
    // For deinterlacing we also need one additional temporary row of resulting pixels
    if (header.interlace_method == .adam7) {
        tmpbytes += result_line_bytes;
    }
    var temp_allocator = if (tmpbytes < 128 * 1024) options.temp_allocator else allocator;
    var tmp_buffer = try temp_allocator.alloc(u8, tmpbytes);
    defer temp_allocator.free(tmp_buffer);
    mem.set(u8, tmp_buffer, 0);
    var prev_row = tmp_buffer[0..virtual_line_bytes];
    var current_row = tmp_buffer[virtual_line_bytes .. 2 * virtual_line_bytes];
    const pixel_stride = @intCast(u8, result_line_bytes / width);
    std.debug.assert(pixel_stride == dest_format.pixelStride());

    var process_row_data = RowProcessData{
        .dest_row = undefined,
        .src_format = header.getPixelFormat(),
        .dest_format = dest_format,
        .header = header,
        .temp_allocator = options.temp_allocator,
    };

    var decompress_reader = decompress_stream.reader();

    if (header.interlace_method == .none) {
        var i: u32 = 0;
        while (i < height) : (i += 1) {
            decompress_reader.readNoEof(current_row[filter_stride - 1 ..]) catch return Image.ReadError.InvalidData;
            try defilter(current_row, prev_row, filter_stride);

            process_row_data.dest_row = destination[0..result_line_bytes];
            destination = destination[result_line_bytes..];

            // Spreads the data into a destination format pixel stride so that all callRowProcessors methods can work in place
            spreadRowData(
                process_row_data.dest_row,
                current_row[filter_stride..],
                header.bit_depth,
                channel_count,
                pixel_stride,
                is_little_endian,
            );

            const result_format = try callRowProcessors(options.processors, &process_row_data);
            if (result_format != dest_format) return Image.ReadError.InvalidData;

            const tmp = prev_row;
            prev_row = current_row;
            current_row = tmp;
        }
    } else {
        const start_x = [7]u8{ 0, 4, 0, 2, 0, 1, 0 };
        const start_y = [7]u8{ 0, 0, 4, 0, 2, 0, 1 };
        const xinc = [7]u8{ 8, 8, 4, 4, 2, 2, 1 };
        const yinc = [7]u8{ 8, 8, 8, 4, 4, 2, 2 };
        const pass_width = [7]u32{
            (width + 7) / 8,
            (width + 3) / 8,
            (width + 3) / 4,
            (width + 1) / 4,
            (width + 1) / 2,
            width / 2,
            width,
        };
        const pass_height = [7]u32{
            (height + 7) / 8,
            (height + 7) / 8,
            (height + 3) / 8,
            (height + 3) / 4,
            (height + 1) / 4,
            (height + 1) / 2,
            height / 2,
        };
        const pixel_bits = header.pixelBits();
        const deinterlace_bit_depth: u8 = if (header.bit_depth <= 8) 8 else 16;
        var dest_row = tmp_buffer[virtual_line_bytes * 2 ..];

        var pass: u32 = 0;
        while (pass < 7) : (pass += 1) {
            if (pass_width[pass] == 0 or pass_height[pass] == 0) {
                continue;
            }
            const pass_bytes = (pixel_bits * pass_width[pass] + 7) / 8;
            const pass_length = pass_bytes + filter_stride;
            const result_pass_line_bytes = pixel_stride * pass_width[pass];
            const deinterlace_stride = xinc[pass] * pixel_stride;
            mem.set(u8, prev_row, 0);
            const destx = start_x[pass] * pixel_stride;
            var desty = start_y[pass];
            var y: u32 = 0;
            while (y < pass_height[pass]) : (y += 1) {
                decompress_reader.readNoEof(current_row[filter_stride - 1 .. pass_length]) catch return Image.ReadError.InvalidData;
                try defilter(current_row[0..pass_length], prev_row[0..pass_length], filter_stride);

                process_row_data.dest_row = dest_row[0..result_pass_line_bytes];

                // Spreads the data into a destination format pixel stride so that all callRowProcessors methods can work in place
                spreadRowData(
                    process_row_data.dest_row,
                    current_row[filter_stride..],
                    header.bit_depth,
                    channel_count,
                    pixel_stride,
                    is_little_endian,
                );

                const result_format = try callRowProcessors(options.processors, &process_row_data);
                if (result_format != dest_format) return Image.ReadError.InvalidData;

                const line_start_index = desty * result_line_bytes;
                const start_byte = line_start_index + destx;
                const end_byte = line_start_index + result_line_bytes;
                // This spread does the actual deinterlacing of the row
                spreadRowData(
                    destination[start_byte..end_byte],
                    process_row_data.dest_row,
                    deinterlace_bit_depth,
                    result_format.channelCount(),
                    deinterlace_stride,
                    false,
                );

                desty += yinc[pass];

                const tmp = prev_row;
                prev_row = current_row;
                current_row = tmp;
            }
        }
    }

    // Just make sure zip stream gets to its end
    var buf: [8]u8 = undefined;
    var shouldBeZero = decompress_stream.read(buf[0..]) catch return Image.ReadError.InvalidData;

    std.debug.assert(shouldBeZero == 0);

    return result;
}

fn callPaletteProcessors(options: *const ReaderOptions, palette: []color.Rgba32) Image.ReadError!void {
    var process_data = PaletteProcessData{ .palette = palette, .temp_allocator = options.temp_allocator };
    for (options.processors) |*processor| {
        try processor.processPalette(&process_data);
    }
}

fn defilter(current_row: []u8, prev_row: []u8, filter_stride: u8) Image.ReadError!void {
    const filter_byte = current_row[filter_stride - 1];
    if (filter_byte > @enumToInt(png.FilterType.paeth)) {
        return Image.ReadError.InvalidData;
    }
    const filter = @intToEnum(png.FilterType, filter_byte);
    current_row[filter_stride - 1] = 0;

    var x: u32 = filter_stride;
    switch (filter) {
        .none => {},
        .sub => while (x < current_row.len) : (x += 1) {
            current_row[x] +%= current_row[x - filter_stride];
        },
        .up => while (x < current_row.len) : (x += 1) {
            current_row[x] +%= prev_row[x];
        },
        .average => while (x < current_row.len) : (x += 1) {
            current_row[x] +%= @truncate(u8, (@intCast(u32, current_row[x - filter_stride]) + @intCast(u32, prev_row[x])) / 2);
        },
        .paeth => while (x < current_row.len) : (x += 1) {
            const a = current_row[x - filter_stride];
            const b = prev_row[x];
            const c = prev_row[x - filter_stride];
            var pa: i32 = @intCast(i32, b) - c;
            var pb: i32 = @intCast(i32, a) - c;
            var pc: i32 = pa + pb;
            if (pa < 0) pa = -pa;
            if (pb < 0) pb = -pb;
            if (pc < 0) pc = -pc;
            // zig fmt: off
            current_row[x] +%= if (pa <= pb and pa <= pc) a
                                else if (pb <= pc) b
                                else c;
            // zig fmt: on
        },
    }
}

fn spreadRowData(
    dest_row: []u8,
    current_row: []u8,
    bit_depth: u8,
    channel_count: u8,
    pixel_stride: u8,
    comptime byteswap: bool,
) void {
    var dest_index: u32 = 0;
    var source_index: u32 = 0;
    const result_line_bytes = dest_row.len;
    switch (bit_depth) {
        1, 2, 4 => {
            while (dest_index < result_line_bytes) {
                // color_type must be Grayscale or Indexed
                var shift = @intCast(i4, 8 - bit_depth);
                var mask = @as(u8, 0xff) << @intCast(u3, shift);
                while (shift >= 0 and dest_index < result_line_bytes) : (shift -= @intCast(i4, bit_depth)) {
                    dest_row[dest_index] = (current_row[source_index] & mask) >> @intCast(u3, shift);
                    dest_index += pixel_stride;
                    mask >>= @intCast(u3, bit_depth);
                }
                source_index += 1;
            }
        },
        8 => {
            while (dest_index < result_line_bytes) : (dest_index += pixel_stride) {
                var c: u32 = 0;
                while (c < channel_count) : (c += 1) {
                    dest_row[dest_index + c] = current_row[source_index + c];
                }
                source_index += channel_count;
            }
        },
        16 => {
            var current_row16 = mem.bytesAsSlice(u16, current_row);
            var dest_row16 = mem.bytesAsSlice(u16, dest_row);
            const pixel_stride16 = pixel_stride / 2;
            source_index /= 2;
            while (dest_index < dest_row16.len) : (dest_index += pixel_stride16) {
                var c: u32 = 0;
                while (c < channel_count) : (c += 1) {
                    // This is a comptime if so it is not executed in every loop
                    dest_row16[dest_index + c] = if (byteswap) @byteSwap(current_row16[source_index + c]) else current_row16[source_index + c];
                }
                source_index += channel_count;
            }
        },
        else => unreachable,
    }
}

fn callRowProcessors(processors: []ReaderProcessor, process_data: *RowProcessData) Image.ReadError!PixelFormat {
    const starting_format = process_data.src_format;
    var result_format = starting_format;
    for (processors) |*processor| {
        result_format = try processor.processDataRow(process_data);
        process_data.src_format = result_format;
    }
    process_data.src_format = starting_format;
    return result_format;
}

pub const ChunkProcessData = struct {
    stream: *Image.Stream,
    chunk_id: u32,
    chunk_length: u32,
    current_format: PixelFormat,
    header: *const png.HeaderData,
    temp_allocator: Allocator,
};

pub const PaletteProcessData = struct {
    palette: []color.Rgba32,
    temp_allocator: Allocator,
};

pub const RowProcessData = struct {
    dest_row: []u8,
    src_format: PixelFormat,
    dest_format: PixelFormat,
    header: *const png.HeaderData,
    temp_allocator: Allocator,
};

pub const ReaderProcessor = struct {
    id: u32,
    context: *anyopaque,
    vtable: *const VTable,

    const VTable = struct {
        chunk_processor: ?fn (context: *anyopaque, data: *ChunkProcessData) Image.ReadError!PixelFormat,
        palette_processor: ?fn (context: *anyopaque, data: *PaletteProcessData) Image.ReadError!void,
        data_row_processor: ?fn (context: *anyopaque, data: *RowProcessData) Image.ReadError!PixelFormat,
    };

    const Self = @This();

    pub inline fn processChunk(self: *Self, data: *ChunkProcessData) Image.ReadError!PixelFormat {
        return if (self.vtable.chunk_processor) |cp| cp(self.context, data) else data.current_format;
    }

    pub inline fn processPalette(self: *Self, data: *PaletteProcessData) Image.ReadError!void {
        if (self.vtable.palette_processor) |pp| try pp(self.context, data);
    }

    pub inline fn processDataRow(self: *Self, data: *RowProcessData) Image.ReadError!PixelFormat {
        return if (self.vtable.data_row_processor) |drp| drp(self.context, data) else data.dest_format;
    }

    pub fn init(
        id: u32,
        context: anytype,
        comptime chunkProcessorFn: ?fn (ptr: @TypeOf(context), data: *ChunkProcessData) Image.ReadError!PixelFormat,
        comptime paletteProcessorFn: ?fn (ptr: @TypeOf(context), data: *PaletteProcessData) Image.ReadError!void,
        comptime dataRowProcessorFn: ?fn (ptr: @TypeOf(context), data: *RowProcessData) Image.ReadError!PixelFormat,
    ) Self {
        const Ptr = @TypeOf(context);
        const ptr_info = @typeInfo(Ptr);

        std.debug.assert(ptr_info == .Pointer); // Must be a pointer
        std.debug.assert(ptr_info.Pointer.size == .One); // Must be a single-item pointer

        const alignment = ptr_info.Pointer.alignment;

        const gen = struct {
            fn chunkProcessor(ptr: *anyopaque, data: *ChunkProcessData) Image.ReadError!PixelFormat {
                const self = @ptrCast(Ptr, @alignCast(alignment, ptr));
                return @call(.{ .modifier = .always_inline }, chunkProcessorFn.?, .{ self, data });
            }
            fn paletteProcessor(ptr: *anyopaque, data: *PaletteProcessData) Image.ReadError!void {
                const self = @ptrCast(Ptr, @alignCast(alignment, ptr));
                return @call(.{ .modifier = .always_inline }, paletteProcessorFn.?, .{ self, data });
            }
            fn dataRowProcessor(ptr: *anyopaque, data: *RowProcessData) Image.ReadError!PixelFormat {
                const self = @ptrCast(Ptr, @alignCast(alignment, ptr));
                return @call(.{ .modifier = .always_inline }, dataRowProcessorFn.?, .{ self, data });
            }

            const vtable = VTable{
                .chunk_processor = if (chunkProcessorFn == null) null else chunkProcessor,
                .palette_processor = if (paletteProcessorFn == null) null else paletteProcessor,
                .data_row_processor = if (dataRowProcessorFn == null) null else dataRowProcessor,
            };
        };

        return .{
            .id = id,
            .context = context,
            .vtable = &gen.vtable,
        };
    }
};

pub const TrnsProcessor = struct {
    const Self = @This();
    const TRNSData = union(enum) { unset: void, gray: u16, rgb: color.Rgb48, index_alpha: []u8 };

    trns_data: TRNSData = .unset,
    processed: bool = false,

    pub fn processor(self: *Self) ReaderProcessor {
        return ReaderProcessor.init(
            png.Chunks.tRNS.id,
            self,
            processChunk,
            processPalette,
            processDataRow,
        );
    }

    pub fn processChunk(self: *Self, data: *ChunkProcessData) Image.ReadError!PixelFormat {
        // We will allow multiple tRNS chunks and load the first one
        // We ignore if we encounter this chunk with color_type that already has alpha
        var result_format = data.current_format;
        if (self.processed) {
            try data.stream.seekBy(data.chunk_length + @sizeOf(u32)); // Skip invalid
            return result_format;
        }
        var reader = data.stream.reader();
        switch (result_format) {
            .grayscale1, .grayscale2, .grayscale4, .grayscale8, .grayscale16 => {
                if (data.chunk_length == 2) {
                    self.trns_data = .{ .gray = try reader.readIntBig(u16) };
                    result_format = if (result_format == .grayscale16) .grayscale16Alpha else .grayscale8Alpha;
                } else {
                    try data.stream.seekBy(data.chunk_length); // Skip invalid
                }
            },
            .indexed1, .indexed2, .indexed4, .indexed8, .indexed16 => {
                if (data.chunk_length <= data.header.maxPaletteSize()) {
                    self.trns_data = .{ .index_alpha = try data.temp_allocator.alloc(u8, data.chunk_length) };
                    try reader.readNoEof(self.trns_data.index_alpha);
                } else {
                    try data.stream.seekBy(data.chunk_length); // Skip invalid
                }
            },
            .rgb24, .rgb48 => {
                if (data.chunk_length == @sizeOf(color.Rgb48)) {
                    self.trns_data = .{ .rgb = try utils.readStructBig(reader, color.Rgb48) };
                    result_format = if (result_format == .rgb48) .rgba64 else .rgba32;
                } else {
                    try data.stream.seekBy(data.chunk_length); // Skip invalid
                }
            },
            else => try data.stream.seekBy(data.chunk_length), // Skip invalid
        }
        // Skip the Crc since this is not critical chunk
        try data.stream.seekBy(@sizeOf(u32));
        return result_format;
    }

    pub fn processPalette(self: *Self, data: *PaletteProcessData) Image.ReadError!void {
        self.processed = true;
        switch (self.trns_data) {
            .index_alpha => |index_alpha| {
                for (index_alpha) |alpha, i| {
                    data.palette[i].a = alpha;
                }
            },
            .unset => return,
            else => return Image.ReadError.InvalidData,
        }
    }

    pub fn processDataRow(self: *Self, data: *RowProcessData) Image.ReadError!PixelFormat {
        self.processed = true;
        if (data.src_format.isIndex() or self.trns_data == .unset) {
            return data.src_format;
        }
        var pixel_stride: u8 = switch (data.dest_format) {
            .grayscale8Alpha, .grayscale16Alpha => 2,
            .rgba32, .bgra32 => 4,
            .rgba64 => 8,
            else => return data.src_format,
        };
        var pixel_pos: u32 = 0;
        switch (self.trns_data) {
            .gray => |gray_alpha| {
                switch (data.src_format) {
                    .grayscale1, .grayscale2, .grayscale4, .grayscale8 => {
                        while (pixel_pos + 1 < data.dest_row.len) : (pixel_pos += pixel_stride) {
                            data.dest_row[pixel_pos + 1] = (data.dest_row[pixel_pos] ^ @truncate(u8, gray_alpha)) *| 255;
                        }
                        return .grayscale8Alpha;
                    },
                    .grayscale16 => {
                        var destination = std.mem.bytesAsSlice(u16, data.dest_row);
                        while (pixel_pos + 1 < destination.len) : (pixel_pos += pixel_stride) {
                            destination[pixel_pos + 1] = (data.dest_row[pixel_pos] ^ gray_alpha) *| 65535;
                        }
                        return .grayscale16Alpha;
                    },
                    else => unreachable,
                }
            },
            .rgb => |tr_color| {
                switch (data.src_format) {
                    .rgb24 => {
                        var destination = std.mem.bytesAsSlice(color.Rgba32, data.dest_row);
                        pixel_stride /= 4;
                        while (pixel_pos < destination.len) : (pixel_pos += pixel_stride) {
                            var val = destination[pixel_pos];
                            val.a = if (val.r == tr_color.r and val.g == tr_color.g and val.b == tr_color.b) 0 else 255;
                            destination[pixel_pos] = val;
                        }
                        return .rgba32;
                    },
                    .rgb48 => {
                        var destination = std.mem.bytesAsSlice(color.Rgba64, data.dest_row);
                        pixel_stride = 1;
                        while (pixel_pos < destination.len) : (pixel_pos += pixel_stride) {
                            var val = destination[pixel_pos];
                            val.a = if (val.r == tr_color.r and val.g == tr_color.g and val.b == tr_color.b) 0 else 65535;
                            destination[pixel_pos] = val;
                        }
                        return .rgba64;
                    },
                    else => unreachable,
                }
            },
            else => unreachable,
        }
        return data.src_format;
    }
};

pub const PlteProcessor = struct {
    const Self = @This();

    palette: []color.Rgba32 = undefined,
    processed: bool = false,

    pub fn processor(self: *Self) ReaderProcessor {
        return ReaderProcessor.init(
            png.Chunks.PLTE.id,
            self,
            processChunk,
            processPalette,
            processDataRow,
        );
    }

    pub fn processChunk(self: *Self, data: *ChunkProcessData) Image.ReadError!PixelFormat {
        // This is critical chunk so it is already read and there is no need to read it here
        var result_format = data.current_format;
        if (self.processed or !result_format.isIndex()) {
            self.processed = true;
            return result_format;
        }

        return .rgba32;
    }

    pub fn processPalette(self: *Self, data: *PaletteProcessData) Image.ReadError!void {
        self.processed = true;
        self.palette = data.palette;
    }

    pub fn processDataRow(self: *Self, data: *RowProcessData) Image.ReadError!PixelFormat {
        self.processed = true;
        if (!data.src_format.isIndex() or self.palette.len == 0) {
            return data.src_format;
        }
        var pixel_stride: u8 = switch (data.dest_format) {
            .rgba32, .bgra32 => 4,
            .rgba64 => 8,
            else => return data.src_format,
        };

        var pixel_pos: u32 = 0;
        switch (data.src_format) {
            .indexed1, .indexed2, .indexed4, .indexed8 => {
                while (pixel_pos + 3 < data.dest_row.len) : (pixel_pos += pixel_stride) {
                    const index = data.dest_row[pixel_pos];
                    const entry = self.palette[index];
                    data.dest_row[pixel_pos] = entry.r;
                    data.dest_row[pixel_pos + 1] = entry.g;
                    data.dest_row[pixel_pos + 2] = entry.b;
                    data.dest_row[pixel_pos + 3] = entry.a;
                }
            },
            .indexed16 => {
                while (pixel_pos + 3 < data.dest_row.len) : (pixel_pos += pixel_stride) {
                    const index = std.mem.bytesToValue(u16, &[2]u8{ data.dest_row[pixel_pos], data.dest_row[pixel_pos + 1] });
                    const entry = self.palette[index];
                    data.dest_row[pixel_pos] = entry.r;
                    data.dest_row[pixel_pos + 1] = entry.g;
                    data.dest_row[pixel_pos + 2] = entry.b;
                    data.dest_row[pixel_pos + 3] = entry.a;
                }
            },
            else => unreachable,
        }

        return .rgba32;
    }
};

/// The options you need to pass to PNG reader. If you want default options
/// with buffer for temporary allocations on the stack and default set of
/// processors just use this:
/// var default_options = DefaultOptions{};
/// png.reader.load(main_allocator, default_options.get());
/// Note that application can define its own DefaultPngOptions in the root file
/// and all the code that uses DefaultOptions will actually use that.
pub const ReaderOptions = struct {
    /// Allocator for temporary allocations. The constant required_temp_bytes defines
    /// the maximum bytes that will be allocated from it. Some temp allocations depend
    /// on the image size so they will use the main allocator since we can't guarantee
    /// they are bounded. They will be allocated after the destination image to
    /// reduce memory fragmentation and freed internally.
    temp_allocator: Allocator,

    /// Default is no processors so they are not even compiled in if not used.
    /// If you want a default set of processors create a DefaultProcessors object
    /// call get() on it and pass that here.
    /// Note that application can define its own DefPngProcessors and all the
    /// code that uses DefaultProcessors will actually use that.
    processors: []ReaderProcessor = &[_]ReaderProcessor{},

    pub fn init(temp_allocator: Allocator) ReaderOptions {
        return .{ .temp_allocator = temp_allocator };
    }

    pub fn initWithProcessors(temp_allocator: Allocator, processors: []ReaderProcessor) ReaderOptions {
        return .{ .temp_allocator = temp_allocator, .processors = processors };
    }
};

// decompressor.zig:294 claims to use up to 300KiB from provided allocator but when
// testing with huge png file it used 760KiB.
// Original zlib claims it only needs 44KiB so next task is to rewrite zig's zlib :).
pub const required_temp_bytes = 800 * 1024;

const root = @import("root");

/// Applications can override this by defining DefPngProcessors struct in their root source file.
pub const DefaultProcessors = if (@hasDecl(root, "DefPngProcessors"))
    root.DefPngProcessors
else
    struct {
        trns_processor: TrnsProcessor = .{},
        plte_processor: PlteProcessor = .{},
        processors_buffer: [2]ReaderProcessor = undefined,

        const Self = @This();

        pub fn get(self: *Self) []ReaderProcessor {
            self.processors_buffer[0] = self.trns_processor.processor();
            self.processors_buffer[1] = self.plte_processor.processor();
            return self.processors_buffer[0..];
        }
    };

/// Applications can override this by defining DefaultPngOptions struct in their root source file.
pub const DefaultOptions = if (@hasDecl(root, "DefaultPngOptions"))
    root.DefaultPngOptions
else
    struct {
        def_processors: DefaultProcessors = .{},
        tmp_buffer: [required_temp_bytes]u8 = undefined,
        fb_allocator: std.heap.FixedBufferAllocator = undefined,

        const Self = @This();

        pub fn get(self: *Self) ReaderOptions {
            self.fb_allocator = std.heap.FixedBufferAllocator.init(self.tmp_buffer[0..]);
            return .{ .temp_allocator = self.fb_allocator.allocator(), .processors = self.def_processors.get() };
        }
    };

// ********************* TESTS *********************

test "testDefilter" {
    var buffer = [_]u8{ 0, 1, 2, 3, 0, 5, 6, 7 };
    // Start with none filter
    var current_row: []u8 = buffer[4..];
    var prev_row: []u8 = buffer[0..4];
    var filter_stride: u8 = 1;

    try testFilter(png.FilterType.none, current_row, prev_row, filter_stride, &[_]u8{ 0, 5, 6, 7 });
    try testFilter(png.FilterType.sub, current_row, prev_row, filter_stride, &[_]u8{ 0, 5, 11, 18 });
    try testFilter(png.FilterType.up, current_row, prev_row, filter_stride, &[_]u8{ 0, 6, 13, 21 });
    try testFilter(png.FilterType.average, current_row, prev_row, filter_stride, &[_]u8{ 0, 6, 17, 31 });
    try testFilter(png.FilterType.paeth, current_row, prev_row, filter_stride, &[_]u8{ 0, 7, 24, 55 });

    var buffer16 = [_]u8{ 0, 0, 1, 2, 3, 4, 5, 6, 7, 0, 0, 8, 9, 10, 11, 12, 13, 14 };
    current_row = buffer16[9..];
    prev_row = buffer16[0..9];
    filter_stride = 2;

    try testFilter(png.FilterType.none, current_row, prev_row, filter_stride, &[_]u8{ 0, 0, 8, 9, 10, 11, 12, 13, 14 });
    try testFilter(png.FilterType.sub, current_row, prev_row, filter_stride, &[_]u8{ 0, 0, 8, 9, 18, 20, 30, 33, 44 });
    try testFilter(png.FilterType.up, current_row, prev_row, filter_stride, &[_]u8{ 0, 0, 9, 11, 21, 24, 35, 39, 51 });
    try testFilter(png.FilterType.average, current_row, prev_row, filter_stride, &[_]u8{ 0, 0, 9, 12, 27, 32, 51, 58, 80 });
    try testFilter(png.FilterType.paeth, current_row, prev_row, filter_stride, &[_]u8{ 0, 0, 10, 14, 37, 46, 88, 104, 168 });
}

fn testFilter(filter_type: png.FilterType, current_row: []u8, prev_row: []u8, filter_stride: u8, expected: []const u8) !void {
    const expectEqualSlices = std.testing.expectEqualSlices;
    current_row[filter_stride - 1] = @enumToInt(filter_type);
    try defilter(current_row, prev_row, filter_stride);
    try expectEqualSlices(u8, expected, current_row);
}

test "spreadRowData" {
    var channel_count: u8 = 1;
    var bit_depth: u8 = 1;
    // 16 destination bytes, filter byte and two more bytes of current_row
    var dest_buffer = [_]u8{0} ** 32;
    var cur_buffer = [_]u8{ 0, 0, 0, 0, 0xa5, 0x7c, 0x39, 0xf2, 0x5b, 0x15, 0x78, 0xd1 };
    var dest_row: []u8 = dest_buffer[0..16];
    var current_row: []u8 = cur_buffer[3..6];
    var filter_stride: u8 = 1;
    var pixel_stride: u8 = 1;
    const expectEqualSlices = std.testing.expectEqualSlices;

    spreadRowData(dest_row, current_row[filter_stride..], bit_depth, channel_count, pixel_stride, false);
    try expectEqualSlices(u8, &[_]u8{ 1, 0, 1, 0, 0, 1, 0, 1, 0, 1, 1, 1, 1, 1, 0, 0 }, dest_row);
    dest_row = dest_buffer[0..32];
    pixel_stride = 2;
    std.mem.set(u8, dest_row, 0);
    spreadRowData(dest_row, current_row[filter_stride..], bit_depth, channel_count, pixel_stride, false);
    try expectEqualSlices(u8, &[_]u8{ 1, 0, 0, 0, 1, 0, 0, 0, 0, 0, 1, 0, 0, 0, 1, 0, 0, 0, 1, 0, 1, 0, 1, 0, 1, 0, 1, 0, 0, 0, 0, 0 }, dest_row);

    bit_depth = 2;
    pixel_stride = 1;
    dest_row = dest_buffer[0..8];
    spreadRowData(dest_row, current_row[filter_stride..], bit_depth, channel_count, pixel_stride, false);
    try expectEqualSlices(u8, &[_]u8{ 2, 2, 1, 1, 1, 3, 3, 0 }, dest_row);
    dest_row = dest_buffer[0..16];
    pixel_stride = 2;
    std.mem.set(u8, dest_row, 0);
    spreadRowData(dest_row, current_row[filter_stride..], bit_depth, channel_count, pixel_stride, false);
    try expectEqualSlices(u8, &[_]u8{ 2, 0, 2, 0, 1, 0, 1, 0, 1, 0, 3, 0, 3, 0, 0, 0 }, dest_row);

    bit_depth = 4;
    pixel_stride = 1;
    dest_row = dest_buffer[0..4];
    spreadRowData(dest_row, current_row[filter_stride..], bit_depth, channel_count, pixel_stride, false);
    try expectEqualSlices(u8, &[_]u8{ 0xa, 0x5, 0x7, 0xc }, dest_row);
    dest_row = dest_buffer[0..8];
    pixel_stride = 2;
    std.mem.set(u8, dest_row, 0);
    spreadRowData(dest_row, current_row[filter_stride..], bit_depth, channel_count, pixel_stride, false);
    try expectEqualSlices(u8, &[_]u8{ 0xa, 0, 0x5, 0, 0x7, 0, 0xc, 0 }, dest_row);

    bit_depth = 8;
    pixel_stride = 1;
    dest_row = dest_buffer[0..2];
    spreadRowData(dest_row, current_row[filter_stride..], bit_depth, channel_count, pixel_stride, false);
    try expectEqualSlices(u8, &[_]u8{ 0xa5, 0x7c }, dest_row);
    dest_row = dest_buffer[0..4];
    pixel_stride = 2;
    std.mem.set(u8, dest_row, 0);
    spreadRowData(dest_row, current_row[filter_stride..], bit_depth, channel_count, pixel_stride, false);
    try expectEqualSlices(u8, &[_]u8{ 0xa5, 0, 0x7c, 0 }, dest_row);

    channel_count = 2; // grayscale_alpha
    bit_depth = 8;
    current_row = cur_buffer[2..8];
    dest_row = dest_buffer[0..4];
    filter_stride = 2;
    pixel_stride = 2;
    spreadRowData(dest_row, current_row[filter_stride..], bit_depth, channel_count, pixel_stride, false);
    try expectEqualSlices(u8, &[_]u8{ 0xa5, 0x7c, 0x39, 0xf2 }, dest_row);
    dest_row = dest_buffer[0..8];
    std.mem.set(u8, dest_row, 0);
    pixel_stride = 4;
    spreadRowData(dest_row, current_row[filter_stride..], bit_depth, channel_count, pixel_stride, false);
    try expectEqualSlices(u8, &[_]u8{ 0xa5, 0x7c, 0, 0, 0x39, 0xf2, 0, 0 }, dest_row);

    bit_depth = 16;
    current_row = cur_buffer[0..12];
    dest_row = dest_buffer[0..8];
    filter_stride = 4;
    pixel_stride = 4;
    spreadRowData(dest_row, current_row[filter_stride..], bit_depth, channel_count, pixel_stride, true);
    try expectEqualSlices(u8, &[_]u8{ 0x7c, 0xa5, 0xf2, 0x39, 0x15, 0x5b, 0xd1, 0x78 }, dest_row);

    channel_count = 3;
    bit_depth = 8;
    current_row = cur_buffer[1..10];
    dest_row = dest_buffer[0..8];
    std.mem.set(u8, dest_row, 0);
    filter_stride = 3;
    pixel_stride = 4;
    spreadRowData(dest_row, current_row[filter_stride..], bit_depth, channel_count, pixel_stride, false);
    try expectEqualSlices(u8, &[_]u8{ 0xa5, 0x7c, 0x39, 0, 0xf2, 0x5b, 0x15, 0 }, dest_row);

    channel_count = 4;
    bit_depth = 16;
    var cbuffer16 = [_]u8{ 0, 0, 0, 0, 0, 0, 0, 0, 0xa5, 0x7c, 0x39, 0xf2, 0x5b, 0x15, 0x78, 0xd1 };
    current_row = cbuffer16[0..];
    dest_row = dest_buffer[0..8];
    std.mem.set(u8, dest_row, 0);
    filter_stride = 8;
    pixel_stride = 8;
    spreadRowData(dest_row, current_row[filter_stride..], bit_depth, channel_count, pixel_stride, true);
    try expectEqualSlices(u8, &[_]u8{ 0x7c, 0xa5, 0xf2, 0x39, 0x15, 0x5b, 0xd1, 0x78 }, dest_row);
}
