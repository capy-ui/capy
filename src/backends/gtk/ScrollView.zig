const std = @import("std");
const c = @import("gtk.zig");
const lib = @import("../../capy.zig");
const common = @import("common.zig");

const ScrollView = @This();

peer: *c.GtkWidget,

pub usingnamespace common.Events(ScrollView);

pub fn create() common.BackendError!ScrollView {
    const scrolledWindow = c.gtk_scrolled_window_new() orelse return common.BackendError.UnknownError;
    try ScrollView.setupEvents(scrolledWindow);
    return ScrollView{ .peer = scrolledWindow };
}

pub fn setChild(self: *ScrollView, peer: *c.GtkWidget, _: *lib.Widget) void {
    c.gtk_scrolled_window_set_child(@ptrCast(self.peer), peer);
}
