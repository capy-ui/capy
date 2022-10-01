const std = @import("std");
const backend = @import("backend.zig");
const Size = @import("data.zig").Size;
const DataWrapper = @import("data.zig").DataWrapper;
const Container_Impl = @import("containers.zig").Container_Impl;

/// A button component. Instantiated using `Button(.{ })`
pub const Button_Impl = struct {
    pub usingnamespace @import("internal.zig").All(Button_Impl);

    peer: ?backend.Button = null,
    handlers: Button_Impl.Handlers = undefined,
    dataWrappers: Button_Impl.DataWrappers = .{},
    label: [:0]const u8 = "",
    enabled: DataWrapper(bool),

    pub const Config = struct {
        label: [:0]const u8 = "",
        onclick: ?Button_Impl.Callback = null,
    };

    pub fn init() Button_Impl {
        return Button_Impl.init_events(Button_Impl{ .enabled = DataWrapper(bool).of(true) });
    }

    pub fn initLabeled(label: [:0]const u8) Button_Impl {
        var button = Button_Impl.init();
        button.setLabel(label);
        return button;
    }

    pub fn _pointerMoved(self: *Button_Impl) void {
        self.enabled.updateBinders();
    }

    pub fn show(self: *Button_Impl) !void {
        if (self.peer == null) {
            self.peer = try backend.Button.create();
            self.peer.?.setLabel(self.label);
            try self.show_events();
        }
    }

    pub fn getPreferredSize(self: *Button_Impl, available: Size) Size {
        _ = available;
        if (self.peer) |peer| {
            return peer.getPreferredSize();
        } else {
            return Size{ .width = 100.0, .height = 40.0 };
        }
    }

    pub fn setLabel(self: *Button_Impl, label: [:0]const u8) void {
        if (self.peer) |*peer| {
            peer.setLabel(label);
        } else {
            self.label = label;
        }
    }

    pub fn getLabel(self: *Button_Impl) [:0]const u8 {
        if (self.peer) |*peer| {
            return peer.getLabel();
        } else {
            return self.label;
        }
    }
};

pub fn Button(config: Button_Impl.Config) Button_Impl {
    var btn = Button_Impl.initLabeled(config.label);
    if (config.onclick) |onclick| {
        btn.addClickHandler(onclick) catch unreachable; // TODO: improve
    }
    return btn;
}

test "Button" {
    var button = Button(.{ .label = "Test Label" });
    try std.testing.expectEqualStrings("Test Label", button.getLabel());

    button.setLabel("New Label");
    try std.testing.expectEqualStrings("New Label", button.getLabel());
}
