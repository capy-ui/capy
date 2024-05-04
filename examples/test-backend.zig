const std = @import("std");
const capy = @import("capy");
pub usingnamespace capy.cross_platform;

pub fn main() !void {
    try capy.backend.init();

    var window = try capy.Window.init();
    try window.set(
        capy.row(.{}, .{}),
    );

    window.setTitle("Basic Backend Test");
    window.setPreferredSize(800, 450);
    window.show();
    capy.runEventLoop();
}
