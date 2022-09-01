const std = @import("std");
const backend = @import("backend.zig");
const Size = @import("data.zig").Size;
const zigimg = @import("zigimg");
const DataWrapper = @import("data.zig").DataWrapper;

const Colorspace = @import("color.zig").Colorspace;

/// As of now, Capy UI only supports RGB and RGBA images
pub const ImageData = struct {
    width: u32,
    stride: u32,
    height: u32,
    /// Value pointing to the image data
    peer: backend.ImageData,

    pub fn fromBytes(width: u32, height: u32, stride: u32, cs: Colorspace, bytes: []const u8) !ImageData {
        std.debug.assert(bytes.len >= stride * height);
        return ImageData{
            .width = width,
            .height = height,
            .stride = stride,
            .peer = try backend.ImageData.from(width, height, stride, cs, bytes),
        };
    }

    pub fn fromFile(allocator: std.mem.Allocator, path: []const u8) !ImageData {
        const file = try std.fs.cwd().openFile(path, .{ .mode = .read_only });
        var stream = std.io.StreamSource{ .file = file };
        return readFromStream(allocator, &stream);
    }

    /// Load from a png file using a buffer (which can be provided by @embedFile)
    pub fn fromBuffer(allocator: std.mem.Allocator, buf: []const u8) !ImageData {
        // stage1 crashes with LLVM ERROR: Unable to expand fixed point multiplication.
        //const img = try zigimg.Image.fromMemory(allocator, buf);

        var stream = std.io.StreamSource{ .const_buffer = std.io.fixedBufferStream(buf) };
        return readFromStream(allocator, &stream);
    }

    fn readFromStream(allocator: std.mem.Allocator, stream: *std.io.StreamSource) !ImageData {
        var arena = std.heap.ArenaAllocator.init(allocator);
        defer arena.deinit();

        var plte = zigimg.png.PlteProcessor{};
        // TRNS processor isn't included as it crashed LLVM due to saturating multiplication
        var img = try zigimg.png.load(
            stream,
            allocator,
            zigimg.png.ReaderOptions.initWithProcessors(
                arena.allocator(),
                &.{plte.processor()},
            ),
        );
        //defer img.deinit();
        const bytes = img.rawBytes();
        return try ImageData.fromBytes(
            @intCast(u32, img.width),
            @intCast(u32, img.height),
            @intCast(u32, img.rowByteSize()),
            .RGBA,
            bytes,
        );
    }
};

/// Component used to show an image.
pub const Image_Impl = struct {
    pub usingnamespace @import("internal.zig").All(Image_Impl);

    peer: ?backend.Canvas = null,
    handlers: Image_Impl.Handlers = undefined,
    dataWrappers: Image_Impl.DataWrappers = .{},
    imageData: DataWrapper(ImageData) = DataWrapper(ImageData)
        .of(.{ .width = 0, .height = 0, .stride = 0, .peer = undefined }),
    scaling: DataWrapper(Scaling) = DataWrapper(Scaling)
        .of(.None),

    pub const Scaling = enum {
        /// Keep the original size of the image
        None,
        /// Scale the image while keeping the aspect ratio, even if it does not use all of the component's space
        Fit,
        /// Scale the image without keeping the aspect ratio but the image may look distorted.
        Stretch,
    };

    pub const Config = struct {
        data: ImageData,
        scaling: Scaling = .Fit,
    };

    pub const DrawContext = backend.Canvas.DrawContext;

    pub fn init(config: Config) Image_Impl {
        var image = Image_Impl.init_events(Image_Impl{
            .imageData = DataWrapper(ImageData).of(config.data),
            .scaling = DataWrapper(Scaling).of(config.scaling),
        });
        _ = image.addDrawHandler(Image_Impl.draw) catch unreachable;
        return image;
    }

    pub fn getPreferredSize(self: *Image_Impl, _: Size) Size {
        const data = self.imageData.get();
        return Size.init(data.width, data.height);
    }

    pub fn draw(self: *Image_Impl, ctx: *DrawContext) !void {
        const width = self.getWidth();
        const height = self.getHeight();

        const image = self.imageData.get();
        switch (self.scaling.get()) {
            .None => {
                const imageX = @intCast(i32, width / 2) - @intCast(i32, image.width / 2);
                const imageY = @intCast(i32, height / 2) - @intCast(i32, image.height / 2);
                ctx.image(
                    imageX,
                    imageY,
                    image.width,
                    image.height,
                    image,
                );
            },
            .Fit => {
                // The aspect ratio of the image
                const ratio = @intToFloat(f32, image.width) / @intToFloat(f32, image.height);
                var imageW: u32 = undefined;
                var imageH: u32 = undefined;

                if (@intToFloat(f32, width) / ratio < @intToFloat(f32, height)) {
                    imageW = width;
                    imageH = @floatToInt(u32, @intToFloat(f32, imageW) / ratio);
                } else {
                    imageH = height;
                    imageW = @floatToInt(u32, @intToFloat(f32, imageH) * ratio);
                }

                const imageX = @intCast(i32, width / 2) - @intCast(i32, imageW / 2);
                const imageY = @intCast(i32, height / 2) - @intCast(i32, imageH / 2);

                ctx.image(
                    imageX,
                    imageY,
                    imageW,
                    imageH,
                    image,
                );
            },
            .Stretch => {
                ctx.image(
                    0,
                    0,
                    image.width,
                    image.height,
                    image,
                );
            },
        }
    }

    pub fn show(self: *Image_Impl) !void {
        if (self.peer == null) {
            self.peer = try backend.Canvas.create();
            try self.show_events();
        }
    }
};

pub fn Image(config: Image_Impl.Config) Image_Impl {
    var image = Image_Impl.init(config);
    return image;
}
