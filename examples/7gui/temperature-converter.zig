const std = @import("std");
const capy = @import("capy");
pub usingnamespace capy.cross_platform;

var celsius = capy.Atom([]const u8).of("0");
var fahrenheit = capy.Atom([]const u8).of("-40");

// Small buffers so that we can edit the values without even allocating memory in the app
var celsiusBuffer: [100]u8 = undefined;
var fahrenheitBuffer: [100]u8 = undefined;

pub fn main() !void {
    try capy.init();
    defer celsius.deinit();
    defer fahrenheit.deinit();

    var window = try capy.Window.init();
    defer window.deinit();

    try window.set(capy.alignment(
        .{},
        capy.row(.{ .spacing = 5 }, .{
            capy.textField(.{})
                .withBinding("text", &celsius),
            capy.label(.{ .text = "Celsius =" }),
            capy.textField(.{})
                .withBinding("text", &fahrenheit),
            capy.label(.{ .text = "Fahrenheit" }),
        }),
    ));

    _ = try celsius.addChangeListener(.{ .function = onCelsiusChange });
    _ = try fahrenheit.addChangeListener(.{ .function = onFahrenheitChange });

    window.setTitle("Temperature Converter");
    window.setPreferredSize(500, 200);
    window.show();

    capy.runEventLoop();
}

pub fn onCelsiusChange(newValue: []const u8, _: ?*anyopaque) void {
    if (std.fmt.parseFloat(f32, newValue)) |number| {
        const targetFahrenheitTemp = number * (9.0 / 5.0) + 32;
        const currentFahrenheitTemp = std.fmt.parseFloat(f32, fahrenheit.get()) catch std.math.nan(f32);

        if (targetFahrenheitTemp != currentFahrenheitTemp) {
            // {d:.1} means print the float in decimal form and round it to 1 digit after the dot
            const text = std.fmt.bufPrint(&fahrenheitBuffer, "{d:.1}", .{targetFahrenheitTemp}) catch unreachable; // We know this is unreachable as a f32 will never exceed 100 characters
            fahrenheit.set(text);
        }
    } else |err| switch (err) {
        error.InvalidCharacter => {
            // fahrenheit.set("");
        },
    }
}

pub fn onFahrenheitChange(newValue: []const u8, _: ?*anyopaque) void {
    if (std.fmt.parseFloat(f32, newValue)) |number| {
        const targetCelsiusTemp = (number - 32) * (5.0 / 9.0);
        const currentCelsiusTemp = std.fmt.parseFloat(f32, celsius.get()) catch std.math.nan(f32);
        if (targetCelsiusTemp != currentCelsiusTemp) {
            const text = std.fmt.bufPrint(&celsiusBuffer, "{d:.1}", .{targetCelsiusTemp}) catch unreachable;
            celsius.set(text);
        }
    } else |err| switch (err) {
        error.InvalidCharacter => {
            // celsius.set("");
        },
    }
}
