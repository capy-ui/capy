const std = @import("std");
const backend = @import("backend");

pub const Button_Impl = struct {
    pub usingnamespace @import("events.zig").Events(Button_Impl);

    peer: ?backend.Button = null,
    clickHandlers: Button_Impl.HandlerList = undefined,
    label: [:0]const u8 = "",

    pub fn init() Button_Impl {
        return Button_Impl.init_events(Button_Impl {});
    }

    pub fn initLabeled(label: [:0]const u8) Button_Impl {
        var button = Button_Impl.init();
        button.setLabel(label);
        return button;
    }
    
    pub fn show(self: *Button_Impl) !void {
        if (self.peer == null) {
            self.peer = try backend.Button.create();
            self.peer.?.setLabel(self.label);
            try self.show_events();
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

pub fn Button(config: struct {
    label: [:0]const u8 = "",
    onclick: ?Button_Impl.Callback = null
}) Button_Impl {
    var btn = Button_Impl.initLabeled(config.label);
    if (config.onclick) |onclick| {
        btn.addClickHandler(onclick) catch unreachable; // TODO: improve
    }
    return btn;
}
