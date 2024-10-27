const common = @import("common.zig");
const js = @import("js.zig");
const lib = @import("../../capy.zig");
const GuiWidget = common.GuiWidget;
const Events = common.Events;

const ImageData = @This();

// TODO
id: js.ResourceId,

pub fn from(width: usize, height: usize, stride: usize, cs: lib.Colorspace, bytes: []const u8) !ImageData {
    return ImageData{
        .id = js.uploadImage(
            width,
            height,
            stride,
            cs == .RGB,
            bytes.ptr,
        ),
    };
}
