usingnamespace @import("zgt");
const std = @import("std");

var label: TextField_Impl = undefined;

fn count(button: *Button_Impl) !void {
    var num = try std.fmt.parseInt(u64, label.getText(), 10);
    // TODO: fix memory leak
    label.setText(try std.fmt.allocPrintZ(zgtInternal.lasting_allocator, "{d}", .{num + 1}));
}

pub fn run() !void {
    var window = try Window.init();
    label = TextField(.{ .text = "0" });

    try window.set(
        Column(.{ .expand = .Fill }, .{
            Row(.{}, .{
                Expanded(&label),
                Expanded(Button(.{ .label = "Count", .onclick = count }))
            })
        })
    );

    window.resize(250, 100);
    window.show();
    window.run();
}
