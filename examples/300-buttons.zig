const std = @import("std");
const capy = @import("capy");
pub usingnamespace capy.cross_platform;

// This is a stress test to see how well Capy performs with 300 buttons

pub fn main() !void {
    try capy.backend.init();
    const start = std.time.milliTimestamp();

    var window = try capy.Window.init();

    const NUM_ROWS = 30;
    const ROW_ITEMS = 10;

    // This is only used for additional performance
    var labelArena = std.heap.ArenaAllocator.init(capy.internal.scratch_allocator);
    defer labelArena.deinit();
    const labelAllocator = labelArena.child_allocator;

    var column = try capy.Column(.{}, .{});
    var i: usize = 0;
    while (i < NUM_ROWS) : (i += 1) {
        var row = try capy.Row(.{}, .{});
        var j: usize = 0;
        while (j < ROW_ITEMS) : (j += 1) {
            const buttonLabel = try std.fmt.allocPrintZ(labelAllocator, "Button #{d}", .{ j + i * ROW_ITEMS + 1 });
            try row.add(capy.Button(.{ .label = buttonLabel }));
        }

        try column.add(row);
    }

    try window.set(capy.Scrollable(
        &column
    ));
    window.resize(800, 600);
    window.show();
    
    const end = std.time.milliTimestamp();
    std.log.info("Took {d}ms for creating {d} buttons", .{ end - start, NUM_ROWS * ROW_ITEMS });

    capy.runEventLoop();
}
