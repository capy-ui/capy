const std = @import("std");
const capy = @import("capy");
pub usingnamespace capy.cross_platform;

pub fn main() !void {
    try capy.init();
    defer capy.deinit();

    var window = try capy.Window.init();
    try window.set(
        capy.margin(capy.Rectangle.init(10, 10, 10, 10), capy.column(.{}, .{
            capy.label(.{ .text = "Hello, World" }), // TODO: capy.Heading (= label with bold + big font)
            capy.label(.{ .text = 
            \\ Lorem ipsum dolor sit amet, consectetur adipiscing elit, sed do eiusmod tempor incididunt ut labore et dolore magna aliqua. Ut enim ad minim veniam, quis nostrud exercitation ullamco laboris nisi ut aliquip ex ea commodo consequat. Duis aute irure dolor in reprehenderit in voluptate velit esse cillum dolore eu fugiat nulla pariatur. Excepteur sint occaecat cupidatat non proident, sunt in culpa qui officia deserunt mollit anim id est laborum.
            }),
            capy.spacing(),
            capy.alignment(.{ .x = 1.0 }, capy.row(.{}, .{
                capy.button(.{ .label = "Previous", .enabled = false }),
                capy.button(.{ .label = "Next" }),
            })),
        })),
    );
    window.setTitle("Installer");
    window.setPreferredSize(800, 600);
    window.show();
    capy.runEventLoop();
}
