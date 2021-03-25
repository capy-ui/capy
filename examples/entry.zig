usingnamespace @import("zgt");
const std = @import("std");

fn draw(ctx: DrawContext, widget: *Canvas_Impl) !void {
    ctx.setColorRGBA(0, 0, 0, 1);
    ctx.rectangle(100, 100, 200, 100);
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
