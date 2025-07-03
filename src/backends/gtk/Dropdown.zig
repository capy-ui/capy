const std = @import("std");
const c = @import("gtk.zig");
const lib = @import("../../capy.zig");
const common = @import("common.zig");

const Dropdown = @This();

peer: *c.GtkWidget,
owned_strings: ?[:null]const ?[*:0]const u8 = null,

pub usingnamespace common.Events(Dropdown);

fn gtkSelected(peer: *c.GtkWidget, userdata: usize) callconv(.C) void {
    _ = userdata;
    const data = common.getEventUserData(peer);

    if (data.user.propertyChangeHandler) |handler| {
        const index: usize = c.gtk_drop_down_get_selected(@ptrCast(peer));
        handler("selected", &index, data.userdata);
    }
}

pub fn create() common.BackendError!Dropdown {
    const dropdown = c.gtk_drop_down_new_from_strings(null);
    try Dropdown.setupEvents(dropdown);
    _ = c.g_signal_connect_data(dropdown, "notify::selected", @as(c.GCallback, @ptrCast(&gtkSelected)), null, @as(c.GClosureNotify, null), 0);
    return Dropdown{ .peer = dropdown };
}

pub fn getSelectedIndex(self: *const Dropdown) usize {
    return c.gtk_drop_down_get_selected(@ptrCast(self.peer));
}

pub fn setSelectedIndex(self: *const Dropdown, index: usize) void {
    c.gtk_drop_down_set_selected(@ptrCast(self.peer), @intCast(index));
}

pub fn setValues(self: *Dropdown, values: []const []const u8) void {
    const allocator = lib.internal.allocator;
    if (self.owned_strings) |strings| {
        for (strings) |string| {
            allocator.free(std.mem.span(string.?));
        }
        allocator.free(strings);
    }

    const duplicated = allocator.allocSentinel(?[*:0]const u8, values.len, null) catch return;
    errdefer allocator.free(duplicated);
    for (values, 0..) |value, i| {
        const slice = allocator.dupeZ(u8, value) catch return;
        duplicated[i] = slice.ptr;
    }
    self.owned_strings = duplicated;

    const old_index = self.getSelectedIndex();
    c.gtk_drop_down_set_model(@ptrCast(self.peer), @ptrCast(c.gtk_string_list_new(duplicated.ptr).?));
    self.setSelectedIndex(old_index);
}

pub fn setEnabled(self: *const Dropdown, enabled: bool) void {
    c.gtk_widget_set_sensitive(self.peer, @intFromBool(enabled));
}
