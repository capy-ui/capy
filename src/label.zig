const std = @import("std");
const backend = @import("backend.zig");
const Size = @import("data.zig").Size;
const DataWrapper = @import("data.zig").DataWrapper;

pub const State = struct {
    text: [:0]const u8 = "",
    alignment: TextAlignment = .Center,
    selectable: bool = false,
};

pub const Label_Impl = struct {
    pub usingnamespace @import("internal.zig").All(Label_Impl);

    peer: ?backend.Label = null,
    handlers: Label_Impl.Handlers = undefined,
    dataWrappers: Label_Impl.DataWrappers = .{},
    state: State,

    pub fn init(state: State) Label_Impl {
        return Label_Impl.init_events(Label_Impl{ .state = state });
    }

    pub fn show(self: *Label_Impl) !void {
        if (self.peer == null) {
            var peer = try backend.Label.create();
            peer.setText(self.state.text);
            peer.setAlignment(self.state.alignment.toFloat());
            if (@hasDecl(backend.Label, "setSelectable")) {
                peer.setSelectable(self.state.selectable);
            }
            self.peer = peer;
            try self.show_events();
        }
    }

    pub fn getPreferredSize(self: *Label_Impl, available: Size) Size {
        _ = available;
        const len = std.mem.len(self.state.text);
        return Size{
            .width = @intCast(u32, 10 * len), // TODO: saturating multiply instead
            .height = 40.0,
        };
    }

    pub fn setSelectable(self: *Label_Impl, selectable: bool) void {
        if (!@hasDecl(backend.Label, "setSelectable")) {
            @compileError("Selectable is not implemented on this backend");
        }
        if (self.peer) |*peer| {
            peer.setSelectable(selectable);
        } else {
            self.config.selectable = selectable;
        }
    }

    pub fn setText(self: *Label_Impl, text: [:0]const u8) void {
        if (self.peer) |*peer| {
            peer.setText(text);
        } else {
            self.state.text = text;
        }
    }

    pub fn setAlignment(self: *Label_Impl, alignment: TextAlignment) void {
        if (self.peer) |*peer| {
            peer.setAlignment(alignment.toFloat());
        } else {
            self.state.alignment = alignment;
        }
    }

    pub fn getText(self: *Label_Impl) [:0]const u8 {
        if (self.peer) |*peer| {
            return peer.getText();
        } else {
            return self.state.text;
        }
    }
};

pub const TextAlignment = enum {
    Left,
    Center,
    Right,

    pub fn toFloat(self: TextAlignment) f32 {
        return @as(f32, switch (self) {
            .Left => 0,
            .Center => 0.5,
            .Right => 1,
        });
    }

};

pub fn Label(state: State) Label_Impl {
    return Label_Impl.init(state);
}
