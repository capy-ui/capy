const std = @import("std");
const c = @import("gtk.zig");
const lib = @import("../../main.zig");
const common = @import("common.zig");

const TabContainer = @This();
peer: *c.GtkWidget,

pub usingnamespace common.Events(TabContainer);

pub fn create() common.BackendError!TabContainer {
    const layout = c.gtk_notebook_new() orelse return common.BackendError.UnknownError;
    try TabContainer.setupEvents(layout);

    const data = common.getEventUserData(layout);
    data.class.resizeHandler = onTabResize;
    data.classUserdata = @intFromPtr(layout);
    return TabContainer{ .peer = layout };
}

fn onTabResize(width: u32, height: u32, data: usize) void {
    const userdata: *common.EventUserData = @ptrFromInt(data);
    const widget: *c.GtkWidget = @ptrFromInt(userdata.classUserdata);
    const n = c.gtk_notebook_get_n_pages(@ptrCast(widget));

    for (0..@intCast(n)) |i| {
        const child = c.gtk_notebook_get_nth_page(@ptrCast(widget), @intCast(i));
        common.widgetSizeChanged(child, width, height);
    }
}

/// Returns the index of the newly added tab
pub fn insert(self: *const TabContainer, position: usize, peer: *c.GtkWidget) usize {
    const data = common.getEventUserData(self.peer);
    data.classUserdata = @intFromPtr(self.peer);
    return @as(usize, @intCast(c.gtk_notebook_insert_page(@as(*c.GtkNotebook, @ptrCast(self.peer)), peer, null, @as(c_int, @intCast(position)))));
}

pub fn setLabel(self: *const TabContainer, position: usize, text: [:0]const u8) void {
    const child = c.gtk_notebook_get_nth_page(@as(*c.GtkNotebook, @ptrCast(self.peer)), @as(c_int, @intCast(position)));
    c.gtk_notebook_set_tab_label_text(@as(*c.GtkNotebook, @ptrCast(self.peer)), child, text.ptr);
}

/// Returns the number of tabs added to this tab container
pub fn getTabsNumber(self: *const TabContainer) usize {
    return @as(usize, @intCast(c.gtk_notebook_get_n_pages(@as(*c.GtkNotebook, @ptrCast(self.peer)))));
}
