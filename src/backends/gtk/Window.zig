const std = @import("std");
const c = @import("gtk.zig");
const lib = @import("../../capy.zig");
const common = @import("common.zig");
const Monitor = @import("Monitor.zig");
const ImageData = @import("ImageData.zig");

// WindowBin
const wbin_new = @import("windowbin.zig").wbin_new;
const wbin_set_child = @import("windowbin.zig").wbin_set_child;

// === GLOBAL VARIABLES ===
pub var randomWindow: *c.GtkWidget = undefined;
// === END GLOBAL VARIABLES ===

const Window = @This();

peer: *c.GtkWidget,
wbin: *c.GtkWidget,
/// A VBox is required to contain the menu and the window's child (wrapped in wbin)
vbox: *c.GtkWidget,
menuBar: ?*c.GtkWidget = null,
source_dpi: u32 = 96,
scale: f32 = 1.0,
child: ?*c.GtkWidget = null,

pub usingnamespace common.Events(Window);

pub fn create() common.BackendError!Window {
    const window = c.gtk_window_new() orelse return error.UnknownError;
    const wbin = wbin_new() orelse unreachable;
    c.gtk_widget_set_vexpand(wbin, 1);
    c.gtk_widget_set_vexpand_set(wbin, 1);

    const vbox = c.gtk_box_new(c.GTK_ORIENTATION_VERTICAL, 0) orelse return error.UnknownError;
    c.gtk_box_append(@ptrCast(vbox), wbin);

    c.gtk_window_set_child(@ptrCast(window), vbox);
    c.gtk_widget_show(window);
    c.gtk_widget_map(window);

    randomWindow = window;
    try Window.setupEvents(window);

    const surface = c.gtk_native_get_surface(@ptrCast(window));
    _ = c.g_signal_connect_data(surface, "layout", @ptrCast(&gtkLayout), window, null, c.G_CONNECT_AFTER);
    _ = c.g_signal_connect_data(window, "close-request", @as(c.GCallback, @ptrCast(&gtkCloseRequest)), null, null, c.G_CONNECT_AFTER);
    return Window{ .peer = window, .wbin = wbin, .vbox = vbox };
}

fn gtkLayout(peer: *c.GdkSurface, width: c.gint, height: c.gint, userdata: ?*anyopaque) callconv(.C) c.gint {
    _ = peer;
    const window: *c.GtkWidget = @ptrCast(@alignCast(userdata.?));
    const data = common.getEventUserData(window);

    const child = c.gtk_widget_get_first_child(
        c.gtk_widget_get_last_child(
            c.gtk_window_get_child(@ptrCast(window)),
        ),
    );
    if (child == null) return 0;

    const child_data = common.getEventUserData(child);

    const w_changed = if (child_data.actual_width) |old_width| width != old_width else true;
    const h_changed = if (child_data.actual_height) |old_height| height != old_height else true;
    const size_changed = w_changed or h_changed;
    child_data.actual_width = @intCast(width);
    child_data.actual_height = @intCast(height);
    if (data.class.resizeHandler) |handler|
        handler(@as(u32, @intCast(width)), @as(u32, @intCast(height)), @intFromPtr(data));
    if (data.user.resizeHandler) |handler|
        handler(@as(u32, @intCast(width)), @as(u32, @intCast(height)), data.userdata);
    if (size_changed) {
        if (child_data.class.resizeHandler) |handler|
            handler(@as(u32, @intCast(width)), @as(u32, @intCast(height)), @intFromPtr(child_data));
        if (child_data.user.resizeHandler) |handler|
            handler(@as(u32, @intCast(width)), @as(u32, @intCast(height)), child_data.userdata);
    }
    return 0;
}

fn gtkCloseRequest(peer: *c.GtkWindow, userdata: ?*anyopaque) callconv(.C) c.gint {
    _ = userdata;
    const data = common.getEventUserData(@ptrCast(peer));
    const value_bool: bool = false;
    if (data.class.propertyChangeHandler) |handler|
        handler("visible", &value_bool, data.userdata);
    if (data.user.propertyChangeHandler) |handler|
        handler("visible", &value_bool, data.userdata);

    return 0;
}

pub fn resize(self: *Window, width: c_int, height: c_int) void {
    c.gtk_window_set_default_size(@ptrCast(self.peer), width, height);
}

pub fn setTitle(self: *Window, title: [*:0]const u8) void {
    c.gtk_window_set_title(@as(*c.GtkWindow, @ptrCast(self.peer)), title);
}

pub fn setIcon(self: *Window, data: ImageData) void {
    // Currently a no-op, as GTK only allows setting icon during distribution.
    // That is the app must have a resource folder containing desired icons.
    // TODO: maybe this could be done by creating a temporary directory and using gtk_icon_theme_add_search_path
    _ = self;
    _ = data;
}

pub fn setChild(self: *Window, peer: ?*c.GtkWidget) void {
    self.child = peer;
    wbin_set_child(@ptrCast(self.wbin), peer);
}

pub fn setMenuBar(self: *Window, bar: lib.MenuBar) void {
    const menuBar = c.gtk_popover_menu_bar_new_from_model(null).?;
    const menuModel = c.g_menu_new().?;
    initMenu(menuModel, bar.menus);

    c.gtk_popover_menu_bar_set_menu_model(@ptrCast(menuBar), @ptrCast(@alignCast(menuModel)));

    c.gtk_box_prepend(@as(*c.GtkBox, @ptrCast(self.vbox)), menuBar);
    self.menuBar = menuBar;
}

pub fn setSourceDpi(self: *Window, dpi: u32) void {
    self.source_dpi = 96;
    // TODO: Handle GtkWindow moving between screens with different DPIs
    const resolution = @as(f32, 96.0);
    self.scale = resolution / @as(f32, @floatFromInt(dpi));
}

fn initMenu(menu: *c.GMenu, items: []const lib.MenuItem) void {
    for (items) |item| {
        if (item.items.len > 0) {
            // The menu associated to the menu item
            const submenu = c.g_menu_new().?;
            initMenu(submenu, item.items);
            c.g_menu_append_submenu(menu, item.config.label, @ptrCast(@alignCast(submenu)));
        } else {
            const menu_item = c.g_menu_item_new(item.config.label, null).?;
            c.g_menu_append_item(menu, menu_item);
            if (item.config.onClick) |callback| {
                const new_action = c.g_simple_action_new(item.config.label, null); // TODO: some unique id
                const data = @as(?*anyopaque, @ptrFromInt(@intFromPtr(callback)));
                _ = c.g_signal_connect_data(new_action, "activate", @as(c.GCallback, @ptrCast(&gtkActivate)), data, null, c.G_CONNECT_AFTER);
                c.g_menu_item_set_action_and_target_value(menu_item, item.config.label, null);
            }
        }
    }
}

fn gtkActivate(peer: *c.GAction, userdata: ?*anyopaque) callconv(.C) void {
    _ = peer;

    const callback = @as(*const fn () void, @ptrCast(userdata.?));
    callback();
}

pub fn setFullscreen(self: *Window, monitor: ?*Monitor, video_mode: ?lib.VideoMode) void {
    if (monitor) |mon| {
        // Video mode is ignored as for now, GTK doesn't support exclusive fullscreen
        _ = video_mode;

        c.gtk_window_fullscreen_on_monitor(@ptrCast(self.peer), mon.peer);
    } else {
        c.gtk_window_fullscreen(@ptrCast(self.peer));
    }
}

pub fn unfullscreen(self: *Window) void {
    c.gtk_window_unfullscreen(@ptrCast(self.peer));
}

pub fn show(self: *Window) void {
    c.gtk_widget_show(self.peer);
    const data = common.getEventUserData(self.peer);
    const value_bool: bool = true;
    if (data.class.propertyChangeHandler) |handler|
        handler("visible", &value_bool, data.userdata);
    if (data.user.propertyChangeHandler) |handler|
        handler("visible", &value_bool, data.userdata);
}

pub fn registerTickCallback(self: *Window) void {
    _ = c.gtk_widget_add_tick_callback(
        self.peer,
        &tickCallback,
        null,
        null,
    );
}

/// Callback called by GTK on each frame (tied to the monitor's sync rate)
fn tickCallback(
    widget: ?*c.GtkWidget,
    frame_clock: ?*c.GdkFrameClock,
    user_data: ?*anyopaque,
) callconv(.C) c.gboolean {
    _ = frame_clock;
    _ = user_data;
    const data = common.getEventUserData(widget.?);
    if (data.user.propertyChangeHandler) |handler| {
        const id: u64 = 0;
        handler("tick_id", &id, data.userdata);
    }
    return @intFromBool(c.G_SOURCE_CONTINUE);
}

pub fn close(self: *Window) void {
    c.gtk_window_close(@as(*c.GtkWindow, @ptrCast(self.peer)));
}
