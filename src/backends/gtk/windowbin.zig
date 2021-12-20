//! Class for a Bin container with a preferred size equals to zero
const std = @import("std");
const c = @import("backend.zig").c;

pub const WBin = extern struct { bin: c.GtkBin };

// Parent class is GtkContainerClass. But it and GtkWidgetClass fail to be translated by translate-c
const GtkBinClass = extern struct {
    parent_class: [1024]u8,
    _gtk_reserved1: ?fn () callconv(.C) void,
    _gtk_reserved2: ?fn () callconv(.C) void,
    _gtk_reserved3: ?fn () callconv(.C) void,
    _gtk_reserved4: ?fn () callconv(.C) void,
};

pub const WBinClass = extern struct { parent_class: GtkBinClass };

var wbin_type: c.GType = 0;

export fn wbin_get_type() c.GType {
    if (wbin_type == 0) {
        const wbin_info = std.mem.zeroInit(c.GTypeInfo, .{ .class_size = @sizeOf(WBinClass), .class_init = @ptrCast(c.GClassInitFunc, wbin_class_init), .instance_size = @sizeOf(WBin), .instance_init = @ptrCast(c.GInstanceInitFunc, wbin_init) });
        wbin_type = c.g_type_register_static(c.gtk_bin_get_type(), "WBin", &wbin_info, 0);
    }
    return wbin_type;
}

pub const edited_GtkWidgetClass = extern struct {
    parent_class: c.GInitiallyUnownedClass,
    activate_signal: c.guint,
    dispatch_child_properties_changed: ?fn ([*c]c.GtkWidget, c.guint, [*c][*c]c.GParamSpec) callconv(.C) void,
    destroy: ?fn ([*c]c.GtkWidget) callconv(.C) void,
    show: ?fn ([*c]c.GtkWidget) callconv(.C) void,
    show_all: ?fn ([*c]c.GtkWidget) callconv(.C) void,
    hide: ?fn ([*c]c.GtkWidget) callconv(.C) void,
    map: ?fn ([*c]c.GtkWidget) callconv(.C) void,
    unmap: ?fn ([*c]c.GtkWidget) callconv(.C) void,
    realize: ?fn ([*c]c.GtkWidget) callconv(.C) void,
    unrealize: ?fn ([*c]c.GtkWidget) callconv(.C) void,
    size_allocate: ?fn ([*c]c.GtkWidget, [*c]c.GtkAllocation) callconv(.C) void,
    state_changed: ?fn ([*c]c.GtkWidget, c.GtkStateType) callconv(.C) void,
    state_flags_changed: ?fn ([*c]c.GtkWidget, c.GtkStateFlags) callconv(.C) void,
    parent_set: ?fn ([*c]c.GtkWidget, [*c]c.GtkWidget) callconv(.C) void,
    hierarchy_changed: ?fn ([*c]c.GtkWidget, [*c]c.GtkWidget) callconv(.C) void,
    style_set: ?fn ([*c]c.GtkWidget, [*c]c.GtkStyle) callconv(.C) void,
    direction_changed: ?fn ([*c]c.GtkWidget, c.GtkTextDirection) callconv(.C) void,
    grab_notify: ?fn ([*c]c.GtkWidget, c.gboolean) callconv(.C) void,
    child_notify: ?fn ([*c]c.GtkWidget, [*c]c.GParamSpec) callconv(.C) void,
    draw: ?fn ([*c]c.GtkWidget, ?*c.cairo_t) callconv(.C) c.gboolean,
    get_request_mode: ?fn ([*c]c.GtkWidget) callconv(.C) c.GtkSizeRequestMode,
    get_preferred_height: ?fn ([*c]c.GtkWidget, [*c]c.gint, [*c]c.gint) callconv(.C) void,
    get_preferred_width_for_height: ?fn ([*c]c.GtkWidget, c.gint, [*c]c.gint, [*c]c.gint) callconv(.C) void,
    get_preferred_width: ?fn ([*c]c.GtkWidget, [*c]c.gint, [*c]c.gint) callconv(.C) void,
    get_preferred_height_for_width: ?fn ([*c]c.GtkWidget, c.gint, [*c]c.gint, [*c]c.gint) callconv(.C) void,
};

fn wbin_class_init(class: *WBinClass) callconv(.C) void {
    _ = class;
    const widget_class = @ptrCast(*edited_GtkWidgetClass, class);
    widget_class.get_preferred_width = wbin_get_preferred_width;
    widget_class.get_preferred_height = wbin_get_preferred_height;
    widget_class.size_allocate = wbin_size_allocate;
}

fn wbin_get_preferred_width(widget: ?*c.GtkWidget, minimum_width: ?*c.gint, natural_width: ?*c.gint) callconv(.C) void {
    _ = widget;
    minimum_width.?.* = 0;
    natural_width.?.* = 0;
}

fn wbin_get_preferred_height(widget: ?*c.GtkWidget, minimum_height: ?*c.gint, natural_height: ?*c.gint) callconv(.C) void {
    _ = widget;
    minimum_height.?.* = 0;
    natural_height.?.* = 0;
}

fn wbin_child_allocate(child: ?*c.GtkWidget, ptr: ?*anyopaque) callconv(.C) void {
    const allocation = @ptrCast(?*c.GtkAllocation, @alignCast(@alignOf(c.GtkAllocation), ptr));
    c.gtk_widget_size_allocate(child, allocation);
}

fn wbin_size_allocate(widget: ?*c.GtkWidget, allocation: ?*c.GtkAllocation) callconv(.C) void {
    c.gtk_widget_set_allocation(widget, allocation);
    c.gtk_container_forall(@ptrCast(?*c.GtkContainer, widget), wbin_child_allocate, allocation);
}

export fn wbin_init(wbin: *WBin, class: *WBinClass) void {
    _ = wbin;
    _ = class;

    // TODO
}

pub fn wbin_new() ?*c.GtkWidget {
    return @ptrCast(?*c.GtkWidget, @alignCast(@alignOf(c.GtkWidget), c.g_object_new(wbin_get_type(), null)));
}
