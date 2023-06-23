const std = @import("std");
const backend = @import("../backend.zig");
const Size = @import("../data.zig").Size;

/// Toggle switch flat peer
pub const FlatToggleSwitch = struct {
    peer: backend.PeerType,
    canvas: backend.Canvas,

    label: [:0]const u8 = "",
    enabled: bool = true,

    pub usingnamespace backend.Events(FlatToggleSwitch);

    pub fn create() !FlatToggleSwitch {
        const canvas = try backend.Canvas.create();
        const events = backend.getEventUserData(canvas.peer);
        events.class.drawHandler = draw;

        return FlatToggleSwitch{ .peer = canvas.peer, .canvas = canvas };
    }

    // TODO: themes and custom styling
    fn draw(ctx: *backend.Canvas.DrawContext, data: usize) void {
        const events = @ptrFromInt(*backend.EventUserData, data);
        const self = @ptrFromInt(?*FlatToggleSwitch, events.classUserdata).?;

        const width = @intCast(u32, backend.getWidthFromPeer(events.peer));
        const height = @intCast(u32, backend.getHeightFromPeer(events.peer));

        if (self.enabled) {
            ctx.setColor(0.8, 0.8, 0.8);
        } else {
            ctx.setColor(0.7, 0.7, 0.7);
        }
        ctx.rectangle(0, 0, width, height);
        ctx.fill();

        const text = self.label;
        var layout = backend.Canvas.DrawContext.TextLayout.init();
        defer layout.deinit();
        ctx.setColor(1, 1, 1);
        layout.setFont(.{ .face = "serif", .size = 12.0 });
        ctx.text(0, 0, layout, text);
        ctx.fill();
    }

    pub fn setLabel(self: *FlatToggleSwitch, label: [:0]const u8) void {
        self.label = label;
        const events = backend.getEventUserData(self.peer);
        events.classUserdata = @intFromPtr(self);
        self.requestDraw() catch {};
    }

    pub fn getLabel(self: *const FlatToggleSwitch) [:0]const u8 {
        return self.label;
    }

    pub fn setEnabled(self: *FlatToggleSwitch, enabled: bool) void {
        self.enabled = enabled;
    }

    pub fn getPreferredSize_impl(self: *const FlatToggleSwitch) Size {
        _ = self;
        return Size.init(300, 100);
    }
};
