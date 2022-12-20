const std = @import("std");
const backend = @import("backend.zig");
const Size = @import("data.zig").Size;
const DataWrapper = @import("data.zig").DataWrapper;

pub const Label_Impl = struct {
    pub usingnamespace @import("internal.zig").All(Label_Impl);

    peer: ?backend.Label = null,
    handlers: Label_Impl.Handlers = undefined,
    dataWrappers: Label_Impl.DataWrappers = .{},
    _text: [:0]const u8,
    _align: TextAlignment,

    pub fn init(text: [:0]const u8, alignment: TextAlignment) Label_Impl {
        return Label_Impl.init_events(Label_Impl{ ._text = text, ._align = alignment });
    }

    pub fn show(self: *Label_Impl) !void {
        if (self.peer == null) {
            var peer = try backend.Label.create();
            peer.setText(self._text);
            peer.setAlignment(switch (self._align) {
                .Left => 0,
                .Center => 0.5,
                .Right => 1,
            });
            self.peer = peer;
            try self.show_events();
        }
    }

    pub fn getPreferredSize(self: *Label_Impl, available: Size) Size {
        _ = available;
        if (self.peer) |peer| {
            return peer.getPreferredSize();
        } else {
            const len = std.mem.len(self._text);
            return Size{ .width = @intCast(u32, 10 * len), .height = 40.0 };
        }
    }

    pub fn setText(self: *Label_Impl, text: [:0]const u8) void {
        if (self.peer) |*peer| {
            peer.setText(text);
        } else {
            self._text = text;
        }
    }

    pub fn getText(self: *Label_Impl) [:0]const u8 {
        if (self.peer) |*peer| {
            return peer.getText();
        } else {
            return self._text;
        }
    }
};

pub const TextAlignment = enum { Left, Center, Right };

pub fn Label(config: struct { text: [:0]const u8 = "", alignment: TextAlignment = .Center }) Label_Impl {
    return Label_Impl.init(config.text, config.alignment);
}

// TODO: replace with an actual empty element from the backend
// Although this is not necessary and would only provide minimal memory/performance gains
pub fn Spacing() !@import("widget.zig").Widget {
    return try @import("containers.zig").Expanded(Label(.{}));
}
