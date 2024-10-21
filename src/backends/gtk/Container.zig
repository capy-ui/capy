const std = @import("std");
const c = @import("gtk.zig");
const lib = @import("../../capy.zig");
const common = @import("common.zig");
// WindowBin
const wbin_new = @import("windowbin.zig").wbin_new;
const wbin_set_child = @import("windowbin.zig").wbin_set_child;

const Container = @This();

peer: *c.GtkWidget,
container: *c.GtkWidget,

pub usingnamespace common.Events(Container);

pub fn create() common.BackendError!Container {
    const layout = c.gtk_fixed_new() orelse return common.BackendError.UnknownError;

    // A custom component is used to bypass GTK's minimum size mechanism
    const wbin = wbin_new() orelse return common.BackendError.UnknownError;
    wbin_set_child(@ptrCast(wbin), layout);
    try Container.setupEvents(wbin);

    // Enable focus on Gtk.Fixed

    // Get the gtk_widget_focus_child method from Gtk.Box's class
    const focus_fn = blk: {
        const box_class = c.g_type_class_ref(c.gtk_box_get_type());
        defer c.g_type_class_unref(box_class);

        const box_widget_class: *c.GtkWidgetClass = @ptrCast(@alignCast(box_class));
        break :blk box_widget_class.focus;
    };

    const fixed_class = c.g_type_class_peek(c.gtk_fixed_get_type());
    const widget_class: *c.GtkWidgetClass = @ptrCast(@alignCast(fixed_class));
    // std.log.info("old: {*} new: {*}", .{ widget_class.focus, focus_fn });
    widget_class.focus = focus_fn;
    c.gtk_widget_class_set_accessible_role(widget_class, c.GTK_ACCESSIBLE_ROLE_GENERIC);

    return Container{ .peer = wbin, .container = layout };
}

pub fn add(self: *const Container, peer: *c.GtkWidget) void {
    c.gtk_fixed_put(@as(*c.GtkFixed, @ptrCast(self.container)), peer, 0, 0);
}

pub fn remove(self: *const Container, peer: *c.GtkWidget) void {
    // TODO(fix): the component might not be able to be added back
    // to fix this every peer type (Container, Button..) would have to hold a reference
    // that GTK knows about to their GtkWidget
    c.gtk_fixed_remove(@as(*c.GtkFixed, @ptrCast(self.container)), peer);
}

pub fn move(self: *const Container, peer: *c.GtkWidget, x: u32, y: u32) void {
    c.gtk_fixed_move(@ptrCast(self.container), peer, @floatFromInt(x), @floatFromInt(y));
    const data = common.getEventUserData(peer);
    data.actual_x = @intCast(x);
    data.actual_y = @intCast(y);
}

pub fn resize(self: *const Container, peer: *c.GtkWidget, w: u32, h: u32) void {
    _ = self;
    c.gtk_widget_set_size_request(peer, @as(c_int, @intCast(w)), @as(c_int, @intCast(h)));
    // c.gtk_container_resize_children(@as(*c.GtkContainer, @ptrCast(self.container)));
    // c.gtk_widget_allocate(peer, @intCast(w), @intCast(h), -1, null);
    c.gtk_widget_queue_resize(peer);
    common.widgetSizeChanged(peer, w, h);
}

pub fn setTabOrder(self: *const Container, peers: []const *c.GtkWidget) void {
    // std.log.info("{}", .{c.gtk_widget_grab_focus(peers[0])});
    var previous: ?*c.GtkWidget = null;
    for (peers) |peer| {
        c.gtk_widget_insert_after(peer, self.container, previous);
        previous = peer;
    }
}
