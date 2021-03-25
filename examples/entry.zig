usingnamespace @import("zgt");
const std = @import("std");

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

pub fn run() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}) {};
    const allocator = &gpa.allocator;
    defer _ = gpa.deinit();

    var window = try Window.init();
    var canvas = Canvas(.{});
    try canvas.addDrawHandler(draw);

    try window.set(
        try Column(.{}, .{
            TextField(.{ .text = "gemini://gemini.circumlunar.space/" }),
            try Expanded(
                &canvas
            )
        })
    );

    try window.resize(800, 600);
    window.show();
    window.run();
}
