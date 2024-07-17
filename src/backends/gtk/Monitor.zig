const std = @import("std");
const lib = @import("../../main.zig");
const c = @import("gtk.zig");
const Monitor = @This();

var monitor_list: ?[]Monitor = null;

peer: *c.GdkMonitor,
internal_name: ?[]const u8 = null,

pub fn getList() []Monitor {
    if (monitor_list) |list| {
        return list;
    } else {
        // TODO: gdk_display_manager_list_displays
        const display = c.gdk_display_get_default();
        const list_model = c.gdk_display_get_monitors(display);
        const n: usize = c.g_list_model_get_n_items(list_model);
        const list = lib.internal.lasting_allocator.alloc(Monitor, n) catch @panic("OOM");

        for (0..c.g_list_model_get_n_items(list_model)) |i| {
            const item: *c.GdkMonitor = @ptrCast(c.g_list_model_get_item(list_model, @intCast(i)).?);
            list[i] = Monitor{ .peer = item };
        }
        monitor_list = list;
        return list;
    }
}

pub fn deinitAllPeers() void {
    if (monitor_list) |list| {
        for (list) |*monitor| monitor.deinit();
        lib.internal.lasting_allocator.free(list);
        monitor_list = null;
    }
}

pub fn getName(self: *Monitor) []const u8 {
    // TODO: detect if GTK version is >= 4.10 and use c.gdk_monitor_get_description if so is the case.
    return std.mem.span(c.gdk_monitor_get_connector(self.peer));
}

pub fn getInternalName(self: *Monitor) []const u8 {
    if (self.internal_name) |internal_name| {
        return internal_name;
    } else {
        self.internal_name = std.mem.concat(lib.internal.lasting_allocator, u8, &.{
            std.mem.span(c.gdk_monitor_get_manufacturer(self.peer) orelse @as([:0]const u8, "").ptr),
            std.mem.span(c.gdk_monitor_get_model(self.peer) orelse @as([:0]const u8, "").ptr),
        }) catch @panic("OOM");
        return self.internal_name.?;
    }
}

pub fn getWidth(self: *Monitor) u32 {
    var geometry: c.GdkRectangle = undefined;
    c.gdk_monitor_get_geometry(self.peer, &geometry);
    return @intCast(geometry.width * c.gdk_monitor_get_scale_factor(self.peer));
}

pub fn getHeight(self: *Monitor) u32 {
    var geometry: c.GdkRectangle = undefined;
    c.gdk_monitor_get_geometry(self.peer, &geometry);
    return @intCast(geometry.height * c.gdk_monitor_get_scale_factor(self.peer));
}

pub fn getRefreshRateMillihertz(self: *Monitor) u32 {
    return @intCast(c.gdk_monitor_get_refresh_rate(self.peer));
}

pub fn getDpi(self: *Monitor) u32 {
    // As GTK+ 4 doesn't have proper fractional scaling support (or atleast not on all versions of GTK+ 4), text
    // scaling is used instead. This is correct "enough", as this is in fact the setting that is changed by Desktop
    // Environments (like KDE or GNOME) when changing the display scale.
    const display = c.gdk_monitor_get_display(self.peer).?;
    var xft_dpi_gvalue: c.GValue = std.mem.zeroes(c.GValue);
    _ = c.g_value_init(&xft_dpi_gvalue, c.G_TYPE_INT);
    std.debug.assert(c.gdk_display_get_setting(display, "gtk-xft-dpi", &xft_dpi_gvalue) != 0);
    const xft_dpi = c.g_value_get_int(&xft_dpi_gvalue);
    const dpi = @as(f32, @floatFromInt(xft_dpi)) / 1024.0;

    // The DPI must be further multiplied by GTK's scale factor.
    return @intFromFloat(@round(
        dpi * @as(f32, @floatFromInt(c.gdk_monitor_get_scale_factor(self.peer))),
    ));
}

pub fn getNumberOfVideoModes(self: *Monitor) usize {
    // TODO: find a way to actually list video modes on GTK+
    _ = self;
    return 1;
}

pub fn getVideoMode(self: *Monitor, index: usize) lib.VideoMode {
    _ = index;
    return .{
        .width = self.getWidth(),
        .height = self.getHeight(),
        .refresh_rate_millihertz = self.getRefreshRateMillihertz(),
        .bit_depth = 32,
    };
}

pub fn deinit(self: *Monitor) void {
    if (self.internal_name) |internal_name| {
        lib.internal.lasting_allocator.free(internal_name);
        self.internal_name = null;
    }
}
