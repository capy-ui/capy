const std = @import("std");
const zgt = @import("zgt");

var count = zgt.DataWrapper(i64).of(0);
var label = zgt.StringDataWrapper.of("0");

fn increment(button: *zgt.Button_Impl) !void {
    _ = button;
    count.set(count.get() + 1);
}

pub fn main() !void {
    try zgt.backend.init();

    var window = try zgt.Window.init();
    
    var format = try zgt.FormatDataWrapper(zgt.internal.lasting_allocator, "{d}", .{ &count });
    defer format.deinit();
    try window.set(
        zgt.Column(.{ .expand = .Fill }, .{
            zgt.Row(.{}, .{
                zgt.Expanded(
                    zgt.TextField(.{})
                        .bindText(format)
                ),
                zgt.Button(.{ .label = "Count", .onclick = increment })
            })
        })
    );

    window.resize(250, 100);
    window.show();

    // Count to 100 in 2000ms
    count.animate(zgt.LinearAnimation, 100, 2000);

    while (zgt.stepEventLoop(.Asynchronous)) {
        _ = count.update();
        std.time.sleep(16);
    }
}
