const std = @import("std");
const backend = @import("../backend.zig");
const Size = @import("../data.zig").Size;
const Atom = @import("../data.zig").Atom;
const Container_Impl = @import("../containers.zig").Container_Impl;

/// A button component. Instantiated using `Button(.{ })`
pub const Button = struct {
    pub usingnamespace @import("../internal.zig").All(Button);

    peer: ?backend.Button = null,
    widget_data: Button.WidgetData = .{},
    label: Atom([:0]const u8) = Atom([:0]const u8).of(""),
    enabled: Atom(bool) = Atom(bool).of(true),

    pub fn init() Button {
        return Button.init_events(Button{});
    }

    pub fn _pointerMoved(self: *Button) void {
        self.enabled.updateBinders();
        self.label.updateBinders();
    }

    fn wrapperEnabledChanged(newValue: bool, userdata: usize) void {
        const peer = @as(*?backend.Button, @ptrFromInt(userdata));
        peer.*.?.setEnabled(newValue);
    }

    fn wrapperLabelChanged(newValue: [:0]const u8, userdata: usize) void {
        const peer = @as(*?backend.Button, @ptrFromInt(userdata));
        peer.*.?.setLabel(newValue);
    }

    pub fn show(self: *Button) !void {
        if (self.peer == null) {
            self.peer = try backend.Button.create();
            self.peer.?.setEnabled(self.enabled.get());

            self.peer.?.setLabel(self.label.get());
            try self.show_events();
            _ = try self.enabled.addChangeListener(.{ .function = wrapperEnabledChanged, .userdata = @intFromPtr(&self.peer) });
            _ = try self.label.addChangeListener(.{ .function = wrapperLabelChanged, .userdata = @intFromPtr(&self.peer) });
        }
    }

    pub fn getPreferredSize(self: *Button, available: Size) Size {
        _ = available;
        if (self.peer) |peer| {
            return peer.getPreferredSize();
        } else {
            return Size{ .width = 100.0, .height = 40.0 };
        }
    }

    pub fn setLabel(self: *Button, label: [:0]const u8) void {
        self.label.set(label);
    }

    pub fn getLabel(self: *Button) [:0]const u8 {
        return self.label.get();
    }

    pub fn _deinit(self: *Button) void {
        self.enabled.deinit();
        self.label.deinit();
    }
};

pub fn button(config: Button.Config) Button {
    var btn = Button.init();
    btn.label.set(config.label);
    btn.enabled.set(config.enabled);
    btn.widget_data.atoms.name.set(config.name);
    if (config.onclick) |onclick| {
        btn.addClickHandler(onclick) catch unreachable; // TODO: improve
    }
    return btn;
}

test "button" {
    var btn = button(.{ .label = "Test Label" });
    try std.testing.expectEqualStrings("Test Label", btn.getLabel());

    btn.setLabel("New Label");
    try std.testing.expectEqualStrings("New Label", btn.getLabel());

    try backend.init();
    try btn.show();
    defer btn.deinit();

    btn.enabled.set(true);

    try std.testing.expectEqualStrings("New Label", btn.getLabel());
    btn.setLabel("One more time");
    try std.testing.expectEqualStrings("One more time", btn.getLabel());
}
