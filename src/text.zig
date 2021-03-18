const std = @import("std");
const backend = @import("backend");

pub const TextArea_Impl = struct {
    pub usingnamespace @import("events.zig").Events(TextArea_Impl);

    peer: ?backend.TextArea = null,
    clickHandlers: TextArea_Impl.HandlerList = undefined,
    _text: []const u8,

    pub fn init(text: []const u8) TextArea_Impl {
        return TextArea_Impl.init_events(TextArea_Impl {
            ._text = text
        });
    }

    pub fn show(self: *TextArea_Impl) !void {
        if (self.peer == null) {
            var peer = try backend.TextArea.create();
            peer.setText(self._text);
            self.peer = peer;
        }
    }

    pub fn setText(self: *TextArea_Impl, text: []const u8) void {
        if (self.peer) |*peer| {
            peer.setText(text);
        } else {
            self._text = text;
        }
    }

    pub fn getText(self: *TextArea_Impl) []const u8 {
        if (self.peer) |*peer| {
            return peer.getText();
        } else {
            return self._text;
        }
    }
};

pub fn TextArea(config: struct {
    text: []const u8 = ""
}) TextArea_Impl {
    return TextArea_Impl.init(config.text);
}
