const std = @import("std");
const zgt = @import("zgt");

var label = zgt.StringDataWrapper.of("0");

fn count(button: *zgt.Button_Impl) !void {
    _ = button;
    var num = try std.fmt.parseInt(i64, label.get(), 10);
    // TODO: fix memory leak
    label.set(try std.fmt.allocPrintZ(zgt.internal.lasting_allocator, "{d}", .{num + 1}));
}

pub fn main() !void {
    try zgt.backend.init();

    var window = try zgt.Window.init();
    try window.set(
        zgt.Column(.{ .expand = .Fill }, .{
            zgt.Row(.{}, .{
                zgt.Expanded(
                    zgt.TextField(.{})
                        .bindText(&label)
                ),
                zgt.Button(.{ .label = "Count", .onclick = count })
            })
        })
    );

    window.resize(250, 100);
    window.show();
    zgt.runEventLoop();
}
