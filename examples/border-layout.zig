const std = @import("std");
const capy = @import("capy");
pub usingnamespace capy.cross_platform;

pub fn main() !void {
    try capy.backend.init();

    var window = try capy.Window.init();
    try window.set(capy.column(.{}, .{
        capy.label(.{ .text = "Top", .alignment = .Center }),
        capy.expanded(
            capy.row(.{}, .{
                capy.label(.{ .text = "Left", .alignment = .Center }),
                capy.expanded(
                    capy.label(.{ .text = "Center", .alignment = .Center }),
                ),
                capy.label(.{ .text = "Right", .alignment = .Center }),
            }),
        ),
        capy.label(.{ .text = "Bottom ", .alignment = .Center }),
    }));

    window.setTitle("Hello");
    window.setPreferredSize(250, 100);
    window.show();

    capy.runEventLoop();
}
