const std = @import("std");
const backend = @import("../backend.zig");
const Size = @import("../data.zig").Size;
const Atom = @import("../data.zig").Atom;

pub const Orientation = enum { Horizontal, Vertical };

/// A slider that the user can move to set a numerical value.
/// From MSDN :
///   > Use a slider when you want your users to be able to set defined, contiguous values (such as volume or brightness) or a range of discrete values (such as screen resolution settings).
///   > A slider is a good choice when you know that users think of the value as a relative quantity, not a numeric value. For example, users think about setting their audio volume to low or medium—not about setting the value to 2 or 5.
///
/// To avoid any cross-platform bugs, ensure that min/stepSize and
/// max/stepSize both are between -32767 and 32768.
pub const Slider = struct {
    pub usingnamespace @import("../internal.zig").All(Slider);

    peer: ?backend.Slider = null,
    widget_data: Slider.WidgetData = .{},
    value: Atom(f32) = Atom(f32).of(0),
    /// The minimum value of the slider.
    /// Note that min MUST be below or equal to max.
    min: Atom(f32),
    /// The maximum value of the slider.
    /// Note that max MUST be above or equal to min.
    max: Atom(f32),
    /// The size of one increment of the value.
    /// This means the value can only be a multiple of step.
    step: Atom(f32) = Atom(f32).of(1),
    enabled: Atom(bool) = Atom(bool).of(true),

    pub fn init() Slider {
        return Slider.init_events(Slider{
            .min = Atom(f32).of(undefined),
            .max = Atom(f32).of(undefined),
        });
    }

    pub fn _pointerMoved(self: *Slider) void {
        self.enabled.updateBinders();
    }

    fn wrapperValueChanged(newValue: f32, userdata: usize) void {
        const peer = @as(*?backend.Slider, @ptrFromInt(userdata));
        peer.*.?.setValue(newValue);
    }

    fn wrapperMinChanged(newValue: f32, userdata: usize) void {
        const peer = @as(*?backend.Slider, @ptrFromInt(userdata));
        peer.*.?.setMinimum(newValue);
    }

    fn wrapperMaxChanged(newValue: f32, userdata: usize) void {
        const peer = @as(*?backend.Slider, @ptrFromInt(userdata));
        peer.*.?.setMaximum(newValue);
    }

    fn wrapperStepChanged(newValue: f32, userdata: usize) void {
        const peer = @as(*?backend.Slider, @ptrFromInt(userdata));
        peer.*.?.setStepSize(@fabs(newValue));
    }

    fn wrapperEnabledChanged(newValue: bool, userdata: usize) void {
        const peer = @as(*?backend.Slider, @ptrFromInt(userdata));
        peer.*.?.setEnabled(newValue);
    }

    fn onPropertyChange(self: *Slider, property_name: []const u8, new_value: *const anyopaque) !void {
        if (std.mem.eql(u8, property_name, "value")) {
            const value = @as(*const f32, @ptrCast(@alignCast(new_value)));
            self.value.set(value.*);
        }
    }

    pub fn show(self: *Slider) !void {
        if (self.peer == null) {
            self.peer = try backend.Slider.create();
            self.peer.?.setMinimum(self.min.get());
            self.peer.?.setMaximum(self.max.get());
            self.peer.?.setValue(self.value.get());
            self.peer.?.setStepSize(@fabs(self.step.get()));
            self.peer.?.setEnabled(self.enabled.get());
            try self.show_events();

            _ = try self.value.addChangeListener(.{ .function = wrapperValueChanged, .userdata = @intFromPtr(&self.peer) });
            _ = try self.min.addChangeListener(.{ .function = wrapperMinChanged, .userdata = @intFromPtr(&self.peer) });
            _ = try self.max.addChangeListener(.{ .function = wrapperMaxChanged, .userdata = @intFromPtr(&self.peer) });
            _ = try self.enabled.addChangeListener(.{ .function = wrapperEnabledChanged, .userdata = @intFromPtr(&self.peer) });
            _ = try self.step.addChangeListener(.{ .function = wrapperStepChanged, .userdata = @intFromPtr(&self.peer) });

            try self.addPropertyChangeHandler(&onPropertyChange);
        }
    }

    pub fn getPreferredSize(self: *Slider, available: Size) Size {
        _ = available;
        if (self.peer) |peer| {
            return peer.getPreferredSize();
        } else {
            return Size{ .width = 100.0, .height = 40.0 };
        }
    }

    pub fn _deinit(self: *Slider) void {
        self.enabled.deinit();
    }
};

pub fn slider(config: Slider.Config) Slider {
    var s = Slider.init();
    s.min.set(config.min);
    s.max.set(config.max);
    s.value.set(config.value);
    s.step.set(config.step);
    s.enabled.set(config.enabled);
    s.widget_data.atoms.name.set(config.name);
    if (config.onclick) |onclick| {
        s.addClickHandler(onclick) catch unreachable; // TODO: improve
    }
    return s;
}
