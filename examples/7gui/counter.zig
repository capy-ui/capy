const std = @import("std");
const capy = @import("capy");
pub usingnamespace capy.cross_platform;

// Thanks to `FormatDataWrapper` (see below) we can use an int for couting
var count = capy.DataWrapper(i64).of(0);

fn increment(_: *capy.Button_Impl) !void {
    count.set(count.get() + 1);
}

pub fn main() !void {
    try capy.backend.init();
    std.log.info("Overhead of DataWrapper(i64) = {d} bytes, align = {d} bytes", .{ @sizeOf(capy.DataWrapper(i64)) - @sizeOf(i64), @alignOf(capy.DataWrapper(i64)) });

    var window = try capy.Window.init();

    // Capy is based around DataWrappers, which is just a way to bind properties, listen to changes, etc.
    // This allows to implement things like `FormatDataWrapper`, which takes other data wrappers as arguments
    // and formats them into text (same syntax as `std.fmt.format`), it can then be used like any other
    // DataWrapper.
    // However, FormatDataWrapper isn't bi-directional (editing the text field won't change count's value),
    // but it remains best fit for this example as the text field is read-only.
    var format = try capy.FormatDataWrapper(capy.internal.lasting_allocator, "{d}", .{&count});
    defer format.deinit();

    try window.set(capy.Column(.{}, .{
        capy.Row(.{ .alignX = 0.5 }, .{
            capy.Row(.{ .alignY = 0.5, .spacing = 5 }, .{
                capy.TextField(.{ .readOnly = true })
                    .setName("text-field")
                    .bind("text", format),
                capy.Button(.{ .label = "Count", .onclick = increment }),
            }),
        }),
    }));

    window.setTitle("Counter");
    window.resize(250, 100);
    window.show();

    // Count to 100 in 2000ms
    count.animate(capy.Easings.InOut, 100, 2000);
    capy.runEventLoop();
}
