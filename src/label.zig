const std = @import("std");
const backend = @import("backend.zig");

pub const Label_Impl = struct {
    pub usingnamespace @import("events.zig").Events(Label_Impl);

    peer: ?backend.Label = null,
    clickHandlers: Label_Impl.HandlerList = undefined,
    _text: [:0]const u8,
    _align: TextAlignment,

    pub fn init(text: [:0]const u8, alignment: TextAlignment) Label_Impl {
        return Label_Impl.init_events(Label_Impl {
            ._text = text,
            ._align = alignment
        });
    }

    pub fn show(self: *Label_Impl) !void {
        if (self.peer == null) {
            var peer = try backend.Label.create();
            peer.setText(self._text);
            peer.setAlignment(switch (self._align) {
                .Left   => 0,
                .Center => 0.5,
                .Right  => 1
            });
            self.peer = peer;
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

pub const TextAlignment = enum {
    Left,
    Center,
    Right
};

pub fn Label(config: struct {
    text: [:0]const u8 = "",
    alignment: TextAlignment = .Center
}) Label_Impl {
    return Label_Impl.init(config.text, config.alignment);
}
