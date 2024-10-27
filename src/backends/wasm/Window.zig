const common = @import("common.zig");
const js = @import("js.zig");
const lib = @import("../../capy.zig");
const GuiWidget = common.GuiWidget;
const Events = common.Events;

const Window = @This();
pub var globalWindow: ?*Window = null;

peer: *GuiWidget,
child: ?*GuiWidget = null,
scale: f32 = 1.0,

pub usingnamespace Events(Window);

pub fn create() !Window {
    return Window{
        .peer = try GuiWidget.init(
            Window,
            lib.lasting_allocator,
            "div",
            "window",
        ),
    };
}

pub fn show(self: *Window) void {
    // TODO: handle multiple windows
    if (globalWindow != null) {
        js.print("one window already showed!");
        return;
    }
    globalWindow = self;
}

pub fn resize(_: *Window, _: c_int, _: c_int) void {
    // Not implemented.
}

pub fn setChild(self: *Window, peer: ?*GuiWidget) void {
    if (peer) |p| {
        js.setRoot(p.element);
        self.child = peer;
    } else {
        // TODO: js.clearRoot();
    }
}

pub fn setTitle(self: *Window, title: [*:0]const u8) void {
    // TODO. This should be configured in the javascript
    _ = self;
    _ = title;
}

pub fn setSourceDpi(self: *Window, dpi: u32) void {
    // CSS pixels are somewhat undefined given they're based on the confortableness of the reader
    const resolution = @as(f32, @floatFromInt(dpi));
    self.scale = resolution / 96.0;
}

pub fn registerTickCallback(self: *Window) void {
    _ = self;
    // TODO
}
