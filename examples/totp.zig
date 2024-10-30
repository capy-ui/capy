const std = @import("std");
const capy = @import("capy");

pub fn main() !void {
    try capy.init();
    defer capy.deinit();

    var window = try capy.Window.init();
    defer window.deinit();

    try window.set(
        capy.alignment(.{ .x = 0.5, .y = 0.5 }, capy.column(.{}, .{
            capy.label(.{ .text = "TOTP application" }),
            // TODO: columnlist
            capy.column(.{}, .{
                capy.label(.{ .text = "Application Name" }),
                capy.label(.{ .text = "TOTP Code: {}" }),
            }),
        })),
    );
    window.show();

    capy.runEventLoop();
}
