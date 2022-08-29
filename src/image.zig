const std = @import("std");
const backend = @import("backend.zig");
const Size = @import("data.zig").Size;
const zigimg = @import("zigimg");

const Colorspace = @import("color.zig").Colorspace;

/// As of now, zgt only supports RGBA images
pub const ImageData = struct {
    width: usize,
    stride: usize,
    height: usize,
    /// Value pointing to the image data
    peer: backend.ImageData,

    pub fn fromBytes(width: usize, height: usize, stride: usize, cs: Colorspace, bytes: []const u8) !ImageData {
        std.debug.assert(bytes.len >= stride * height);
        return ImageData{ .width = width, .height = height, .stride = stride, .peer = try backend.ImageData.from(width, height, stride, cs, bytes) };
    }

    pub fn fromFile(allocator: std.mem.Allocator, path: []const u8) !ImageData {
        const file = try std.fs.cwd().openFile(path, .{ .mode = .read_only });
        defer file.close();

        const reader = file.reader();
        return @import("png.zig").read(allocator, reader);
    }

    /// Load from a png file using a buffer (which can be provided by @embedFile)
    pub fn fromBuffer(allocator: std.mem.Allocator, buf: []const u8) !ImageData {
        // stage1 crashes with LLVM ERROR: Unable to expand fixed point multiplication.
        //const img = try zigimg.Image.fromMemory(allocator, buf);

        var stream = std.io.StreamSource{ .const_buffer = std.io.fixedBufferStream(buf) };
        var arena = std.heap.ArenaAllocator.init(allocator);
        defer arena.deinit();

        var plte = zigimg.png.PlteProcessor{};
        // TRNS processor isn't included as it crashed LLVM due to saturating multiplication
        var img = try zigimg.png.load(
            &stream,
            allocator,
            zigimg.png.ReaderOptions.initWithProcessors(
                arena.allocator(),
                &.{plte.processor()},
            ),
        );
        defer img.deinit();
        const bytes = img.rawBytes();
        return try ImageData.fromBytes(img.width, img.height, img.rowByteSize(), .RGB, bytes);
    }
};

pub const Image_Impl = struct {
    pub usingnamespace @import("internal.zig").All(Image_Impl);

    peer: ?backend.Image = null,
    handlers: Image_Impl.Handlers = undefined,
    dataWrappers: Image_Impl.DataWrappers = .{},
    data: ImageData,

    pub fn init() Image_Impl {
        return initWithData(.{ .width = 0, .height = 0, .stride = 0, .peer = 0 });
    }

    pub fn initWithData(data: ImageData) Image_Impl {
        return Image_Impl.init_events(Image_Impl{ .data = data });
    }

    pub fn show(self: *Image_Impl) !void {
        if (self.peer == null) {
            self.peer = try backend.Image.create();
            self.peer.?.setData(self.data.peer);
            try self.show_events();
        }
    }

    pub fn getPreferredSize(self: *Image_Impl, available: Size) Size {
        _ = available;
        return Size{ .width = @intCast(u32, self.data.width), .height = @intCast(u32, self.data.height) };
    }
};

pub fn Image(config: struct { data: ImageData }) Image_Impl {
    var image = Image_Impl.initWithData(config.data);
    return image;
}
