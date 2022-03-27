const std = @import("std");
const zgt = @import("zgt");
pub usingnamespace zgt.cross_platform;

pub fn main() !void {
    try zgt.backend.init();

    var window = try zgt.Window.init();

    var column = try zgt.Column(.{}, .{});
    var i: usize = 0;
    while (i < 4) : (i += 1) {
        var row = try zgt.Row(.{}, .{});
        var j: usize = 0;
        while (j < 20) : (j += 1) {
            try row.add(try zgt.Column(.{}, .{zgt.Label(.{ .text = "Sample Item" })}));
        }

        try column.add(zgt.Label(.{ .text = "Row" }));
        try column.add(try zgt.Scrollable(row));
    }

    try window.set(&column);
    window.resize(800, 600);
    window.show();
    zgt.runEventLoop();
}
