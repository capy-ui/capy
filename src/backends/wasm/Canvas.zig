const std = @import("std");
const common = @import("common.zig");
const js = @import("js.zig");
const lib = @import("../../capy.zig");
const GuiWidget = common.GuiWidget;
const Events = common.Events;

const Canvas = @This();

peer: *GuiWidget,
dirty: bool,

pub usingnamespace Events(Canvas);

pub const DrawContextImpl = struct {
    ctx: js.CanvasContextId,

    pub const Font = struct {
        face: [:0]const u8,
        size: f64,
    };

    pub const TextSize = struct { width: u32, height: u32 };

    pub const TextLayout = struct {
        wrap: ?f64 = null,

        pub fn setFont(self: *TextLayout, font: Font) void {
            // TODO
            _ = self;
            _ = font;
        }

        pub fn deinit(self: *TextLayout) void {
            // TODO
            _ = self;
        }

        pub fn getTextSize(self: *TextLayout, str: []const u8) TextSize {
            // TODO
            _ = self;
            _ = str;
            return TextSize{ .width = 0, .height = 0 };
        }

        pub fn init() TextLayout {
            return TextLayout{};
        }
    };

    pub fn setColorRGBA(self: *DrawContextImpl, r: f32, g: f32, b: f32, a: f32) void {
        const color = lib.Color{
            .red = @as(u8, @intFromFloat(std.math.clamp(r, 0, 1) * 255)),
            .green = @as(u8, @intFromFloat(std.math.clamp(g, 0, 1) * 255)),
            .blue = @as(u8, @intFromFloat(std.math.clamp(b, 0, 1) * 255)),
            .alpha = @as(u8, @intFromFloat(std.math.clamp(a, 0, 1) * 255)),
        };
        js.setColor(self.ctx, color.red, color.green, color.blue, color.alpha);
    }

    pub fn rectangle(self: *DrawContextImpl, x: i32, y: i32, w: u32, h: u32) void {
        js.rectPath(self.ctx, x, y, w, h);
    }

    pub fn roundedRectangleEx(self: *DrawContextImpl, x: i32, y: i32, w: u32, h: u32, corner_radiuses: [4]f32) void {
        _ = corner_radiuses;
        js.rectPath(self.ctx, x, y, w, h);
    }

    pub fn text(self: *DrawContextImpl, x: i32, y: i32, layout: TextLayout, str: []const u8) void {
        // TODO: layout
        _ = layout;
        js.fillText(self.ctx, str.ptr, str.len, x, y);
    }

    pub fn image(self: *DrawContextImpl, x: i32, y: i32, w: u32, h: u32, data: lib.ImageData) void {
        _ = w;
        _ = h; // TODO: scaling
        js.fillImage(self.ctx, data.peer.id, x, y);
    }

    pub fn line(self: *DrawContextImpl, x1: i32, y1: i32, x2: i32, y2: i32) void {
        js.moveTo(self.ctx, x1, y1);
        js.lineTo(self.ctx, x2, y2);
        js.stroke(self.ctx);
    }

    pub fn ellipse(self: *DrawContextImpl, x: i32, y: i32, w: u32, h: u32) void {
        js.ellipse(self.ctx, x, y, w, h);
    }

    pub fn clear(self: *DrawContextImpl, x: u32, y: u32, w: u32, h: u32) void {
        // TODO
        _ = self;
        _ = x;
        _ = y;
        _ = w;
        _ = h;
    }

    pub fn stroke(self: *DrawContextImpl) void {
        js.stroke(self.ctx);
    }

    pub fn fill(self: *DrawContextImpl) void {
        js.fill(self.ctx);
    }
};

pub fn create() !Canvas {
    return Canvas{
        .peer = try GuiWidget.init(
            Canvas,
            lib.lasting_allocator,
            "canvas",
            "canvas",
        ),
        .dirty = true, // the Canvas needs one initial draw
    };
}

pub fn _requestDraw(self: *Canvas) void {
    self.dirty = true;
}

pub fn _onWindowTick(self: *Canvas) void {
    if (!self.dirty) return;
    defer self.dirty = false;

    const ctx_id = js.openContext(self.peer.element);
    const impl = DrawContextImpl{ .ctx = ctx_id };
    var ctx = @import("../../backend.zig").DrawContext{ .impl = impl };
    if (self.peer.class.drawHandler) |handler| {
        handler(&ctx, self.peer.classUserdata);
    }
    if (self.peer.user.drawHandler) |handler| {
        handler(&ctx, self.peer.userdata);
    }
}
