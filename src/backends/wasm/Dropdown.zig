const common = @import("common.zig");
const js = @import("js.zig");
const lib = @import("../../capy.zig");
const GuiWidget = common.GuiWidget;
const Events = common.Events;

const Dropdown = @This();

peer: js.ElementId,

pub usingnamespace Events(Dropdown);

pub fn create() !Dropdown {
    return Dropdown{ .peer = try GuiWidget.init(
        Dropdown,
        lib.lasting_allocator,
        "select",
        "select",
    ) };
}
