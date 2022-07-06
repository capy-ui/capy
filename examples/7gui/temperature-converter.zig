const std = @import("std");
const zgt = @import("zgt");
pub usingnamespace zgt.cross_platform;

pub fn main() !void {
    try zgt.backend.init();

    var window = try zgt.Window.init();

    try window.set(zgt.Column(.{}, .{
        zgt.Row(.{ .alignX = 0.5 }, .{
            zgt.Row(.{ .alignY = 0.5, .spacing = 5 }, .{
                zgt.TextField(.{})
                    .setName("celsius-field"),
                zgt.Label(.{ .text = "Celsius =" }),
                zgt.TextField(.{})
                    .setName("fahrenheit-field"),
                zgt.Label(.{ .text = "Fahrenheit" }),
            }),
        }),
    }));

    window.setTitle("Temperature Converter");
    window.resize(500, 200);
    window.show();

    zgt.runEventLoop();
}
