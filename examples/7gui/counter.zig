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

var buf: [128]u8 = undefined;
var gpa = std.heap.GeneralPurposeAllocator(.{}){};

pub const capy_allocator = gpa.allocator();
pub fn main() !void {
    defer _ = gpa.deinit();
    try capy.init();
    defer capy.deinit();
    defer count.deinit();

    std.log.info(
        "Overhead of Atom(i64) = {d} bytes, align = {d} bytes",
        .{ @sizeOf(capy.Atom(i64)) - @sizeOf(i64), @alignOf(capy.Atom(i64)) },
    );

    var window = try capy.Window.init();
    defer window.deinit();

    // Capy is based around Atoms, which is just a way to bind properties, listen to changes, etc.
    // This allows to implement things like `FormatAtom`, which takes other data wrappers as arguments
    // and formats them into text (same syntax as `std.fmt.format`), it can then be used like any other
    // Atom.
    // However, FormatAtom isn't bi-directional (editing the text field won't change count's value),
    // but it remains best fit for this example as the text field is read-only.
    var format = try capy.FormattedAtom(capy.internal.allocator, "{d}", .{&count});
    defer format.deinit();

    try window.set(capy.alignment(
        .{},
        capy.row(.{ .spacing = 5 }, .{
            capy.textField(.{ .readOnly = true, .name = "text-field" })
                .withBinding("text", format),
            capy.button(.{ .label = "Count", .onclick = increment }),
        }),
    ));

    window.setTitle("Counter");
    window.setPreferredSize(250, 100);
    window.show();

    // Count to 100 in 2000ms
    count.animate(window.animation_controller, capy.Easings.InOut, 100, 2000);
    capy.runEventLoop();
}
