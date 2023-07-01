//! Class for a Bin container with a preferred size equals to zero
const std = @import("std");
const c = @import("backend.zig").c;

pub const WBin = extern struct { widget: c.GtkWidget };

// Parent class is GtkContainerClass. But it and GtkWidgetClass fail to be translated by translate-c
// TODO boxclass
const GtkBoxClass = extern struct {
    parent_class: [1024]u8,
    _gtk_reserved1: ?*const fn () callconv(.C) void,
    _gtk_reserved2: ?*const fn () callconv(.C) void,
    _gtk_reserved3: ?*const fn () callconv(.C) void,
    _gtk_reserved4: ?*const fn () callconv(.C) void,
};

pub const WBinClass = extern struct { parent_class: GtkBoxClass };

var wbin_type: c.GType = 0;

export fn wbin_get_type() c.GType {
    if (wbin_type == 0) {
        const wbin_info = std.mem.zeroInit(c.GTypeInfo, .{
            .class_size = @sizeOf(WBinClass),
            .class_init = @as(c.GClassInitFunc, @ptrCast(&wbin_class_init)),
            .instance_size = @sizeOf(WBin),
            .instance_init = @as(c.GInstanceInitFunc, @ptrCast(&wbin_init)),
        });
        wbin_type = c.g_type_register_static(c.gtk_box_get_type(), "WBin", &wbin_info, 0);
    }
    return wbin_type;
}

fn wbin_class_init(class: *WBinClass) callconv(.C) void {
    const widget_class = @as(*c.GtkWidgetClass, @ptrCast(class));
    // widget_class.get_preferred_width = wbin_get_preferred_width;
    // widget_class.get_preferred_height = wbin_get_preferred_height;
    widget_class.measure = &wbin_measure;
    widget_class.size_allocate = &wbin_size_allocate;
    widget_class.get_request_mode = &wbin_get_request_mode;
}

fn wbin_measure(widget: [*c]c.GtkWidget, orientation: c.GtkOrientation, for_size: c_int, minimum: [*c]c_int, natural: [*c]c_int, minimum_baseline: [*c]c_int, natural_baseline: [*c]c_int) callconv(.C) void {
    _ = orientation;
    _ = for_size;
    _ = widget;
    minimum.* = 0;
    natural.* = 0;
    minimum_baseline.* = -1; // no baseline
    natural_baseline.* = -1; // no baseline
}

fn wbin_get_request_mode(widget: ?*c.GtkWidget) callconv(.C) c.GtkSizeRequestMode {
    _ = widget;
    return c.GTK_SIZE_REQUEST_CONSTANT_SIZE;
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
    const allocation = @as(?*c.GtkAllocation, @ptrCast(@alignCast(ptr)));
    c.gtk_widget_size_allocate(child, allocation);
}

fn wbin_size_allocate(
    widget: ?*c.GtkWidget,
    width: c_int,
    height: c_int,
    baseline: c_int,
) callconv(.C) void {
    _ = baseline;
    _ = height;
    _ = width;
    _ = widget;
    // TODO: ???
    // c.gtk_widget_set_allocation(widget, allocation);
    // c.gtk_container_forall(@as(?*c.GtkContainer, @ptrCast(widget)), wbin_child_allocate, allocation);
}

export fn wbin_init(wbin: *WBin, class: *WBinClass) void {
    _ = class;

    // TODO
    c.gtk_box_set_homogeneous(@ptrCast(wbin), @intFromBool(true));
}

pub fn wbin_new() ?*c.GtkWidget {
    return @as(?*c.GtkWidget, @ptrCast(@alignCast(c.g_object_new(wbin_get_type(), null))));
}
