const std = @import("std");
const backend = @import("../backend.zig");
const Size = @import("../data.zig").Size;
const Color = @import("../color.zig").Color;

/// Button flat peer
pub const FlatButton = struct {
    peer: backend.PeerType,
    canvas: backend.Canvas,

    label: [:0]const u8 = "",
    enabled: bool = true,

    pub usingnamespace backend.Events(FlatButton);

    pub fn create() !FlatButton {
        const canvas = try backend.Canvas.create();
        const events = backend.getEventUserData(canvas.peer);
        events.class.drawHandler = draw;

        return FlatButton{ .peer = canvas.peer, .canvas = canvas };
    }

    // TODO: themes and custom styling
    fn draw(ctx: *backend.Canvas.DrawContext, data: usize) void {
        const events = @intToPtr(*backend.EventUserData, data);
        const self = @intToPtr(?*FlatButton, events.classUserdata).?;

        const width = @intCast(u32, backend.getWidthFromPeer(events.peer));
        const height = @intCast(u32, backend.getHeightFromPeer(events.peer));

        ctx.setColorByte(Color.comptimeFromString("#00000029"));
        ctx.rectangle(0, 0, width, height);
        ctx.fill();

        if (self.enabled) {
            ctx.setColorByte(Color.comptimeFromString("#ffffffb3"));
        } else {
            ctx.setColor(0.7, 0.7, 0.7);
        }
        ctx.rectangle(3, 3, width - 6, height - 6);
        ctx.fill();

        const text = self.label;
        var layout = backend.Canvas.DrawContext.TextLayout.init();
        defer layout.deinit();
        ctx.setColorByte(Color.comptimeFromString("#000000e4"));
        layout.setFont(.{ .face = "Segoe UI", .size = 14.0 });
        ctx.text(0, 0, layout, text);
        ctx.fill();
    }

    pub fn setLabel(self: *FlatButton, label: [:0]const u8) void {
        self.label = label;
        const events = backend.getEventUserData(self.peer);
        events.classUserdata = @ptrToInt(self);
        self.requestDraw() catch {};
    }

    pub fn getLabel(self: *const FlatButton) [:0]const u8 {
        return self.label;
    }

    pub fn setEnabled(self: *FlatButton, enabled: bool) void {
        self.enabled = enabled;
    }

    pub fn getPreferredSize_impl(self: *const FlatButton) Size {
        _ = self;
        return Size.init(300, 50);
    }
};
