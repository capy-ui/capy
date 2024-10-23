const std = @import("std");
const capy = @import("capy");
pub usingnamespace capy.cross_platform;

pub fn main() !void {
    try capy.init();

    var window = try capy.Window.init();
    try window.set(capy.stack(.{
        capy.rect(.{ .color = capy.Color.comptimeFromString("#2D2D2D") }),
        capy.image(.{ .url = "asset:///ziglogo.png" }),
        capy.column(.{}, .{
            capy.spacing(),
            capy.row(.{}, .{
                capy.button(.{ .label = "Previous", .enabled = false }), // TODO: capy Icon left arrow / previous + tooltip
                capy.button(.{ .label = "Next", .enabled = false }), // TODO: capy Icon right arrow / next + tooltip
                capy.expanded(capy.label(.{ .text = "TODO: slider" })),
                capy.button(.{ .label = "Fullscreen" }), // TODO: capy Icon fullscreen + tooltip
            }),
        }),
    }));

    window.setTitle("Slide Viewer");
    window.setPreferredSize(800, 600);
    window.show();
    capy.runEventLoop();
}
