const std = @import("std");
const c = @import("gtk.zig");
const lib = @import("../../capy.zig");
const common = @import("common.zig");

const ScrollView = @This();

peer: *c.GtkWidget,

const _events = common.Events(@This());
pub const setupEvents = _events.setupEvents;
pub const copyEventUserData = _events.copyEventUserData;
pub const deinit = _events.deinit;
pub const setUserData = _events.setUserData;
pub const setCallback = _events.setCallback;
pub const setOpacity = _events.setOpacity;
pub const requestDraw = _events.requestDraw;
pub const getX = _events.getX;
pub const getY = _events.getY;
pub const getWidth = _events.getWidth;
pub const getHeight = _events.getHeight;
pub const getPreferredSize = _events.getPreferredSize;

pub fn create() common.BackendError!ScrollView {
    const scrolledWindow = c.gtk_scrolled_window_new() orelse return common.BackendError.UnknownError;
    try ScrollView.setupEvents(scrolledWindow);
    return ScrollView{ .peer = scrolledWindow };
}

pub fn setChild(self: *ScrollView, peer: *c.GtkWidget, _: *lib.Widget) void {
    c.gtk_scrolled_window_set_child(@ptrCast(self.peer), peer);
}
