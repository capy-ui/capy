//! This is a test for Capy's ease of use when using lists of many items
const capy = @import("capy");
const std = @import("std");

// TODO: automatic initialisation using default values
// The state can be configured using a tuple which may contain values or data wrappers
// If data wrapper -> bind
// If value -> set
const CounterState = struct {
    count: capy.DataWrapper(i64) = capy.DataWrapper(i64).of(0),
};

fn Counter() anyerror!capy.Align_Impl {
    var count = capy.DataWrapper(i64).alloc(0); // TODO: DataWrapper.alloc
    var format = try capy.FormatDataWrapper(capy.internal.lasting_allocator, "{d}", .{count});
    // TODO: when to deinit format?

    // var state = CounterState{ .count = capy.DataWrapper(i64).of(0) };
    const state = try capy.internal.lasting_allocator.create(CounterState);
    state.* = .{};

    // TODO: .{ .state = &state } to auto-deinit when the component is deinit
    return capy.Align(.{}, capy.Row(.{ .state = state }, .{
        capy.Button(.{
            .label = "-",
            .onclick = (struct {
                // TODO: switch back to *capy.Button_Impl when ziglang/zig#12325 is fixed
                fn sub(button_: *anyopaque) !void {
                    const button = @as(*capy.Button_Impl, @ptrCast(@alignCast(@alignOf(capy.Button_Impl), button_)));
                    _ = button;
                }
            }).sub,
        }),
        capy.TextField(.{ .text = "0", .readOnly = true })
            .bind("text", format),
        capy.Button(.{ .label = "+", .onclick = struct {
            fn add(_: *anyopaque) anyerror!void {
                state.count.set(state.count.get() + 1);
            }
        }.add }),
    }));
}

pub fn main() !void {
    try capy.init();

    var window = try capy.Window.init();
    try window.set(capy.Column(.{}, .{
        capy.Column(.{ .name = "counters-column" }, .{
            Counter(),
        }),
        capy.Align(.{}, capy.Button(.{ .label = "+" })),
    }));

    window.setTitle("Many Counters");
    window.setPreferredSize(800, 600);
    window.show();

    capy.runEventLoop();
}
