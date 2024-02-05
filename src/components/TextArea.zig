const std = @import("std");
const backend = @import("../backend.zig");
const dataStructures = @import("../data.zig");
const internal = @import("../internal.zig");
const Size = dataStructures.Size;
const Atom = dataStructures.Atom;
const StringAtom = dataStructures.StringAtom;

pub const TextArea = struct {
    pub usingnamespace internal.All(TextArea);

    peer: ?backend.TextArea = null,
    widget_data: TextArea.WidgetData = .{},
    text: StringAtom = StringAtom.of(""),

    // TODO: replace with TextArea.setFont(.{ .family = "monospace" }) ?
    /// Whether to let the system choose a monospace font for us and use it in this TextArea..
    monospace: Atom(bool) = Atom(bool).of(false),

    pub fn init(config: TextArea.Config) TextArea {
        var area = TextArea.init_events(TextArea{
            .text = StringAtom.of(config.text),
            .monospace = Atom(bool).of(config.monospace),
        });
        @import("../internal.zig").applyConfigStruct(&area, config);
        area.setName(config.name);
        return area;
    }

    pub fn _pointerMoved(self: *TextArea) void {
        self.text.updateBinders();
        self.monospace.updateBinders();
    }

    fn onTextAtomChanged(newValue: []const u8, userdata: ?*anyopaque) void {
        const self: *TextArea = @ptrCast(@alignCast(userdata));
        if (std.mem.eql(u8, self.peer.?.getText(), newValue)) return;
        self.peer.?.setText(newValue);
    }

    fn onMonospaceAtomChanged(newValue: bool, userdata: ?*anyopaque) void {
        const self: *TextArea = @ptrCast(@alignCast(userdata));
        self.peer.?.setMonospaced(newValue);
    }

    fn textChanged(userdata: usize) void {
        const self = @as(*TextArea, @ptrFromInt(userdata));
        const text = self.peer.?.getText();
        self.text.set(text);
    }

    pub fn show(self: *TextArea) !void {
        if (self.peer == null) {
            var peer = try backend.TextArea.create();
            peer.setText(self.text.get());
            peer.setMonospaced(self.monospace.get());
            self.peer = peer;
            try self.setupEvents();

            try peer.setCallback(.TextChanged, textChanged);
            _ = try self.text.addChangeListener(.{ .function = onTextAtomChanged, .userdata = self });
            _ = try self.monospace.addChangeListener(.{ .function = onMonospaceAtomChanged, .userdata = self });
        }
    }

    pub fn getPreferredSize(self: *TextArea, available: Size) Size {
        _ = available;
        if (self.peer) |peer| {
            return peer.getPreferredSize();
        } else {
            return Size{ .width = 100.0, .height = 100.0 };
        }
    }

    pub fn setText(self: *TextArea, text: []const u8) void {
        self.text.set(text);
    }

    pub fn getText(self: *TextArea) []const u8 {
        return self.text.get();
    }
};

pub fn textArea(config: TextArea.Config) *TextArea {
    return TextArea.alloc(config);
}
