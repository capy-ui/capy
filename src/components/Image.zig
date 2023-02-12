const std = @import("std");
const zigimg = @import("zigimg");
const backend = @import("../backend.zig");
const internal = @import("../internal.zig");
const Size = @import("../data.zig").Size;
const DataWrapper = @import("../data.zig").DataWrapper;

// TODO: use zigimg's structs instead of duplicating efforts
const Colorspace = @import("../color.zig").Colorspace;

const ImageData = @import("../image.zig").ImageData;

/// Component used to show an image.
pub const Image_Impl = struct {
    pub usingnamespace @import("../internal.zig").All(Image_Impl);

    peer: ?backend.Canvas = null,
    handlers: Image_Impl.Handlers = undefined,
    dataWrappers: Image_Impl.DataWrappers = .{},
    data: DataWrapper(ImageData),
    scaling: DataWrapper(Scaling) = DataWrapper(Scaling).of(.Fit),

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
            .data = DataWrapper(ImageData).of(config.data),
            .scaling = DataWrapper(Scaling).of(config.scaling),
        });
        image.addDrawHandler(&Image_Impl.draw) catch unreachable;
        return image;
    }

    pub fn getPreferredSize(self: *Image_Impl, _: Size) Size {
        const data = self.data.get();
        return Size.init(data.width, data.height);
    }

    pub fn draw(self: *Image_Impl, ctx: *DrawContext) !void {
        const width = self.getWidth();
        const height = self.getHeight();

        const image = self.data.get();
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
