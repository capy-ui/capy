const capy = @import("capy");
const std = @import("std");
pub usingnamespace capy.cross_platform;

// Override the allocator used by Capy
var gpa = std.heap.GeneralPurposeAllocator(.{}){};
pub const capy_allocator = gpa.allocator();

fn draw(widget: *capy.Canvas_Impl, ctx: *capy.DrawContext) !void {
    _ = widget;
    std.log.info("drawing widget", .{});
    ctx.setColor(0, 0, 0);
    ctx.rectangle(120, 320, 50, 50);
    ctx.fill();

    var layout = capy.DrawContext.TextLayout.init();
    defer layout.deinit();
    ctx.setColor(1, 1, 1);
    layout.setFont(.{ .face = "Liberation Sans", .size = 12.0 });
    layout.wrap = 50;
    ctx.text(120, 320, layout, "Hello, World !");
    ctx.fill();
}

fn scroll(widget: *capy.Canvas_Impl, dx: f32, dy: f32) !void {
    std.log.info("Scroll by {d}, {d}", .{ dx, dy });
    try widget.requestDraw();
}

pub fn main() !void {
    try capy.backend.init();
    defer _ = gpa.deinit();

    var window = try capy.Window.init();
    defer window.deinit();

    var canvas = try capy.Canvas(.{})
        .addDrawHandler(draw);
    try canvas.addScrollHandler(scroll);

    try window.set(capy.Column(.{}, .{
        capy.Row(.{}, .{
            capy.Expanded(capy.TextField(.{ .text = "gemini://gemini.circumlunar.space/" })),
            capy.Button(.{ .label = "Go!" }),
        }),
        capy.TextField(.{ .text = "other text" }),
        capy.Expanded(&canvas),
    }));

    window.resize(800, 600);
    window.show();
    capy.runEventLoop();
}
