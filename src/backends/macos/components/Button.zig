const backend = @import("../backend.zig");
const objc = @import("objc");
const AppKit = @import("../AppKit.zig");
const Events = backend.Events;
const BackendError = @import("../../shared.zig").BackendError;

const Button = @This();

peer: objc.Object,

pub usingnamespace Events(Button);

pub fn create() BackendError!Button {
    const NSButton = objc.getClass("NSButton").?;
    // const button = NSButton.msgSend(objc.Object, "alloc", .{})
    const button = NSButton.msgSend(objc.Object, "buttonWithTitle:target:action:", .{ AppKit.nsString(""), AppKit.nil, null });
    try Button.setupEvents(button);
    return Button{ .peer = button };
}

pub fn setLabel(self: *const Button, label: [:0]const u8) void {
    self.peer.setProperty("title", AppKit.nsString(label.ptr));
}

pub fn getLabel(self: *const Button) [:0]const u8 {
    const title = self.peer.getProperty(objc.Object, "title");
    const label = title.msgSend([*]const u8, "cStringUsingEncoding:", .{AppKit.NSStringEncoding.UTF8});
    return label;
}

pub fn setEnabled(self: *const Button, enabled: bool) void {
    self.peer.setProperty("enabled", enabled);
}
