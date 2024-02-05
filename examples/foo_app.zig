const std = @import("std");
const capy = @import("capy");
pub usingnamespace capy.cross_platform;

pub fn main() !void {
    try capy.backend.init();

    var window = try capy.Window.init();

    var column = try capy.column(.{}, .{});
    var i: usize = 0;
    while (i < 4) : (i += 1) {
        var row = try capy.row(.{}, .{});
        var j: usize = 0;
        while (j < 20) : (j += 1) {
            try row.add(try capy.column(.{}, .{capy.label(.{ .text = "Sample Item" })}));
        }

        try column.add(capy.label(.{ .text = "Row" }));
        try column.add(try capy.scrollable(row));
    }

    try window.set(capy.scrollable(column));
    window.setPreferredSize(800, 600);
    window.show();
    capy.runEventLoop();
}
