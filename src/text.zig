const std = @import("std");
const backend = @import("backend.zig");
const dataStructures = @import("data.zig");
const Size = dataStructures.Size;
const StringDataWrapper = dataStructures.StringDataWrapper;

pub const TextArea_Impl = struct {
    pub usingnamespace @import("internal.zig").All(TextArea_Impl);

    peer: ?backend.TextArea = null,
    handlers: TextArea_Impl.Handlers = undefined,
    dataWrappers: TextArea_Impl.DataWrappers = .{},
    _text: []const u8,

    pub fn init(text: []const u8) TextArea_Impl {
        return TextArea_Impl.init_events(TextArea_Impl{ ._text = text });
    }

    pub fn show(self: *TextArea_Impl) !void {
        if (self.peer == null) {
            var peer = try backend.TextArea.create();
            peer.setText(self._text);
            self.peer = peer;
        }
    }

    pub fn getPreferredSize(self: *TextArea_Impl, available: Size) Size {
        _ = available;
        if (self.peer) |peer| {
            return peer.getPreferredSize();
        } else {
            return Size{ .width = 100.0, .height = 100.0 };
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

pub const TextField_Impl = struct {
    pub usingnamespace @import("internal.zig").All(TextField_Impl);
    //pub usingnamespace @import("internal.zig").Property(TextField_Impl, "text");

    peer: ?backend.TextField = null,
    handlers: TextField_Impl.Handlers = undefined,
    dataWrappers: TextField_Impl.DataWrappers = .{},
    text: StringDataWrapper,

    pub fn init(text: []const u8) TextField_Impl {
        return TextField_Impl.init_events(TextField_Impl{ .text = StringDataWrapper.of(text) });
    }

    /// Internal function used at initialization.
    /// It is used to move some pointers so things do not break.
    pub fn _pointerMoved(self: *TextField_Impl) void {
        self.text.updateBinders();
    }

    /// When the text is changed in the StringDataWrapper
    fn wrapperTextChanged(newValue: []const u8, userdata: usize) void {
        const peer = @intToPtr(*?backend.TextField, userdata);
        peer.*.?.setText(newValue);
    }

    fn textChanged(userdata: usize) void {
        const self = @intToPtr(*TextField_Impl, userdata);
        const text = self.peer.?.getText();

        self.text.setNoListen(text);
    }

    pub fn show(self: *TextField_Impl) !void {
        if (self.peer == null) {
            var peer = try backend.TextField.create();
            peer.setText(self.text.get());
            self.peer = peer;
            try self.show_events();
            try peer.setCallback(.TextChanged, textChanged);
            _ = try self.text.addChangeListener(.{ .function = wrapperTextChanged, .userdata = @ptrToInt(&self.peer) });
        }
    }

    pub fn getPreferredSize(self: *TextField_Impl, available: Size) Size {
        _ = available;
        if (self.peer) |peer| {
            return peer.getPreferredSize();
        } else {
            return Size{ .width = 200.0, .height = 40.0 };
        }
    }

    pub fn setText(self: *TextField_Impl, text: []const u8) void {
        self.text.set(text);
    }

    pub fn getText(self: *TextField_Impl) []const u8 {
        return self.text.get();
    }

    /// Bind the 'text' property to argument.
    pub fn bindText(self: *TextField_Impl, other: *StringDataWrapper) TextField_Impl {
        self.text.bind(other);
        self.text.set(other.get());
        return self.*;
    }
};

pub fn TextArea(config: struct { text: []const u8 = "" }) TextArea_Impl {
    return TextArea_Impl.init(config.text);
}

pub fn TextField(config: struct { text: []const u8 = "" }) TextField_Impl {
    return TextField_Impl.init(config.text);
}
