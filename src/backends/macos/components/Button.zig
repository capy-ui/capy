const std = @import("std");
const backend = @import("../backend.zig");
const objc = @import("objc");
const AppKit = @import("../AppKit.zig");
const Events = backend.Events;
const BackendError = @import("../../shared.zig").BackendError;
const lib = @import("../../../capy.zig");

const Button = @This();

peer: backend.GuiWidget,

const _events = Events(@This());
pub const setupEvents = _events.setupEvents;
pub const setUserData = _events.setUserData;
pub const setCallback = _events.setCallback;
pub const setOpacity = _events.setOpacity;
pub const getX = _events.getX;
pub const getY = _events.getY;
pub const getWidth = _events.getWidth;
pub const getHeight = _events.getHeight;
pub const getPreferredSize = _events.getPreferredSize;
pub const requestDraw = _events.requestDraw;
pub const deinit = _events.deinit;

pub fn create() BackendError!Button {
    const NSButton = objc.getClass("NSButton").?;
    // const button = NSButton.msgSend(objc.Object, "alloc", .{})
    const button = NSButton.msgSend(objc.Object, "buttonWithTitle:target:action:", .{ AppKit.nsString(""), AppKit.nil, null });
    const peer = backend.GuiWidget{
        .object = button,
        .data = try lib.internal.allocator.create(backend.EventUserData),
    };
    try Button.setupEvents(peer);
    return Button{ .peer = peer };
}

pub fn setLabel(self: *const Button, label: [:0]const u8) void {
    self.peer.object.setProperty("title", AppKit.nsString(label.ptr));
}

pub fn getLabel(self: *const Button) [:0]const u8 {
    const title = self.peer.object.getProperty(objc.Object, "title");
    const label = title.msgSend([*:0]const u8, "cStringUsingEncoding:", .{AppKit.NSStringEncoding.UTF8});
    return std.mem.sliceTo(label, 0);
}

pub fn setEnabled(self: *const Button, enabled: bool) void {
    self.peer.object.setProperty("enabled", enabled);
}
