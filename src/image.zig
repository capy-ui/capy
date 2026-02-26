const std = @import("std");
const zigimg = @import("zigimg");
const backend = @import("backend.zig");
const internal = @import("internal.zig");
const Size = @import("data.zig").Size;
const DataWrapper = @import("data.zig").DataWrapper;

// TODO: use zigimg's structs instead of duplicating efforts
const Colorspace = @import("color.zig").Colorspace;

/// As of now, Capy UI only supports RGB and RGBA images
pub const ImageData = struct {
    width: u32,
    stride: u32,
    height: u32,
    /// Value pointing to the image data
    peer: backend.ImageData,
    data: []const u8,
    allocator: ?std.mem.Allocator = null,

    pub fn new(width: u32, height: u32, cs: Colorspace) !ImageData {
        const stride = width * cs.byteCount();
        const bytes = try internal.allocator.alloc(u8, stride * height);
        @memset(bytes, 0x00);
        return fromBytes(width, height, stride, cs, bytes, internal.allocator);
    }

    pub fn fromBytes(width: u32, height: u32, stride: u32, cs: Colorspace, bytes: []const u8, allocator: ?std.mem.Allocator) !ImageData {
        std.debug.assert(bytes.len >= stride * height);
        return ImageData{
            .width = width,
            .height = height,
            .stride = stride,
            .peer = if (backend.ImageData != void) try backend.ImageData.from(width, height, stride, cs, bytes) else {},
            .data = bytes,
            .allocator = allocator,
        };
    }

    pub fn fromFile(allocator: std.mem.Allocator, path: []const u8) !ImageData {
        const file = try std.fs.cwd().openFile(path, .{ .mode = .read_only });
        var file_read_buf: [4096]u8 = undefined;
        var stream = zigimg.io.ReadStream.initFile(file, &file_read_buf);
        return readFromStream(allocator, &stream);
    }

    /// Load from a png file using a buffer (which can be provided by @embedFile)
    pub fn fromBuffer(allocator: std.mem.Allocator, buf: []const u8) !ImageData {
        var stream = zigimg.io.ReadStream.initMemory(buf);
        return readFromStream(allocator, &stream);
    }

    // TODO: on WASM, let the browser do the job of loading image data, so we can reduce the WASM bundle size
    // TODO: basically, use <img> on Web
    pub fn readFromStream(allocator: std.mem.Allocator, stream: *zigimg.io.ReadStream) !ImageData {
        var arena = std.heap.ArenaAllocator.init(allocator);
        defer arena.deinit();

        var plte = zigimg.formats.png.PlteProcessor{};
        // TRNS processor isn't included as it crashed LLVM due to saturating multiplication
        var processors: [1]zigimg.formats.png.ReaderProcessor = .{plte.processor()};
        var img = try zigimg.formats.png.load(
            stream,
            allocator,
            zigimg.formats.png.ReaderOptions.initWithProcessors(
                arena.allocator(),
                &processors,
            ),
        );
        defer img.deinit(allocator);
        const raw_bytes = img.rawBytes();
        const bytes = try allocator.dupe(u8, raw_bytes);
        errdefer allocator.free(bytes);
        return try ImageData.fromBytes(
            @as(u32, @intCast(img.width)),
            @as(u32, @intCast(img.height)),
            @as(u32, @intCast(img.rowByteSize())),
            .RGBA,
            bytes,
            allocator,
        );
    }

    pub fn deinit(self: *ImageData) void {
        self.peer.deinit();
        if (self.allocator) |allocator| {
            allocator.free(self.data);
        }
        self.* = undefined;
    }
};

test "ImageData.fromFile loads png" {
    var img = try ImageData.fromFile(std.testing.allocator, "assets/ziglogo.png");
    defer img.deinit();
    // ziglogo.png must have non-zero dimensions
    try std.testing.expect(img.width > 0);
    try std.testing.expect(img.height > 0);
    // Data slice must be at least width * height * bytes_per_pixel (RGBA = 4)
    try std.testing.expect(img.data.len >= img.stride * img.height);
}

test "ImageData.fromFile dimensions are consistent" {
    var img = try ImageData.fromFile(std.testing.allocator, "assets/ziglogo.png");
    defer img.deinit();
    // Stride must be at least width * 4 (RGBA)
    try std.testing.expect(img.stride >= img.width * 4);
    // Total data must cover all rows
    try std.testing.expectEqual(img.stride * img.height, @as(u32, @intCast(img.data.len)));
}

test "ImageData.fromFile returns error for missing file" {
    const result = ImageData.fromFile(std.testing.allocator, "assets/nonexistent.png");
    try std.testing.expectError(error.FileNotFound, result);
}

pub const ScalableVectorData = struct {};
