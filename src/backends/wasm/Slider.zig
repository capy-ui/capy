const std = @import("std");
const common = @import("common.zig");
const js = @import("js.zig");
const lib = @import("../../capy.zig");
const GuiWidget = common.GuiWidget;
const Events = common.Events;

const Slider = @This();

peer: *GuiWidget,

pub usingnamespace Events(Slider);

pub fn create() !Slider {
    return Slider{
        .peer = try GuiWidget.init(
            Slider,
            lib.lasting_allocator,
            "input",
            "slider",
        ),
    };
}

pub fn getValue(self: *const Slider) f32 {
    return js.getValue(self.peer.element);
}

pub fn setValue(self: *Slider, value: f32) void {
    var buf: [100]u8 = undefined;
    const slice = std.fmt.bufPrint(&buf, "{}", .{value}) catch unreachable;
    js.setAttribute(self.peer.element, "value", slice);
}

pub fn setMinimum(self: *Slider, minimum: f32) void {
    var buf: [100]u8 = undefined;
    const slice = std.fmt.bufPrint(&buf, "{}", .{minimum}) catch unreachable;
    js.setAttribute(self.peer.element, "min", slice);
}

pub fn setMaximum(self: *Slider, maximum: f32) void {
    var buf: [100]u8 = undefined;
    const slice = std.fmt.bufPrint(&buf, "{}", .{maximum}) catch unreachable;
    js.setAttribute(self.peer.element, "max", slice);
}

pub fn setStepSize(self: *Slider, stepSize: f32) void {
    var buf: [100]u8 = undefined;
    const slice = std.fmt.bufPrint(&buf, "{}", .{stepSize}) catch unreachable;
    js.setAttribute(self.peer.element, "step", slice);
}

pub fn setEnabled(self: *Slider, enable: bool) void {
    if (enable) {
        js.removeAttribute(self.peer.element, "disabled");
    } else {
        js.setAttribute(self.peer.element, "disabled", "disabled");
    }
}

pub fn setOrientation(self: *Slider, orientation: lib.Orientation) void {
    _ = orientation;
    _ = self;
}
