const std = @import("std");
const capy = @import("capy");
pub usingnamespace capy.cross_platform;

pub fn main() !void {
    try capy.backend.init();

    const imageData = try capy.ImageData.fromBuffer(capy.internal.lasting_allocator, @embedFile("ziglogo.png"));

    var window = try capy.Window.init();
    try window.set(capy.Stack(.{
        capy.Rect(.{ .color = capy.Color.comptimeFromString("#2D2D2D") }),
        capy.Image(.{ .data = imageData }),
        capy.Column(.{}, .{
            capy.Spacing(),
            capy.Row(.{}, .{
                capy.Button(.{ .label = "Previous", .enabled = false }), // TODO: capy Icon left arrow / previous + tooltip
                capy.Button(.{ .label = "Next", .enabled = false }), // TODO: capy Icon right arrow / next + tooltip
                capy.Expanded(capy.Label(.{ .text = "TODO: slider" })),
                capy.Button(.{ .label = "Fullscreen" }), // TODO: capy Icon fullscreen + tooltip
            }),
        }),
    }));

    window.setTitle("Slide Viewer");
    window.resize(800, 600);
    window.show();
    capy.runEventLoop();
}
