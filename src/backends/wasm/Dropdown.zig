const common = @import("common.zig");
const js = @import("js.zig");
const lib = @import("../../capy.zig");
const GuiWidget = common.GuiWidget;
const Events = common.Events;

const Dropdown = @This();

peer: js.ElementId,

const _events = Events(@This());
pub const setupEvents = _events.setupEvents;
pub const setUserData = _events.setUserData;
pub const setCallback = _events.setCallback;
pub const setOpacity = _events.setOpacity;
pub const requestDraw = _events.requestDraw;
pub const processEvent = _events.processEvent;
pub const getWidth = _events.getWidth;
pub const getHeight = _events.getHeight;
pub const getPreferredSize = _events.getPreferredSize;
pub const deinit = _events.deinit;

pub fn create() !Dropdown {
    return Dropdown{ .peer = try GuiWidget.init(
        Dropdown,
        lib.lasting_allocator,
        "select",
        "select",
    ) };
}
