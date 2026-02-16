const std = @import("std");
const c = @import("gtk.zig");
const lib = @import("../../capy.zig");
const common = @import("common.zig");

const Slider = @This();
peer: *c.GtkWidget,

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

fn gtkValueChanged(peer: *c.GtkWidget, userdata: usize) callconv(.c) void {
    _ = userdata;
    const data = common.getEventUserData(peer);

    if (data.user.propertyChangeHandler) |handler| {
        const adjustment = c.gtk_range_get_adjustment(@as(*c.GtkRange, @ptrCast(peer)));
        const stepSize = c.gtk_adjustment_get_minimum_increment(adjustment);
        const value = c.gtk_range_get_value(@as(*c.GtkRange, @ptrCast(peer)));
        var adjustedValue = @round(value / stepSize) * stepSize;

        // check if it is equal to -0.0 (a quirk from IEEE 754), if it is then set to 0.0
        if (adjustedValue == 0 and std.math.copysign(@as(f64, 1.0), adjustedValue) == -1.0) {
            adjustedValue = 0.0;
        }

        if (!std.math.approxEqAbs(f64, value, adjustedValue, 0.001)) {
            c.gtk_range_set_value(@as(*c.GtkRange, @ptrCast(peer)), adjustedValue);
        } else {
            const value_f32 = @as(f32, @floatCast(adjustedValue));
            handler("value", &value_f32, data.userdata);
        }
    }
}

pub fn create() common.BackendError!Slider {
    const adjustment = c.gtk_adjustment_new(0, 0, 100 + 10, 10, 10, 10);
    const slider = c.gtk_scale_new(c.GTK_ORIENTATION_HORIZONTAL, adjustment) orelse return error.UnknownError;
    c.gtk_scale_set_draw_value(@as(*c.GtkScale, @ptrCast(slider)), @intFromBool(false));
    try Slider.setupEvents(slider);
    _ = c.g_signal_connect_data(slider, "value-changed", @as(c.GCallback, @ptrCast(&gtkValueChanged)), null, @as(c.GClosureNotify, null), 0);
    return Slider{ .peer = slider };
}

pub fn getValue(self: *const Slider) f32 {
    return @as(f32, @floatCast(c.gtk_range_get_value(@as(*c.GtkRange, @ptrCast(self.peer)))));
}

pub fn setValue(self: *Slider, value: f32) void {
    c.gtk_range_set_value(@as(*c.GtkRange, @ptrCast(self.peer)), value);
}

pub fn setMinimum(self: *Slider, minimum: f32) void {
    const adjustment = c.gtk_range_get_adjustment(@as(*c.GtkRange, @ptrCast(self.peer)));
    c.gtk_adjustment_set_lower(adjustment, minimum);
    c.gtk_range_set_adjustment(@as(*c.GtkRange, @ptrCast(self.peer)), adjustment);
}

pub fn setMaximum(self: *Slider, maximum: f32) void {
    const adjustment = c.gtk_range_get_adjustment(@as(*c.GtkRange, @ptrCast(self.peer)));
    c.gtk_adjustment_set_upper(adjustment, maximum + c.gtk_adjustment_get_step_increment(adjustment));
    c.gtk_range_set_adjustment(@as(*c.GtkRange, @ptrCast(self.peer)), adjustment);
}

pub fn setStepSize(self: *Slider, stepSize: f32) void {
    c.gtk_range_set_increments(@as(*c.GtkRange, @ptrCast(self.peer)), stepSize, stepSize * 10);
}

pub fn setEnabled(self: *Slider, enabled: bool) void {
    c.gtk_widget_set_sensitive(self.peer, @intFromBool(enabled));
}

pub fn setOrientation(self: *Slider, orientation: lib.Orientation) void {
    const gtkOrientation: c_uint = switch (orientation) {
        .Horizontal => c.GTK_ORIENTATION_HORIZONTAL,
        .Vertical => c.GTK_ORIENTATION_VERTICAL,
    };
    c.gtk_orientable_set_orientation(@as(*c.GtkOrientable, @ptrCast(self.peer)), gtkOrientation);
}

pub fn setTickCount(self: *Slider, count: u32) void {
    const scale: *c.GtkScale = @ptrCast(self.peer);
    c.gtk_scale_clear_marks(scale);
    if (count > 1) {
        const adjustment = c.gtk_range_get_adjustment(@as(*c.GtkRange, @ptrCast(self.peer)));
        const min_val = c.gtk_adjustment_get_lower(adjustment);
        const max_val = c.gtk_adjustment_get_upper(adjustment) - c.gtk_adjustment_get_step_increment(adjustment);
        const step = (max_val - min_val) / @as(f64, @floatFromInt(count - 1));
        for (0..count) |i| {
            const mark_value = min_val + step * @as(f64, @floatFromInt(i));
            c.gtk_scale_add_mark(scale, mark_value, c.GTK_POS_BOTTOM, null);
        }
    }
}

pub fn setSnapToTicks(self: *Slider, snap: bool) void {
    _ = self;
    _ = snap;
    // GTK doesn't have native snap-to-tick. The existing gtkValueChanged
    // callback already rounds to the step size, which provides snapping
    // when step is set to match tick intervals.
}
