usingnamespace @import("zgt");
const std = @import("std");

var gpa = std.heap.GeneralPurposeAllocator(.{}) {};
pub const zgtAllocator = &gpa.allocator;

fn draw(widget: *Canvas_Impl, ctx: DrawContext) !void {
    std.log.info("drawing widget", .{});
    ctx.setColor(0, 0, 0);
    ctx.rectangle(120, 320, 50, 50);
    ctx.fill();

    var layout = DrawContext.TextLayout.init();
    defer layout.deinit();
    ctx.setColor(1, 1, 1);
    layout.setFont(.{ .face = "Liberation Sans", .size = 12.0 });
    layout.wrap = 50;
    ctx.text(120, 320, layout, "Hello, World !");
    ctx.fill();
}

fn scroll(widget: *Canvas_Impl, dx: f64, dy: f64) !void {
    std.log.info("Scroll by {d}, {d}", .{dx, dy});
    try widget.requestDraw();
}

pub fn run() !void {
    defer _ = gpa.deinit();

    var window = try Window.init();
    var canvas = Canvas(.{});
    try canvas.addDrawHandler(draw);
    try canvas.addScrollHandler(scroll);
    std.log.info("{}", .{TextField_Impl.WidgetClass});
    try window.set(
        Column(.{}, .{
            TextField(.{ .text = "gemini://gemini.circumlunar.space/" }),
            TextField(.{ .text = "other text" }),
            //Expanded(
            //    &canvas
            //)
        })
    );

    window.resize(800, 600);
    window.show();
    window.run();
}
