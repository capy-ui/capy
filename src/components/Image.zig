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
pub const Image_Impl = struct {
    pub usingnamespace @import("../internal.zig").All(Image_Impl);

    peer: ?backend.Canvas = null,
    widget_data: Image_Impl.WidgetData = .{},
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

    pub const DrawContext = backend.Canvas.DrawContext;

    // TODO: just directly accept an URL or file path if there's no data
    pub fn init(config: Image_Impl.Config) Image_Impl {
        var image = Image_Impl.init_events(Image_Impl{
            .url = Atom([]const u8).of(config.url),
            .data = Atom(?ImageData).of(config.data),
            .scaling = Atom(Scaling).of(config.scaling),
        });
        image.addDrawHandler(&Image_Impl.draw) catch unreachable;
        return image;
    }

    pub fn getPreferredSize(self: *Image_Impl, available: Size) Size {
        if (self.data.get()) |data| {
            return Size.init(data.width, data.height);
        } else {
            return Size.init(100, 30).intersect(available);
        }
    }

    fn loadImage(self: *Image_Impl) !void {
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

    pub fn draw(self: *Image_Impl, ctx: *DrawContext) !void {
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

        const image = self.data.get().?;
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
