const std = @import("std");
const c = @import("gtk.zig");
const lib = @import("../../capy.zig");
const common = @import("common.zig");

const CheckBox = @This();

peer: *c.GtkWidget,

pub usingnamespace common.Events(CheckBox);

fn gtkClicked(peer: *c.GtkWidget, userdata: usize) callconv(.C) void {
    _ = userdata;
    const data = common.getEventUserData(peer);

    if (data.user.clickHandler) |handler| {
        handler(data.userdata);
    }
}

pub fn create() common.BackendError!CheckBox {
    const button = c.gtk_check_button_new() orelse return error.UnknownError;
    try CheckBox.setupEvents(button);
    _ = c.g_signal_connect_data(button, "toggled", @as(c.GCallback, @ptrCast(&gtkClicked)), null, @as(c.GClosureNotify, null), 0);
    return CheckBox{ .peer = button };
}

pub fn setLabel(self: *const CheckBox, label: [:0]const u8) void {
    c.gtk_check_button_set_label(@ptrCast(self.peer), label.ptr);
}

pub fn getLabel(self: *const CheckBox) [:0]const u8 {
    const label = c.gtk_check_button_get_label(@ptrCast(self.peer));
    return std.mem.span(label);
}

pub fn setEnabled(self: *const CheckBox, enabled: bool) void {
    c.gtk_widget_set_sensitive(self.peer, @intFromBool(enabled));
}

pub fn setChecked(self: *const CheckBox, checked: bool) void {
    c.gtk_check_button_set_active(@ptrCast(self.peer), @intFromBool(checked));
}

pub fn isChecked(self: *const CheckBox) bool {
    return c.gtk_check_button_get_active(@ptrCast(self.peer)) != 0;
}
