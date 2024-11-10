const std = @import("std");
const capy = @import("capy");
pub usingnamespace capy.cross_platform;

pub fn main() !void {
    try capy.init();

    var window = try capy.Window.init();
    try window.set(capy.column(.{}, .{
        capy.label(.{ .text = "Top", .layout = .{ .alignment = .Center } }),
        capy.expanded(
            capy.row(.{}, .{
                capy.label(.{ .text = "Left", .layout = .{ .alignment = .Center } }),
                capy.expanded(
                    capy.label(.{ .text = "Center", .layout = .{ .alignment = .Center } }),
                ),
                capy.label(.{ .text = "Right", .layout = .{ .alignment = .Center } }),
            }),
        ),
        capy.label(.{ .text = "Bottom ", .layout = .{ .alignment = .Center } }),
    }));

    window.setTitle("Hello");
    window.setPreferredSize(250, 100);
    window.show();

    capy.runEventLoop();
}
