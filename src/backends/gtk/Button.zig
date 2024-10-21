const std = @import("std");
const c = @import("gtk.zig");
const lib = @import("../../capy.zig");
const common = @import("common.zig");

const Button = @This();

peer: *c.GtkWidget,

pub usingnamespace common.Events(Button);

fn gtkClicked(peer: *c.GtkWidget, userdata: usize) callconv(.C) void {
    _ = userdata;
    const data = common.getEventUserData(peer);

    if (data.user.clickHandler) |handler| {
        handler(data.userdata);
    }
}

pub fn create() common.BackendError!Button {
    const button = c.gtk_button_new() orelse return error.UnknownError;
    try Button.setupEvents(button);
    _ = c.g_signal_connect_data(button, "clicked", @as(c.GCallback, @ptrCast(&gtkClicked)), null, @as(c.GClosureNotify, null), 0);
    return Button{ .peer = button };
}

pub fn setLabel(self: *const Button, label: [:0]const u8) void {
    c.gtk_button_set_label(@as(*c.GtkButton, @ptrCast(self.peer)), label.ptr);
}

pub fn getLabel(self: *const Button) [:0]const u8 {
    const label = c.gtk_button_get_label(@as(*c.GtkButton, @ptrCast(self.peer)));
    return std.mem.span(label);
}

pub fn setEnabled(self: *const Button, enabled: bool) void {
    c.gtk_widget_set_sensitive(self.peer, @intFromBool(enabled));
}
