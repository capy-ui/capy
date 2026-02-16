const std = @import("std");
const c = @import("gtk.zig");
const lib = @import("../../capy.zig");
const common = @import("common.zig");
const wbin_new = @import("windowbin.zig").wbin_new;
const wbin_set_child = @import("windowbin.zig").wbin_set_child;
const ImageData = @import("ImageData.zig");

const NavigationSidebar = @This();

peer: *c.GtkWidget,
list: *c.GtkWidget,

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

pub fn create() common.BackendError!NavigationSidebar {
    const listBox = c.gtk_list_box_new();
    const context: *c.GtkStyleContext = c.gtk_widget_get_style_context(listBox);
    c.gtk_style_context_add_class(context, "navigation-sidebar");

    // A custom component is used to bypass GTK's minimum size mechanism
    const wbin = wbin_new() orelse return common.BackendError.UnknownError;
    wbin_set_child(@ptrCast(wbin), listBox);
    try NavigationSidebar.setupEvents(wbin);

    var sidebar = NavigationSidebar{ .peer = wbin, .list = listBox };
    sidebar.append(undefined, "Test");
    return sidebar;
}

pub fn append(self: *NavigationSidebar, image: ImageData, label: [:0]const u8) void {
    const box = c.gtk_box_new(c.GTK_ORIENTATION_HORIZONTAL, 6);
    // TODO: append not prepend
    c.gtk_list_box_prepend(@as(*c.GtkListBox, @ptrCast(self.list)), box);

    _ = image;
    const icon = c.gtk_image_new_from_icon_name("dialog-warning-symbolic");
    // TODO: create GtkImage from ImageData
    c.gtk_box_append(@ptrCast(box), icon);

    const label_gtk = c.gtk_label_new(label);
    c.gtk_box_append(@ptrCast(box), label_gtk);

    const context: *c.GtkStyleContext = c.gtk_widget_get_style_context(box);
    c.gtk_style_context_add_class(context, "activatable");
    c.gtk_style_context_add_class(context, "row");
}

pub fn getPreferredSize_impl(self: *const NavigationSidebar) lib.Size {
    _ = self;
    return lib.Size.init(
        @as(u32, @intCast(200)),
        @as(u32, @intCast(100)),
    );
}
