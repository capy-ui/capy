const std = @import("std");
const zgt = @import("zgt");
pub usingnamespace zgt.cross_platform;

var celsius    = zgt.DataWrapper([]const u8).of("0");
var fahrenheit = zgt.DataWrapper([]const u8).of("-40");

// Small buffers to avoid memory allocations when editing the values
var celsiusBuffer   : [100]u8 = undefined;
var fahrenheitBuffer: [100]u8 = undefined;

pub fn main() !void {
    try zgt.backend.init();

    var window = try zgt.Window.init();

    try window.set(zgt.Column(.{}, .{
        zgt.Row(.{ .alignX = 0.5 }, .{
            zgt.Row(.{ .alignY = 0.5, .spacing = 5 }, .{
                zgt.TextField(.{})
                    .setName("celsius-field")
                    .bindText(&celsius),
                zgt.Label(.{ .text = "Celsius =" }),
                zgt.TextField(.{})
                    .setName("fahrenheit-field")
                    .bindText(&fahrenheit),
                zgt.Label(.{ .text = "Fahrenheit" }),
            }),
        }),
    }));

    _ = try celsius.addChangeListener(.{ .function = onCelsiusChange });
    _ = try fahrenheit.addChangeListener(.{ .function = onFahrenheitChange });

    window.setTitle("Temperature Converter");
    window.resize(500, 200);
    window.show();

    zgt.runEventLoop();
}

pub fn onCelsiusChange(newValue: []const u8, _: usize) void {
    if (std.fmt.parseFloat(f32, newValue)) |number| {
        const fahrenheitTemp = number * (9.0 / 5.0) + 32;

        // {d:.1} means print the float in decimal form and round it to 1 digit after the dot
        const text = std.fmt.bufPrint(&fahrenheitBuffer, "{d:.1}", .{ fahrenheitTemp })
            catch unreachable; // We know this is unreachable as a f32 will never exceed 100 characters
        fahrenheit.set(text);
    } else |err| switch (err) {
        error.InvalidCharacter => {
            fahrenheit.set("");
        }
    }
}

pub fn onFahrenheitChange(newValue: []const u8, _: usize) void {
    if (std.fmt.parseFloat(f32, newValue)) |number| {
        const celsiusTemp = (number - 32) * (5.0 / 9.0);
        const text = std.fmt.bufPrint(&celsiusBuffer, "{d:.1}", .{ celsiusTemp }) catch unreachable;
        celsius.set(text);
    } else |err| switch (err) {
        error.InvalidCharacter => {
            celsius.set("");
        }
    }
}
