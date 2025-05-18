const std = @import("std");
const capy = @import("capy");
pub usingnamespace capy.cross_platform;

// This is a stress test to see how well Capy performs with 300 buttons

pub fn main() !void {
    try capy.init();
    const start = std.time.milliTimestamp();

    var window = try capy.Window.init();

    const NUM_BUTTONS = 300;

    // This is only used for additional performance
    var label_arena = std.heap.ArenaAllocator.init(capy.internal.scratch_allocator);
    defer label_arena.deinit();
    const label_allocator = label_arena.child_allocator;

    const grid = try capy.grid(.{
        .template_columns = &([_]capy.GridLayoutConfig.LengthUnit{.{ .fraction = 1 }} ** 5),
        .template_rows = &.{ .{ .pixels = 150 }, .{ .pixels = 300 } },
        .column_spacing = 5,
        .row_spacing = 10,
    }, .{});
    var i: usize = 0;
    while (i < NUM_BUTTONS) : (i += 1) {
        const button_label = try std.fmt.allocPrintZ(label_allocator, "Button #{d}", .{i + 1});
        try grid.add(capy.button(.{ .label = button_label }));
    }

    try window.set(capy.alignment(.{}, grid));
    window.setPreferredSize(800, 600);
    window.show();

    const end = std.time.milliTimestamp();
    std.log.info("Took {d}ms for creating {d} buttons", .{ end - start, NUM_BUTTONS });

    capy.runEventLoop();
}
