const std = @import("std");
const backend = @import("../backend.zig");
const Size = @import("../data.zig").Size;
const Atom = @import("../data.zig").Atom;

pub const DrawContext = backend.Canvas.DrawContext;

pub const Canvas_Impl = struct {
    pub usingnamespace @import("../internal.zig").All(Canvas_Impl);

    peer: ?backend.Canvas = null,
    widget_data: Canvas_Impl.WidgetData = .{},
    preferredSize: Atom(?Size) = Atom(?Size).of(null),

    pub const DrawContext = backend.Canvas.DrawContext;

    pub fn init() Canvas_Impl {
        return Canvas_Impl.init_events(Canvas_Impl{});
    }

    pub fn getPreferredSize(self: *Canvas_Impl, available: Size) Size {
        // As it's a canvas, by default it should take the available space
        return self.preferredSize.get() orelse available;
    }

    pub fn setPreferredSize(self: *Canvas_Impl, preferred: Size) Canvas_Impl {
        self.preferredSize.set(preferred);
        return self.*;
    }

    pub fn show(self: *Canvas_Impl) !void {
        if (self.peer == null) {
            self.peer = try backend.Canvas.create();
            try self.show_events();
        }
    }
};

pub fn Canvas(config: Canvas_Impl.Config) Canvas_Impl {
    var btn = Canvas_Impl.init();
    btn.preferredSize = Atom(?Size).of(config.preferredSize);
    btn.widget_data.atoms.name.set(config.name);
    if (config.onclick) |onclick| {
        btn.addClickHandler(onclick) catch unreachable; // TODO: improve
    }
    if (config.ondraw) |ondraw| {
        btn.addDrawHandler(ondraw) catch unreachable; // TODO: improve
    }
    return btn;
}

const Color = @import("../color.zig").Color;

pub const Rect_Impl = struct {
    pub usingnamespace @import("../internal.zig").All(Rect_Impl);

    peer: ?backend.Canvas = null,
    widget_data: Rect_Impl.WidgetData = .{},
    preferredSize: Atom(?Size) = Atom(?Size).of(null),
    color: Atom(Color) = Atom(Color).of(Color.black),
    cornerRadius: Atom([4]f32) = Atom([4]f32).of(.{0.0} ** 4),

    pub fn init() Rect_Impl {
        return Rect_Impl.init_events(Rect_Impl{});
    }

    pub fn getPreferredSize(self: *Rect_Impl, available: Size) Size {
        return self.preferredSize.get() orelse
            available.intersect(Size.init(0, 0));
    }

    pub fn setPreferredSize(self: *Rect_Impl, preferred: Size) Rect_Impl {
        self.preferredSize.set(preferred);
        return self.*;
    }

    pub fn draw(self: *Rect_Impl, ctx: *Canvas_Impl.DrawContext) !void {
        ctx.setColorByte(self.color.get());
        ctx.roundedRectangleEx(0, 0, self.getWidth(), self.getHeight(), self.cornerRadius.get());
        ctx.fill();
    }

    pub fn show(self: *Rect_Impl) !void {
        if (self.peer == null) {
            self.peer = try backend.Canvas.create();
            _ = try self.color.addChangeListener(.{ .function = struct {
                fn callback(_: Color, userdata: usize) void {
                    const peer = @intToPtr(*?backend.Canvas, userdata);
                    peer.*.?.requestDraw() catch {};
                }
            }.callback, .userdata = @ptrToInt(&self.peer) });
            _ = try self.cornerRadius.addChangeListener(.{ .function = struct {
                fn callback(_: [4]f32, userdata: usize) void {
                    const peer = @intToPtr(*?backend.Canvas, userdata);
                    peer.*.?.requestDraw() catch {};
                }
            }.callback, .userdata = @ptrToInt(&self.peer) });
            try self.show_events();
        }
    }
};

pub fn Rect(config: Rect_Impl.Config) Rect_Impl {
    var rect = Rect_Impl.init();
    rect.addDrawHandler(&Rect_Impl.draw) catch unreachable;
    rect.preferredSize = Atom(?Size).of(config.preferredSize);
    rect.color = Atom(Color).of(config.color);
    rect.cornerRadius = Atom([4]f32).of(config.cornerRadius);
    rect.widget_data.atoms.name.set(config.name);
    return rect;
}

const fuzz = @import("../fuzz.zig");

test "instantiate Canvas" {
    var canvas = Canvas(.{});
    defer canvas.deinit();
}

test "instantiate Rect" {
    var rect = Rect(.{ .color = Color.blue });
    defer rect.deinit();
    try std.testing.expectEqual(Color.blue, rect.color.get());

    var rect2 = Rect(.{ .color = Color.yellow });
    defer rect2.deinit();
    try std.testing.expectEqual(Color.yellow, rect2.color.get());
}
