const common = @import("common.zig");
const js = @import("js.zig");
const lib = @import("../../capy.zig");
const GuiWidget = common.GuiWidget;
const Events = common.Events;

const Button = @This();

peer: *GuiWidget,
/// The label returned by getLabel(), it's invalidated everytime setLabel is called
temp_label: ?[:0]const u8 = null,

pub usingnamespace Events(Button);

pub fn create() !Button {
    return Button{ .peer = try GuiWidget.init(
        Button,
        lib.lasting_allocator,
        "button",
        "button",
    ) };
}

pub fn setLabel(self: *Button, label: [:0]const u8) void {
    js.setText(self.peer.element, label.ptr, label.len);
    if (self.temp_label) |slice| {
        lib.lasting_allocator.free(slice);
        self.temp_label = null;
    }
}

pub fn getLabel(self: *const Button) [:0]const u8 {
    if (self.temp_label) |text| {
        return text;
    } else {
        const len = js.getTextLen(self.peer.element);
        const text = lib.lasting_allocator.allocSentinel(u8, len, 0) catch unreachable;
        js.getText(self.peer.element, text.ptr);
        self.temp_label = text;

        return text;
    }
}

pub fn setEnabled(self: *const Button, enable: bool) void {
    if (enable) {
        js.removeAttribute(self.peer.element, "disabled");
    } else {
        js.setAttribute(self.peer.element, "disabled", "disabled");
    }
}
