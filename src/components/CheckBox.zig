const std = @import("std");
const backend = @import("../backend.zig");
const Size = @import("../data.zig").Size;
const Atom = @import("../data.zig").Atom;
const Container_Impl = @import("../containers.zig").Container_Impl;

pub const CheckBox = struct {
    pub usingnamespace @import("../internal.zig").All(CheckBox);

    peer: ?backend.CheckBox = null,
    widget_data: CheckBox.WidgetData = .{},
    checked: Atom(bool) = Atom(bool).of(false),
    label: Atom([:0]const u8) = Atom([:0]const u8).of(""),
    enabled: Atom(bool) = Atom(bool).of(true),

    pub fn init() CheckBox {
        return CheckBox.init_events(CheckBox{});
    }

    pub fn _pointerMoved(self: *CheckBox) void {
        self.enabled.updateBinders();
        self.checked.updateBinders();
    }

    fn wrapperCheckedChanged(newValue: bool, userdata: usize) void {
        const peer = @as(*?backend.CheckBox, @ptrFromInt(userdata));
        peer.*.?.setChecked(newValue);
    }

    fn wrapperEnabledChanged(newValue: bool, userdata: usize) void {
        const peer = @as(*?backend.CheckBox, @ptrFromInt(userdata));
        peer.*.?.setEnabled(newValue);
    }

    fn wrapperLabelChanged(newValue: [:0]const u8, userdata: usize) void {
        const peer = @as(*?backend.CheckBox, @ptrFromInt(userdata));
        peer.*.?.setLabel(newValue);
    }

    fn onClick(self: *CheckBox) !void {
        self.checked.set(self.peer.?.isChecked());
    }

    pub fn show(self: *CheckBox) !void {
        if (self.peer == null) {
            self.peer = try backend.CheckBox.create();
            self.peer.?.setChecked(self.checked.get());
            self.peer.?.setEnabled(self.enabled.get());
            self.peer.?.setLabel(self.label.get());
            try self.show_events();

            _ = try self.checked.addChangeListener(.{ .function = wrapperCheckedChanged, .userdata = @intFromPtr(&self.peer) });
            _ = try self.enabled.addChangeListener(.{ .function = wrapperEnabledChanged, .userdata = @intFromPtr(&self.peer) });
            _ = try self.label.addChangeListener(.{ .function = wrapperLabelChanged, .userdata = @intFromPtr(&self.peer) });

            try self.addClickHandler(&onClick);
        }
    }

    pub fn getPreferredSize(self: *CheckBox, available: Size) Size {
        _ = available;
        if (self.peer) |peer| {
            return peer.getPreferredSize();
        } else {
            return Size{ .width = 100.0, .height = 40.0 };
        }
    }

    pub fn setLabel(self: *CheckBox, label: [:0]const u8) void {
        self.label.set(label);
    }

    pub fn getLabel(self: *CheckBox) [:0]const u8 {
        return self.label.get();
    }

    pub fn _deinit(self: *CheckBox) void {
        self.enabled.deinit();
    }
};

pub fn checkBox(config: CheckBox.Config) CheckBox {
    var btn = CheckBox.init();
    @import("../internal.zig").applyConfigStruct(&btn, config);
    return btn;
}
