const std = @import("std");
const backend = @import("../backend.zig");
const dataStructures = @import("../data.zig");
const internal = @import("../internal.zig");
const Size = dataStructures.Size;
const Atom = dataStructures.Atom;
const StringAtom = dataStructures.StringAtom;

pub const TextField = struct {
    pub usingnamespace internal.All(TextField);

    peer: ?backend.TextField = null,
    widget_data: TextField.WidgetData = .{},
    text: StringAtom = StringAtom.of(""),
    readOnly: Atom(bool) = Atom(bool).of(false),

    pub fn init(config: TextField.Config) TextField {
        var field = TextField.init_events(TextField{});
        internal.applyConfigStruct(&field, config);
        return field;
    }

    /// Internal function used at initialization.
    /// It is used to move some pointers so things do not break.
    pub fn _pointerMoved(self: *TextField) void {
        self.text.updateBinders();
    }

    /// When the text is changed in the StringAtom
    fn onTextAtomChange(newValue: []const u8, userdata: ?*anyopaque) void {
        const self: *TextField = @ptrCast(@alignCast(userdata));
        if (std.mem.eql(u8, self.peer.?.getText(), newValue)) return;
        self.peer.?.setText(newValue);
    }

    fn onReadOnlyAtomChange(newValue: bool, userdata: ?*anyopaque) void {
        const self: *TextField = @ptrCast(@alignCast(userdata));
        self.peer.?.setReadOnly(newValue);
    }

    fn textChanged(userdata: usize) void {
        const self: *TextField = @ptrFromInt(userdata);
        const text = self.peer.?.getText();
        self.text.set(text);
    }

    pub fn show(self: *TextField) !void {
        if (self.peer == null) {
            var peer = try backend.TextField.create();
            peer.setText(self.text.get());
            peer.setReadOnly(self.readOnly.get());
            self.peer = peer;

            try self.setupEvents();
            try peer.setCallback(.TextChanged, textChanged);
            _ = try self.text.addChangeListener(.{ .function = onTextAtomChange, .userdata = self });
            _ = try self.readOnly.addChangeListener(.{ .function = onReadOnlyAtomChange, .userdata = self });
        }
    }

    pub fn getPreferredSize(self: *TextField, available: Size) Size {
        _ = available;
        if (self.peer) |peer| {
            return peer.getPreferredSize();
        } else {
            return Size{ .width = 200.0, .height = 40.0 };
        }
    }

    pub fn setText(self: *TextField, text: []const u8) void {
        self.text.set(text);
    }

    pub fn getText(self: *TextField) []const u8 {
        return self.text.get();
    }

    pub fn setReadOnly(self: *TextField, readOnly: bool) void {
        self.readOnly.set(readOnly);
    }

    pub fn isReadOnly(self: *TextField) bool {
        return self.readOnly.get();
    }
};

pub fn textField(config: TextField.Config) *TextField {
    return TextField.alloc(config);
}
