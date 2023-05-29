const std = @import("std");
const capy = @import("capy");
pub usingnamespace capy.cross_platform;

pub fn main() !void {
    try capy.backend.init();
    var window = try capy.Window.init();

    try window.set(
        capy.Margin(capy.Rectangle.init(10, 10, 10, 10), capy.Column(.{}, .{
            capy.Label(.{ .text = "Hello, World", .alignment = .Left }), // TODO: capy.Heading (= label with bold + big font)
            capy.Label(.{ .text = 
            \\ Lorem ipsum dolor sit amet, consectetur adipiscing elit, sed do eiusmod tempor incididunt ut labore et dolore magna aliqua. Ut enim ad minim veniam, quis nostrud exercitation ullamco laboris nisi ut aliquip ex ea commodo consequat. Duis aute irure dolor in reprehenderit in voluptate velit esse cillum dolore eu fugiat nulla pariatur. Excepteur sint occaecat cupidatat non proident, sunt in culpa qui officia deserunt mollit anim id est laborum.
            }),
            capy.Spacing(),
            capy.Align(.{ .x = 1.0 }, capy.Row(.{}, .{
                capy.Button(.{ .label = "Previous", .enabled = false }),
                capy.Button(.{ .label = "Next" }),
            })),
        })),
    );
    window.setTitle("Installer");
    window.setPreferredSize(800, 600);
    window.show();
    capy.runEventLoop();
}
