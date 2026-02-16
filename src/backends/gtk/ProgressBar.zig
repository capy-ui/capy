const std = @import("std");
const c = @import("gtk.zig");
const lib = @import("../../capy.zig");
const common = @import("common.zig");

const ProgressBar = @This();

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

pub fn create() common.BackendError!ProgressBar {
    const bar = c.gtk_progress_bar_new() orelse return error.UnknownError;
    try ProgressBar.setupEvents(bar);
    return ProgressBar{ .peer = bar };
}

pub fn setValue(self: *ProgressBar, value: f32) void {
    c.gtk_progress_bar_set_fraction(@ptrCast(self.peer), @as(f64, @floatCast(std.math.clamp(value, 0.0, 1.0))));
}
