usingnamespace @import("zgt");
const std = @import("std");

var gpa = std.heap.GeneralPurposeAllocator(.{}) {};
pub const zgtAllocator = &gpa.allocator;

fn draw(ctx: DrawContext, widget: *Canvas_Impl) !void {
    ctx.setColor(0, 0, 0);
    ctx.rectangle(120, 320, 50, 50);
    ctx.fill();

    ctx.setColor(1, 1, 1);
    var layout = DrawContext.TextLayout.init(ctx);
    layout.setFont(.{ .face = "Liberation Sans", .size = 12.0 });
    layout.wrap = 50;
    ctx.text(120, 320, layout, "Hello, World !");
    ctx.fill();
}

fn scroll(dx: f64, dy: f64, widget: *Canvas_Impl) !void {
    std.log.info("Scroll by {d}, {d}", .{dx, dy});
}

pub fn run() !void {
    defer _ = gpa.deinit();

    var window = try Window.init();
    var canvas = Canvas(.{});
    try canvas.addDrawHandler(draw);
    try canvas.addScrollHandler(scroll);

    try window.set(
        Column(.{}, .{
            TextField(.{ .text = "gemini://gemini.circumlunar.space/" }),
            Expanded(
                &canvas
            )
        })
    );

    window.resize(800, 600);
    window.show();
    window.run();
}
