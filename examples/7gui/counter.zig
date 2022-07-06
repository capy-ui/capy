const std = @import("std");
const zgt = @import("zgt");
pub usingnamespace zgt.cross_platform;

// Thanks to `FormatDataWrapper` (see below) we can use an int for couting
var count = zgt.DataWrapper(i64).of(0);

fn increment(_: *zgt.Button_Impl) !void {
    count.set(count.get() + 1);
}

pub fn main() !void {
    try zgt.backend.init();

    var window = try zgt.Window.init();

    // zgt is based around DataWrappers, which is just a way to bind properties, listen to changes, etc.
    // This allows to implement things like `FormatDataWrapper`, which takes other data wrappers as arguments
    // and formats them into text (same syntax as `std.fmt.format`), it can then be used like any other
    // DataWrapper.
    // However, FormatDataWrapper isn't bi-directional (editing the text field won't change count's value),
    // but it remains best fit for this example as the text field is read-only.
    var format = try zgt.FormatDataWrapper(zgt.internal.lasting_allocator, "{d}", .{&count});
    defer format.deinit();

    try window.set(zgt.Column(.{}, .{
        zgt.Row(.{ .alignX = 0.5 }, .{
            zgt.Row(.{ .alignY = 0.5, .spacing = 5 }, .{
                zgt.TextField(.{ .readOnly = true })
                    .setName("text-field")
                    .bindText(format),
                zgt.Button(.{ .label = "Count", .onclick = increment })
            }),
        }),
    }));

    window.setTitle("Counter");
    window.resize(250, 100);
    window.show();

    // Count to 100 in 2000ms
    count.animate(zgt.Easings.InOut, 100, 2000);
    zgt.runEventLoop();
}
