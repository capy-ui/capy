const std = @import("std");
const backend = @import("../backend.zig");
const internal = @import("../internal.zig");
const Size = @import("../data.zig").Size;
const Atom = @import("../data.zig").Atom;
const capy = @import("../capy.zig");

/// Label containing text for the user to view.
pub const Label = struct {
    pub usingnamespace internal.All(Label);

    peer: ?backend.Label = null,
    widget_data: Label.WidgetData = .{},
    /// The text the label will take. For instance, if this is 'Example', the user
    /// will see the text 'Example'.
    text: Atom([]const u8) = Atom([]const u8).of(""),
    /// Defines how the text will show and take up available space.
    layout: Atom(capy.TextLayout) = Atom(capy.TextLayout).of(.{}),

    pub fn init(config: Label.Config) Label {
        var lbl = Label.init_events(Label{});
        internal.applyConfigStruct(&lbl, config);
        return lbl;
    }

    fn onTextAtomChange(newValue: []const u8, userdata: ?*anyopaque) void {
        const self: *Label = @ptrCast(@alignCast(userdata.?));
        self.peer.?.setText(newValue);
    }

    fn onTextLayoutAtomChange(newValue: capy.TextLayout, userdata: ?*anyopaque) void {
        const self: *Label = @ptrCast(@alignCast(userdata.?));
        self.peer.?.setAlignment(switch (newValue.alignment) {
            .Left => 0,
            .Center => 0.5,
            .Right => 1,
        });
        self.peer.?.setFont(newValue.font);
    }

    pub fn show(self: *Label) !void {
        if (self.peer == null) {
            var peer = try backend.Label.create();
            peer.setText(self.text.get());
            self.peer = peer;
            try self.setupEvents();
            _ = try self.text.addChangeListener(.{ .function = onTextAtomChange, .userdata = self });
            _ = try self.layout.addChangeListener(.{ .function = onTextLayoutAtomChange, .userdata = self });
            onTextLayoutAtomChange(self.layout.get(), self);
        }
    }

    pub fn getPreferredSize(self: *Label, available: Size) Size {
        _ = available;
        if (self.peer) |peer| {
            return peer.getPreferredSize();
        } else {
            // Crude approximation
            const len = self.text.get().len;
            return Size{ .width = @floatFromInt(10 * len), .height = 40.0 };
        }
    }

    pub fn setText(self: *Label, text: []const u8) void {
        self.text.set(text);
    }

    pub fn getText(self: *Label) []const u8 {
        return self.text.get();
    }
};

pub fn label(config: Label.Config) *Label {
    return Label.alloc(config);
}

// TODO: replace with an actual empty element from the backend
// Although this is not necessary and would only provide minimal memory/performance gains
pub fn spacing() !*@import("../widget.zig").Widget {
    return try @import("../containers.zig").expanded(label(.{}));
}
