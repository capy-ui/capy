const std = @import("std");
const backend = @import("../backend.zig");
const dataStructures = @import("../data.zig");
const internal = @import("../internal.zig");
const Size = dataStructures.Size;
const DataWrapper = dataStructures.DataWrapper;
const StringDataWrapper = dataStructures.StringDataWrapper;

pub const TextArea_Impl = struct {
    pub usingnamespace internal.All(TextArea_Impl);

    peer: ?backend.TextArea = null,
    handlers: TextArea_Impl.Handlers = undefined,
    dataWrappers: TextArea_Impl.DataWrappers = .{},
    text: StringDataWrapper = StringDataWrapper.of(""),
    _wrapperTextBlock: std.atomic.Atomic(bool) = std.atomic.Atomic(bool).init(false),

    pub fn init(config: TextArea_Impl.Config) TextArea_Impl {
        var area = TextArea_Impl.init_events(TextArea_Impl{
            .text = StringDataWrapper.of(config.text),
        });
        area.setName(config.name);
        return area;
    }

    pub fn _pointerMoved(self: *TextArea_Impl) void {
        self.text.updateBinders();
    }

    fn wrapperTextChanged(newValue: []const u8, userdata: usize) void {
        const self = @intToPtr(*TextArea_Impl, userdata);
        if (self._wrapperTextBlock.load(.Monotonic) == true) return;

        self.peer.?.setText(newValue);
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
            self.peer = peer;
            try self.show_events();

            try peer.setCallback(.TextChanged, textChanged);
            _ = try self.text.addChangeListener(.{ .function = wrapperTextChanged, .userdata = @ptrToInt(self) });
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
