const zgt = @import("zgt");
const std = @import("std");

var gpa = std.heap.GeneralPurposeAllocator(.{}) {};
pub const zgtAllocator = &gpa.allocator;

fn draw(widget: *zgt.Canvas_Impl, ctx: zgt.DrawContext) !void {
    _ = widget;
    std.log.info("drawing widget", .{});
    ctx.setColor(0, 0, 0);
    ctx.rectangle(120, 320, 50, 50);
    ctx.fill();

    var layout = zgt.DrawContext.TextLayout.init();
    defer layout.deinit();
    ctx.setColor(1, 1, 1);
    layout.setFont(.{ .face = "Liberation Sans", .size = 12.0 });
    layout.wrap = 50;
    ctx.text(120, 320, layout, "Hello, World !");
    ctx.fill();
}

fn scroll(widget: *zgt.Canvas_Impl, dx: f64, dy: f64) !void {
    std.log.info("Scroll by {d}, {d}", .{dx, dy});
    try widget.requestDraw();
}

pub fn main() !void {
    try zgt.backend.init();
    defer _ = gpa.deinit();

    var window = try zgt.Window.init();

    var canvas = zgt.Canvas(.{});
    try canvas.addDrawHandler(draw);
    try canvas.addScrollHandler(scroll);
    
    try window.set(
        zgt.Column(.{}, .{
            zgt.TextField(.{ .text = "gemini://gemini.circumlunar.space/" }),
            zgt.TextField(.{ .text = "other text" }),
            zgt.Expanded(
                &canvas
            )
        })
    );

    window.resize(800, 600);
    window.show();
    zgt.runEventLoop();
}
