const std = @import("std");
const backend = @import("../backend.zig");
const internal = @import("../internal.zig");
const Size = @import("../data.zig").Size;
const Atom = @import("../data.zig").Atom;

/// A button component. Instantiated using `button(.{ })`
pub const Button = struct {
    pub usingnamespace @import("../internal.zig").All(Button);

    peer: ?backend.Button = null,
    widget_data: Button.WidgetData = .{},
    label: Atom([:0]const u8) = Atom([:0]const u8).of(""),
    enabled: Atom(bool) = Atom(bool).of(true),

    pub fn init(config: Button.Config) Button {
        var btn = Button.init_events(Button{});
        internal.applyConfigStruct(&btn, config);
        return btn;
    }

    fn onEnabledAtomChange(newValue: bool, userdata: ?*anyopaque) void {
        const self: *Button = @ptrCast(@alignCast(userdata));
        self.peer.?.setEnabled(newValue);
    }

    fn onLabelAtomChange(newValue: [:0]const u8, userdata: ?*anyopaque) void {
        const self: *Button = @ptrCast(@alignCast(userdata));
        self.peer.?.setLabel(newValue);
    }

    pub fn show(self: *Button) !void {
        if (self.peer == null) {
            var peer = try backend.Button.create();
            peer.setEnabled(self.enabled.get());
            peer.setLabel(self.label.get());
            self.peer = peer;
            try self.setupEvents();
            _ = try self.enabled.addChangeListener(.{ .function = onEnabledAtomChange, .userdata = self });
            _ = try self.label.addChangeListener(.{ .function = onLabelAtomChange, .userdata = self });
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
};

pub fn button(config: Button.Config) *Button {
    return Button.alloc(config);
}

test Button {
    var btn = button(.{ .label = "Test Label" });
    btn.ref(); // because we're keeping a reference, we need to ref() it
    defer btn.unref();
    try std.testing.expectEqualStrings("Test Label", btn.getLabel());

    btn.setLabel("New Label");
    try std.testing.expectEqualStrings("New Label", btn.getLabel());

    try backend.init();
    try btn.show();

    btn.enabled.set(true);

    try std.testing.expectEqualStrings("New Label", btn.getLabel());
    btn.setLabel("One more time");
    try std.testing.expectEqualStrings("One more time", btn.getLabel());
}
