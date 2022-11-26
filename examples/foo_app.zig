const std = @import("std");
const capy = @import("capy");
pub usingnamespace capy.cross_platform;

pub fn main() !void {
    try capy.backend.init();

    var window = try capy.Window.init();

    var column = try capy.Column(.{}, .{});
    var i: usize = 0;
    while (i < 4) : (i += 1) {
        var row = try capy.Row(.{}, .{});
        var j: usize = 0;
        while (j < 20) : (j += 1) {
            try row.add(try capy.Column(.{}, .{capy.Label(.{ .text = "Sample Item" })}));
        }

        try column.add(capy.Label(.{ .text = "Row" }));
        try column.add(try capy.Scrollable(row));
    }

    try window.set(capy.Scrollable(&column));
    window.resize(800, 600);
    window.show();
    capy.runEventLoop();
}
