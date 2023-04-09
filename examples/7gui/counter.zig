const std = @import("std");
const capy = @import("capy");
pub usingnamespace capy.cross_platform;

// Thanks to `FormattedAtom` (see below) we can use an int for couting
var count = capy.Atom(i64).of(0);

// TODO: switch back to *capy.Button_Impl when ziglang/zig#12325 is fixed
fn increment(_: *anyopaque) !void {
    count.rmw(struct {
        fn callback(old_value: i64) i64 {
            return old_value + 1;
        }
    }.callback);
}

pub fn main() !void {
    try capy.init();
    std.log.info(
        "Overhead of DataWrapper(i64) = {d} bytes, align = {d} bytes",
        .{ @sizeOf(capy.Atom(i64)) - @sizeOf(i64), @alignOf(capy.Atom(i64)) },
    );

    var window = try capy.Window.init();

    // Capy is based around DataWrappers, which is just a way to bind properties, listen to changes, etc.
    // This allows to implement things like `FormatDataWrapper`, which takes other data wrappers as arguments
    // and formats them into text (same syntax as `std.fmt.format`), it can then be used like any other
    // DataWrapper.
    // However, FormatDataWrapper isn't bi-directional (editing the text field won't change count's value),
    // but it remains best fit for this example as the text field is read-only.
    var format = try capy.FormattedAtom(capy.internal.lasting_allocator, "{d}", .{&count});
    defer format.deinit();

    try window.set(capy.Align(
        .{},
        capy.Row(.{ .spacing = 5 }, .{
            capy.TextField(.{ .readOnly = true, .name = "text-field" })
                .bind("text", format),
            capy.Button(.{ .label = "Count", .onclick = increment }),
        }),
    ));

    window.setTitle("Counter");
    window.resize(250, 100);
    window.show();

    // Count to 100 in 2000ms
    count.animate(capy.Easings.InOut, 100, 2000);
    capy.runEventLoop();
}
