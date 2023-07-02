//! Class for a Bin container with a preferred size equals to zero
const std = @import("std");
const c = @import("backend.zig").c;

pub const WBin = extern struct { widget: c.GtkWidget };
pub const WBinClass = extern struct {
    parent_class: c.GtkWidgetClass,
    padding: [8]u8,
};

var wbin_type: c.GType = 0;

export fn wbin_get_type() c.GType {
    if (wbin_type == 0) {
        const wbin_info = std.mem.zeroInit(c.GTypeInfo, .{
            .class_size = @sizeOf(WBinClass),
            .class_init = @as(c.GClassInitFunc, @ptrCast(&wbin_class_init)),
            .instance_size = @sizeOf(WBin),
            .instance_init = @as(c.GInstanceInitFunc, @ptrCast(&wbin_init)),
        });
        // wbin_type = c.g_type_register_static(c.gtk_box_get_type(), "WBin", &wbin_info, 0);
        wbin_type = c.g_type_register_static(c.gtk_widget_get_type(), "WrapperBin", &wbin_info, 0);
    }
    return wbin_type;
}

fn wbin_class_init(class: *WBinClass) callconv(.C) void {
    const widget_class = @as(*c.GtkWidgetClass, @ptrCast(class));
    // widget_class.measure = wbin_measure;
    widget_class.size_allocate = wbin_size_allocate;
    // widget_class.get_request_mode = wbin_get_request_mode;
}

fn wbin_measure(widget: [*c]c.GtkWidget, orientation: c.GtkOrientation, for_size: c_int, minimum: [*c]c_int, natural: [*c]c_int, minimum_baseline: [*c]c_int, natural_baseline: [*c]c_int) callconv(.C) void {
    _ = orientation;
    _ = for_size;
    _ = widget;
    minimum.* = 0;
    natural.* = 100;
    minimum_baseline.* = -1; // no baseline
    natural_baseline.* = -1; // no baseline
}

fn wbin_get_request_mode(widget: ?*c.GtkWidget) callconv(.C) c.GtkSizeRequestMode {
    _ = widget;
    return c.GTK_SIZE_REQUEST_CONSTANT_SIZE;
}

fn wbin_size_allocate(
    widget: ?*c.GtkWidget,
    width: c_int,
    height: c_int,
    baseline: c_int,
) callconv(.C) void {
    const child = c.gtk_widget_get_first_child(widget);
    if (child != null) {
        c.gtk_widget_allocate(child, width, height, baseline, null);
    }
}

export fn wbin_init(wbin: *WBin, class: *WBinClass) void {
    _ = wbin;
    _ = class;
    // c.gtk_box_set_homogeneous(@ptrCast(wbin), @intFromBool(true));
}

pub fn wbin_new() ?*c.GtkWidget {
    return @as(?*c.GtkWidget, @ptrCast(@alignCast(c.g_object_new(wbin_get_type(), null))));
}

pub fn wbin_set_child(self: *WBin, child: ?*c.GtkWidget) void {
    // TODO: remove old child
    const old_child = c.gtk_widget_get_first_child(@ptrCast(self));
    _ = old_child;

    if (child != null) {
        c.gtk_widget_set_parent(child, @ptrCast(self));
        c.gtk_widget_show(child);
    }
}
