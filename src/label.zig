const std = @import("std");
const backend = @import("backend.zig");
const Size = @import("data.zig").Size;
const DataWrapper = @import("data.zig").DataWrapper;

pub const Label_Impl = struct {
    pub usingnamespace @import("internal.zig").All(Label_Impl);

    peer: ?backend.Label = null,
    handlers: Label_Impl.Handlers = undefined,
    dataWrappers: Label_Impl.DataWrappers = .{},
    text: DataWrapper([]const u8) = DataWrapper([]const u8).of(""),
    alignment: DataWrapper(TextAlignment) = DataWrapper(TextAlignment).of(.Left),

    pub fn init(config: Label_Impl.Config) Label_Impl {
        return Label_Impl.init_events(Label_Impl{
            .text = DataWrapper([]const u8).of(config.text),
            .alignment = DataWrapper(TextAlignment).of(config.alignment),
        });
    }

    pub fn _pointerMoved(self: *Label_Impl) void {
        self.text.updateBinders();
        self.alignment.updateBinders();
    }

    fn wrapperTextChanged(newValue: []const u8, userdata: usize) void {
        const self = @intToPtr(*Label_Impl, userdata);
        self.peer.?.setText(newValue);
    }

    pub fn show(self: *Label_Impl) !void {
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
            _ = try self.text.addChangeListener(.{ .function = wrapperTextChanged, .userdata = @ptrToInt(self) });
        }
    }

    pub fn getPreferredSize(self: *Label_Impl, available: Size) Size {
        _ = available;
        if (self.peer) |peer| {
            return peer.getPreferredSize();
        } else {
            const len = self.text.get().len;
            return Size{ .width = @intCast(u32, 10 * len), .height = 40.0 };
        }
    }

    pub fn setText(self: *Label_Impl, text: []const u8) void {
        self.text.set(text);
    }

    pub fn getText(self: *Label_Impl) []const u8 {
        return self.text.get();
    }
};

pub const TextAlignment = enum { Left, Center, Right };

pub fn Label(config: Label_Impl.Config) Label_Impl {
    return Label_Impl.init(config);
}

// TODO: replace with an actual empty element from the backend
// Although this is not necessary and would only provide minimal memory/performance gains
pub fn Spacing() !@import("widget.zig").Widget {
    return try @import("containers.zig").Expanded(Label(.{}));
}
