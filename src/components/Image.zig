const std = @import("std");
const zigimg = @import("zigimg");
const backend = @import("../backend.zig");
const internal = @import("../internal.zig");
const Size = @import("../data.zig").Size;
const Atom = @import("../data.zig").Atom;
const assets = @import("../assets.zig");

// TODO: use zigimg's structs instead of duplicating efforts
const Colorspace = @import("../color.zig").Colorspace;

const ImageData = @import("../image.zig").ImageData;
const ScalableVectorData = @import("../image.zig").ScalableVectorData;

// TODO: convert to using a flat component so a backend may provide an Image backend
/// Component used to show an image.
pub const Image = struct {
    pub usingnamespace @import("../internal.zig").All(Image);

    peer: ?backend.Canvas = null,
    widget_data: Image.WidgetData = .{},
    url: Atom([]const u8),
    data: Atom(?ImageData) = Atom(?ImageData).of(null),
    scaling: Atom(Scaling) = Atom(Scaling).of(.Fit),

    // TODO: if vector graphics (SVG or TVG) then rerender every time Image component is resized
    vectorData: Atom(?ScalableVectorData) = Atom(?ScalableVectorData).of(null),

    // TODO: when url changes set data to null

    pub const Scaling = enum {
        /// Keep the original size of the image
        None,
        /// Scale the image while keeping the aspect ratio, even if it does not use all of the component's space
        Fit,
        /// Scale the image without keeping the aspect ratio but the image may look distorted.
        Stretch,
    };

    pub const DrawContext = backend.DrawContext;

    pub fn init(config: Image.Config) Image {
        var self = Image.init_events(Image{ .url = Atom([]const u8).of(config.url) });
        self.addDrawHandler(&Image.draw) catch unreachable;
        @import("../internal.zig").applyConfigStruct(&self, config);
        return self;
    }

    pub fn getPreferredSize(self: *Image, available: Size) Size {
        if (self.data.get()) |data| {
            return Size.init(@floatFromInt(data.width), @floatFromInt(data.height));
        } else {
            return Size.init(100, 100).intersect(available);
        }
    }

    fn loadImage(self: *Image) !void {
        // TODO: asynchronous loading
        var handle = try assets.get(self.url.get());
        defer handle.deinit();

        var reader = handle.reader();
        // TODO: progressive when I find a way to fit AssetHandle.Reader into zigimg
        const contents = try reader.readAllAlloc(internal.scratch_allocator, std.math.maxInt(usize));
        defer internal.scratch_allocator.free(contents);

        const data = try ImageData.fromBuffer(internal.lasting_allocator, contents);
        self.data.set(data);
    }

    pub fn draw(self: *Image, ctx: *DrawContext) !void {
        const width = self.getWidth();
        const height = self.getHeight();

        if (self.data.get() == null) {
            self.loadImage() catch |err| {
                std.log.err("{s}", .{@errorName(err)});
                if (@errorReturnTrace()) |trace| {
                    std.debug.dumpStackTrace(trace.*);
                }
            };

            // TODO: render a placeholder
            return;
        }

        const img = self.data.get().?;
        switch (self.scaling.get()) {
            .None => {
                const imgX = @as(i32, @intCast(width / 2)) - @as(i32, @intCast(img.width / 2));
                const imgY = @as(i32, @intCast(height / 2)) - @as(i32, @intCast(img.height / 2));
                ctx.image(
                    imgX,
                    imgY,
                    img.width,
                    img.height,
                    img,
                );
            },
            .Fit => {
                // The aspect ratio of the img
                const ratio = @as(f32, @floatFromInt(img.width)) / @as(f32, @floatFromInt(img.height));
                var imgW: u32 = undefined;
                var imgH: u32 = undefined;

                if (@as(f32, @floatFromInt(width)) / ratio < @as(f32, @floatFromInt(height))) {
                    imgW = width;
                    imgH = @as(u32, @intFromFloat(@as(f32, @floatFromInt(imgW)) / ratio));
                } else {
                    imgH = height;
                    imgW = @as(u32, @intFromFloat(@as(f32, @floatFromInt(imgH)) * ratio));
                }

                const imgX = @as(i32, @intCast(width / 2)) - @as(i32, @intCast(imgW / 2));
                const imgY = @as(i32, @intCast(height / 2)) - @as(i32, @intCast(imgH / 2));

                ctx.image(
                    imgX,
                    imgY,
                    imgW,
                    imgH,
                    img,
                );
            },
            .Stretch => {
                ctx.image(
                    0,
                    0,
                    img.width,
                    img.height,
                    img,
                );
            },
        }
    }

    pub fn show(self: *Image) !void {
        if (self.peer == null) {
            self.peer = try backend.Canvas.create();
            try self.setupEvents();
        }
    }
};

pub fn image(config: Image.Config) *Image {
    return Image.alloc(config);
}
