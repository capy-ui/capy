const std = @import("std");
const backend = @import("../backend.zig");
const dataStructures = @import("../data.zig");
const internal = @import("../internal.zig");
const Size = dataStructures.Size;
const Atom = dataStructures.Atom;
const StringAtom = dataStructures.StringAtom;

pub const TextArea_Impl = struct {
    pub usingnamespace internal.All(TextArea_Impl);

    peer: ?backend.TextArea = null,
    widget_data: TextArea_Impl.WidgetData = .{},
    text: StringAtom = StringAtom.of(""),
    _wrapperTextBlock: std.atomic.Atomic(bool) = std.atomic.Atomic(bool).init(false),

    // TODO: replace with TextArea.setFont(.{ .family = "monospace" }) ?
    /// Whether to let the system choose a monospace font for us and use it in this TextArea..
    monospace: Atom(bool) = Atom(bool).of(false),

    pub fn init(config: TextArea_Impl.Config) TextArea_Impl {
        var area = TextArea_Impl.init_events(TextArea_Impl{
            .text = StringAtom.of(config.text),
            .monospace = Atom(bool).of(config.monospace),
        });
        area.setName(config.name);
        return area;
    }

    pub fn _pointerMoved(self: *TextArea_Impl) void {
        self.text.updateBinders();
        self.monospace.updateBinders();
    }

    fn wrapperTextChanged(newValue: []const u8, userdata: usize) void {
        const self = @intToPtr(*TextArea_Impl, userdata);
        if (self._wrapperTextBlock.load(.Monotonic) == true) return;

        self.peer.?.setText(newValue);
    }

    fn wrapperMonospaceChanged(newValue: bool, userdata: usize) void {
        const self = @intToPtr(*TextArea_Impl, userdata);
        self.peer.?.setMonospaced(newValue);
    }

    fn textChanged(userdata: usize) void {
        const self = @intToPtr(*TextArea_Impl, userdata);
        const text = self.peer.?.getText();

        self._wrapperTextBlock.store(true, .Monotonic);
        defer self._wrapperTextBlock.store(false, .Monotonic);
        self.text.set(text);
    }

    pub fn show(self: *TextArea_Impl) !void {
        if (self.peer == null) {
            var peer = try backend.TextArea.create();
            peer.setText(self.text.get());
            peer.setMonospaced(self.monospace.get());
            self.peer = peer;
            try self.show_events();

            try peer.setCallback(.TextChanged, textChanged);
            _ = try self.text.addChangeListener(.{ .function = wrapperTextChanged, .userdata = @ptrToInt(self) });
            _ = try self.monospace.addChangeListener(.{ .function = wrapperMonospaceChanged, .userdata = @ptrToInt(self) });
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
        self.text.set(text);
    }

    pub fn getText(self: *TextArea_Impl) []const u8 {
        return self.text.get();
    }
};

pub fn TextArea(config: TextArea_Impl.Config) TextArea_Impl {
    return TextArea_Impl.init(config);
}
