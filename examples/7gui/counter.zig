usingnamespace @import("zgt");
const std = @import("std");

var label = StringDataWrapper.of("0");

fn count(button: *Button_Impl) !void {
    var num = try std.fmt.parseInt(i64, label.get(), 10);
    // TODO: fix memory leak
    label.set(try std.fmt.allocPrintZ(zgtInternal.lasting_allocator, "{d}", .{num + 1}));
}

pub fn run() !void {
    var window = try Window.init();

    try window.set(
        Column(.{ .expand = .Fill }, .{
            Row(.{}, .{
                Expanded(
                    TextField(.{})
                        .bindText(&label)
                ),
                Expanded(Button(.{ .label = "Count", .onclick = count }))
            })
        })
    );

    window.resize(250, 100);
    window.show();
    window.run();
}
