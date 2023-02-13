const std = @import("std");
const backend = @import("../backend.zig");
const Size = @import("../data.zig").Size;
const DataWrapper = @import("../data.zig").DataWrapper;

pub const Orientation = enum { Horizontal, Vertical };

/// A slider that the user can move to set a numerical value.
/// From MSDN :
///   > Use a slider when you want your users to be able to set defined, contiguous values (such as volume or brightness) or a range of discrete values (such as screen resolution settings).
///   > A slider is a good choice when you know that users think of the value as a relative quantity, not a numeric value. For example, users think about setting their audio volume to low or medium—not about setting the value to 2 or 5.
///
/// To avoid any cross-platform bugs, ensure that min/stepSize and
/// max/stepSize both are between -32767 and 32768.
pub const Slider_Impl = struct {
    pub usingnamespace @import("../internal.zig").All(Slider_Impl);

    peer: ?backend.Slider = null,
    handlers: Slider_Impl.Handlers = undefined,
    dataWrappers: Slider_Impl.DataWrappers = .{},
    value: DataWrapper(f32) = DataWrapper(f32).of(0),
    /// The minimum value of the slider.
    /// Note that min MUST be below or equal to max.
    min: DataWrapper(f32),
    /// The maximum value of the slider.
    /// Note that max MUST be above or equal to min.
    max: DataWrapper(f32),
    /// The size of one increment of the value.
    /// This means the value can only be a multiple of step.
    step: DataWrapper(f32) = DataWrapper(f32).of(1),
    enabled: DataWrapper(bool) = DataWrapper(bool).of(true),

    pub fn init() Slider_Impl {
        return Slider_Impl.init_events(Slider_Impl{
            .min = DataWrapper(f32).of(undefined),
            .max = DataWrapper(f32).of(undefined),
        });
    }

    pub fn _pointerMoved(self: *Slider_Impl) void {
        self.enabled.updateBinders();
    }

    fn wrapperValueChanged(newValue: f32, userdata: usize) void {
        const peer = @intToPtr(*?backend.Slider, userdata);
        peer.*.?.setValue(newValue);
    }

    fn wrapperMinChanged(newValue: f32, userdata: usize) void {
        const peer = @intToPtr(*?backend.Slider, userdata);
        peer.*.?.setMinimum(newValue);
    }

    fn wrapperMaxChanged(newValue: f32, userdata: usize) void {
        const peer = @intToPtr(*?backend.Slider, userdata);
        peer.*.?.setMaximum(newValue);
    }

    fn wrapperStepChanged(newValue: f32, userdata: usize) void {
        const peer = @intToPtr(*?backend.Slider, userdata);
        peer.*.?.setStepSize(@fabs(newValue));
    }

    fn wrapperEnabledChanged(newValue: bool, userdata: usize) void {
        const peer = @intToPtr(*?backend.Slider, userdata);
        peer.*.?.setEnabled(newValue);
    }

    fn onPropertyChange(self: *Slider_Impl, property_name: []const u8, new_value: *const anyopaque) !void {
        if (std.mem.eql(u8, property_name, "value")) {
            const value = @ptrCast(*const f32, @alignCast(@alignOf(f32), new_value));
            self.value.set(value.*);
        }
    }

    pub fn show(self: *Slider_Impl) !void {
        if (self.peer == null) {
            self.peer = try backend.Slider.create();
            self.peer.?.setMinimum(self.min.get());
            self.peer.?.setMaximum(self.max.get());
            self.peer.?.setValue(self.value.get());
            self.peer.?.setStepSize(@fabs(self.step.get()));
            self.peer.?.setEnabled(self.enabled.get());
            try self.show_events();

            _ = try self.value.addChangeListener(.{ .function = wrapperValueChanged, .userdata = @ptrToInt(&self.peer) });
            _ = try self.min.addChangeListener(.{ .function = wrapperMinChanged, .userdata = @ptrToInt(&self.peer) });
            _ = try self.max.addChangeListener(.{ .function = wrapperMaxChanged, .userdata = @ptrToInt(&self.peer) });
            _ = try self.enabled.addChangeListener(.{ .function = wrapperEnabledChanged, .userdata = @ptrToInt(&self.peer) });
            _ = try self.step.addChangeListener(.{ .function = wrapperStepChanged, .userdata = @ptrToInt(&self.peer) });

            try self.addPropertyChangeHandler(&onPropertyChange);
        }
    }

    pub fn getPreferredSize(self: *Slider_Impl, available: Size) Size {
        _ = available;
        if (self.peer) |peer| {
            return peer.getPreferredSize();
        } else {
            return Size{ .width = 100.0, .height = 40.0 };
        }
    }

    pub fn _deinit(self: *Slider_Impl) void {
        self.enabled.deinit();
    }
};

pub fn Slider(config: Slider_Impl.Config) Slider_Impl {
    var slider = Slider_Impl.init();
    slider.min.set(config.min);
    slider.max.set(config.max);
    slider.value.set(config.value);
    slider.step.set(config.step);
    slider.enabled.set(config.enabled);
    slider.dataWrappers.name.set(config.name);
    if (config.onclick) |onclick| {
        slider.addClickHandler(onclick) catch unreachable; // TODO: improve
    }
    return slider;
}
