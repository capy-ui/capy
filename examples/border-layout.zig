const std = @import("std");
const capy = @import("capy");
pub usingnamespace capy.cross_platform;

pub fn main() !void {
    try capy.backend.init();

    var window = try capy.Window.init();
    try window.set(capy.Column(.{}, .{
        capy.Label(.{ .text = "Top" }),
        capy.Expanded(
            capy.Row(.{}, .{
                capy.Label(.{ .text = "Left" }),
                capy.Expanded(
                    capy.Label(.{ .text = "Center" }),
                ),
                capy.Label(.{ .text = "Right" }),
            }),
        ),
        capy.Label(.{ .text = "Bottom " }),
    }));

    window.setTitle("Hello");
    window.setPreferredSize(250, 100);
    window.show();

    capy.runEventLoop();
}
