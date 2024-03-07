const std = @import("std");
const backend = @import("../backend.zig");
const Size = @import("../data.zig").Size;
const Atom = @import("../data.zig").Atom;
const Container_Impl = @import("../containers.zig").Container_Impl;

/// A little box you can check or leave unmarked.
///
/// It is mainly used to select or deselect an item from a list of multiple items that the user
/// can choose.
pub const CheckBox = struct {
    pub usingnamespace @import("../internal.zig").All(CheckBox);

    peer: ?backend.CheckBox = null,
    widget_data: CheckBox.WidgetData = .{},
    /// Whether the check box has a small tick inside.
    /// ☒ true
    /// ☐ false
    checked: Atom(bool) = Atom(bool).of(false),
    /// The label that shows next to the check box.
    label: Atom([:0]const u8) = Atom([:0]const u8).of(""),
    /// Whether the user can interact with the check box.
    enabled: Atom(bool) = Atom(bool).of(true),

    pub fn init(config: CheckBox.Config) CheckBox {
        var btn = CheckBox.init_events(CheckBox{});
        @import("../internal.zig").applyConfigStruct(&btn, config);
        return btn;
    }

    pub fn _pointerMoved(self: *CheckBox) void {
        self.enabled.updateBinders();
        self.checked.updateBinders();
    }

    fn wrapperCheckedChanged(newValue: bool, userdata: ?*anyopaque) void {
        const self: *CheckBox = @ptrCast(@alignCast(userdata));
        self.peer.?.setChecked(newValue);
    }

    fn wrapperEnabledChanged(newValue: bool, userdata: ?*anyopaque) void {
        const self: *CheckBox = @ptrCast(@alignCast(userdata));
        self.peer.?.setEnabled(newValue);
    }

    fn wrapperLabelChanged(newValue: [:0]const u8, userdata: ?*anyopaque) void {
        const self: *CheckBox = @ptrCast(@alignCast(userdata));
        self.peer.?.setLabel(newValue);
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
            try self.setupEvents();

            _ = try self.checked.addChangeListener(.{ .function = wrapperCheckedChanged, .userdata = self });
            _ = try self.enabled.addChangeListener(.{ .function = wrapperEnabledChanged, .userdata = self });
            _ = try self.label.addChangeListener(.{ .function = wrapperLabelChanged, .userdata = self });

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
};

pub fn checkBox(config: CheckBox.Config) *CheckBox {
    return CheckBox.alloc(config);
}
