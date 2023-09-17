const capy = @import("capy");
const std = @import("std");
pub usingnamespace capy.cross_platform;

var gpa: std.heap.GeneralPurposeAllocator(.{}) = undefined;
pub const capy_allocator = gpa.allocator();

pub fn main() !void {
    try capy.init();
    defer capy.deinit();

    gpa = .{};
    defer _ = gpa.deinit();

    var window = try capy.Window.init();
    defer window.deinit();

    try window.set(
        capy.alignment(.{}, capy.column(.{}, .{
            rotatingDisc(), // TODO
            capy.label(.{ .text = "Audio Name", .alignment = .Center }),
        })),
    );

    window.show();
    capy.runEventLoop();
}

/// A spinning CD disc with the thumbnail of the audio or none if there isn't any
fn rotatingDisc() !capy.Canvas {
    var canvas = capy.canvas(.{
        .preferredSize = capy.Size.init(256, 256),
    });
    try canvas.addDrawHandler(&drawRotatingDisc);
    return canvas;
}

fn drawRotatingDisc(self: *capy.Canvas, ctx: *capy.DrawContext) anyerror!void {
    const width = self.getWidth();
    const height = self.getHeight();

    // TODO: we need multiply drawing (with circle) or arbitrary clipping paths
    // it should be able to handle an outer circle and an inner circle for the CD disc
    // TODO: do that clipping in path? transform path into clipping?

    ctx.setColor(0, 0, 0);
    ctx.ellipse(0, 0, width, height);
    ctx.fill();

    ctx.setColor(1, 1, 1);
    ctx.ellipse(@as(i32, @intCast(width / 2 - 20)), @as(i32, @intCast(height / 2 - 20)), 40, 40);
    ctx.fill();

    ctx.setColor(0.9, 0.9, 0.9);
    ctx.ellipse(@as(i32, @intCast(width / 2 - 15)), @as(i32, @intCast(height / 2 - 15)), 30, 30);
    ctx.fill();
}
