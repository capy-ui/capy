usingnamespace @import("zgt");
const std = @import("std");

var label = StringDataWrapper.of("0");

fn count(button: *Button_Impl) !void {
    var num = try std.fmt.parseInt(u64, label.get(), 10);
    // TODO: fix memory leak
    label.set(try std.fmt.allocPrintZ(zgtInternal.lasting_allocator, "{d}", .{num + 1}));
    std.log.info("{s}", .{label.get()});
}

pub fn run() !void {
    var window = try Window.init();

    try window.set(
        Column(.{ .expand = .Fill }, .{
            Row(.{}, .{
                Expanded(
                    TextField(.{})
                        .setTextWrapper(label)
                ),
                Expanded(Button(.{ .label = "Count", .onclick = count }))
            })
        })
    );

    window.resize(250, 100);
    window.show();
    window.run();
}
