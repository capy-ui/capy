const common = @import("common.zig");
const js = @import("js.zig");
const lib = @import("../../capy.zig");
const GuiWidget = common.GuiWidget;
const Events = common.Events;

const TextField = @This();

peer: *GuiWidget,

pub usingnamespace Events(TextField);

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
    const len = js.getTextLen(self.peer.element);
    // TODO: fix the obvious memory leak
    const text = lib.lasting_allocator.allocSentinel(u8, len, 0) catch unreachable;
    js.getText(self.peer.element, text.ptr);

    return text;
}

pub fn setReadOnly(self: *TextField, readOnly: bool) void {
    if (readOnly) {
        js.removeAttribute(self.peer.element, "readonly");
    } else {
        js.setAttribute(self.peer.element, "readonly", "readonly");
    }
}
