const std = @import("std");
const builtin = @import("builtin");
const backend = @import("../backend.zig");
const Size = @import("../data.zig").Size;
const Atom = @import("../data.zig").Atom;
const Color = @import("../color.zig").Color;
const Colors = @import("../color.zig").Colors;

/// Arbitrary size area on which the application may draw content.
///
/// It also has the particularity of being the only component on which the draw handler works.
pub const Canvas = struct {
    pub usingnamespace @import("../internal.zig").All(Canvas);

    peer: ?backend.Canvas = null,
    widget_data: Canvas.WidgetData = .{},
    /// The preferred size of the canvas, or null to take the least possible.
    preferredSize: Atom(?Size) = Atom(?Size).of(null),

    pub const DrawContext = backend.Canvas.DrawContext;

    pub fn init(config: Canvas.Config) Canvas {
        var cnv = Canvas.init_events(Canvas{});
        @import("../internal.zig").applyConfigStruct(&cnv, config);
        return cnv;
    }

    pub fn getPreferredSize(self: *Canvas, available: Size) Size {
        // As it's a canvas, by default it should take the available space
        return self.preferredSize.get() orelse available;
    }

    pub fn setPreferredSize(self: *Canvas, preferred: Size) Canvas {
        self.preferredSize.set(preferred);
        return self.*;
    }

    pub fn show(self: *Canvas) !void {
        if (self.peer == null) {
            self.peer = try backend.Canvas.create();
            try self.setupEvents();
        }
    }
};

pub fn canvas(config: Canvas.Config) *Canvas {
    return Canvas.alloc(config);
}

/// Arbitrary size area filled with a given color.
///
/// *This widget extends `Canvas`.*
pub const Rect = struct {
    pub usingnamespace @import("../internal.zig").All(Rect);

    peer: ?backend.Canvas = null,
    widget_data: Rect.WidgetData = .{},

    /// The preferred size of the canvas, or null to take the least possible.
    preferredSize: Atom(?Size) = Atom(?Size).of(null),
    /// The color the rectangle will be filled with.
    color: Atom(Color) = Atom(Color).of(Colors.black),
    /// The radiuses of the the corners of the rectangle. It can be changed to make
    /// a rounded rectangle.
    cornerRadius: Atom([4]f32) = Atom([4]f32).of(.{0.0} ** 4),

    pub fn init(config: Rect.Config) Rect {
        var rectangle = Rect.init_events(Rect{});
        @import("../internal.zig").applyConfigStruct(&rectangle, config);
        rectangle.addDrawHandler(&Rect.draw) catch unreachable;
        return rectangle;
    }

    pub fn getPreferredSize(self: *Rect, available: Size) Size {
        return self.preferredSize.get() orelse
            available.intersect(Size.init(0, 0));
    }

    pub fn setPreferredSize(self: *Rect, preferred: Size) Rect {
        self.preferredSize.set(preferred);
        return self.*;
    }

    pub fn draw(self: *Rect, ctx: *Canvas.DrawContext) !void {
        ctx.setColorByte(self.color.get());
        if (builtin.os.tag == .windows) {
            ctx.rectangle(0, 0, self.getWidth(), self.getHeight());
        } else {
            ctx.roundedRectangleEx(0, 0, self.getWidth(), self.getHeight(), self.cornerRadius.get());
        }
        ctx.fill();
    }

    pub fn show(self: *Rect) !void {
        if (self.peer == null) {
            self.peer = try backend.Canvas.create();
            _ = try self.color.addChangeListener(.{ .function = struct {
                fn callback(_: Color, userdata: ?*anyopaque) void {
                    const ptr: *Rect = @ptrCast(@alignCast(userdata.?));
                    ptr.peer.?.requestDraw() catch {};
                }
            }.callback, .userdata = self });
            _ = try self.cornerRadius.addChangeListener(.{ .function = struct {
                fn callback(_: [4]f32, userdata: ?*anyopaque) void {
                    const ptr: *Rect = @ptrCast(@alignCast(userdata.?));
                    ptr.peer.?.requestDraw() catch {};
                }
            }.callback, .userdata = self });
            try self.setupEvents();
        }
    }
};

pub fn rect(config: Rect.Config) *Rect {
    return Rect.alloc(config);
}

const fuzz = @import("../fuzz.zig");

test Canvas {
    var cnv = canvas(.{});
    cnv.ref(); // because we keep a reference to canvas we must call ref()
    defer cnv.unref();
}

test Rect {
    var rect1 = rect(.{ .color = Colors.blue });
    rect1.ref();
    defer rect1.unref();
    try std.testing.expectEqual(Colors.blue, rect1.color.get());

    var rect2 = rect(.{ .color = Colors.yellow });
    rect2.ref();
    defer rect2.unref();
    try std.testing.expectEqual(Colors.yellow, rect2.color.get());
}
