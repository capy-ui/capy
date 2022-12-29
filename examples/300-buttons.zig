const std = @import("std");
const capy = @import("capy");
pub usingnamespace capy.cross_platform;

// This is a stress test to see how well Capy performs with 300 buttons

pub fn main() !void {
    try capy.backend.init();
    const start = std.time.milliTimestamp();

    var window = try capy.Window.init();

    const NUM_BUTTONS = 300;

    // This is only used for additional performance
    var labelArena = std.heap.ArenaAllocator.init(capy.internal.scratch_allocator);
    defer labelArena.deinit();
    const labelAllocator = labelArena.child_allocator;

    var row = try capy.Row(.{ .wrapping = true }, .{});
    var i: usize = 0;
    while (i < NUM_BUTTONS) : (i += 1) {
        const buttonLabel = try std.fmt.allocPrintZ(labelAllocator, "Button #{d}", .{i});
        try row.add(capy.Button(.{ .label = buttonLabel }));
    }

    try window.set(row);
    window.resize(800, 600);
    window.show();

    const end = std.time.milliTimestamp();
    std.log.info("Took {d}ms for creating {d} buttons", .{ end - start, NUM_BUTTONS });

    capy.runEventLoop();
}
