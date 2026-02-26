const common = @import("common.zig");
const js = @import("js.zig");
const lib = @import("../../capy.zig");
const GuiWidget = common.GuiWidget;
const Events = common.Events;

const TextField = @This();

peer: *GuiWidget,
text: ?[:0]const u8 = null,

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

pub fn create() !TextField {
    return TextField{ .peer = try GuiWidget.init(
        TextField,
        lib.lasting_allocator,
        "input",
        "textfield",
    ) };
}

pub fn setText(self: *TextField, text: []const u8) void {
    js.setText(self.peer.element, text.ptr, text.len);
}

pub fn getText(self: *TextField) [:0]const u8 {
    if (self.text) |previous_text| {
        lib.allocator.free(previous_text);
    }

    const len = js.getTextLen(self.peer.element);
    const text = lib.lasting_allocator.allocSentinel(u8, len, 0) catch @panic("OOM");
    js.getText(self.peer.element, text.ptr);
    self.text = text;
    return text;
}

pub fn setReadOnly(self: *TextField, readOnly: bool) void {
    if (readOnly) {
        js.setAttribute(self.peer.element, "readonly", "readonly");
    } else {
        js.removeAttribute(self.peer.element, "readonly");
    }
}
