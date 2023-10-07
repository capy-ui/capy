const std = @import("std");
const backend = @import("../backend.zig");
const Size = @import("../data.zig").Size;
const Atom = @import("../data.zig").Atom;

pub const Label = struct {
    pub usingnamespace @import("../internal.zig").All(Label);

    peer: ?backend.Label = null,
    widget_data: Label.WidgetData = .{},
    text: Atom([]const u8) = Atom([]const u8).of(""),
    alignment: Atom(TextAlignment) = Atom(TextAlignment).of(.Left),

    pub fn init(config: Label.Config) Label {
        var lbl = Label.init_events(Label{});
        @import("../internal.zig").applyConfigStruct(&lbl, config);
        return lbl;
    }

    pub fn _pointerMoved(self: *Label) void {
        self.text.updateBinders();
        self.alignment.updateBinders();
    }

    fn wrapperTextChanged(newValue: []const u8, userdata: usize) void {
        const self = @as(*Label, @ptrFromInt(userdata));
        self.peer.?.setText(newValue);
    }

    pub fn show(self: *Label) !void {
        if (self.peer == null) {
            var peer = try backend.Label.create();
            peer.setText(self.text.get());
            peer.setAlignment(switch (self.alignment.get()) {
                .Left => 0,
                .Center => 0.5,
                .Right => 1,
            });
            self.peer = peer;
            try self.show_events();
            _ = try self.text.addChangeListener(.{ .function = wrapperTextChanged, .userdata = @intFromPtr(self) });
        }
    }

    pub fn getPreferredSize(self: *Label, available: Size) Size {
        _ = available;
        if (self.peer) |peer| {
            return peer.getPreferredSize();
        } else {
            const len = self.text.get().len;
            return Size{ .width = @as(u32, @intCast(10 * len)), .height = 40.0 };
        }
    }

    pub fn setText(self: *Label, text: []const u8) void {
        self.text.set(text);
    }

    pub fn getText(self: *Label) []const u8 {
        return self.text.get();
    }
};

pub const TextAlignment = enum { Left, Center, Right };

pub fn label(config: Label.Config) Label {
    return Label.init(config);
}

// TODO: replace with an actual empty element from the backend
// Although this is not necessary and would only provide minimal memory/performance gains
pub fn spacing() !@import("../widget.zig").Widget {
    return try @import("../containers.zig").expanded(label(.{}));
}
