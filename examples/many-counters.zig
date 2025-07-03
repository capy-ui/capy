//! This is a test for Capy's ease of use when using lists of many items
const capy = @import("capy");
const std = @import("std");

// TODO: automatic initialisation using default values
// The state can be configured using a tuple which may contain values or data wrappers
// If data wrapper -> bind
// If value -> set
const CounterState = struct {
    count: capy.Atom(i64) = capy.Atom(i64).of(0),
};

fn counter() anyerror!*capy.Alignment {
    var state1 = try capy.internal.allocator.create(CounterState);
    state1.* = .{};
    const format = try capy.FormattedAtom(capy.internal.allocator, "{d}", .{&state1.count});
    // TODO: when to deinit format?

    return capy.alignment(
        .{},
        (try capy.row(.{}, .{
            capy.button(.{
                .label = "-",
                .onclick = (struct {
                    fn sub(pointer: *anyopaque) !void {
                        const button: *capy.Button = @ptrCast(@alignCast(pointer));
                        const state: *CounterState = button.getUserdata(CounterState).?;
                        state.count.set(state.count.get() - 1);
                    }
                }).sub,
            }),
            capy.textField(.{ .text = "0", .readOnly = true })
                .bind("text", format),
            capy.button(.{ .label = "+", .onclick = struct {
                fn add(pointer: *anyopaque) anyerror!void {
                    const button: *capy.Button = @ptrCast(@alignCast(pointer));
                    const state: *CounterState = button.getUserdata(CounterState).?;
                    state.count.set(state.count.get() + 1);
                }
            }.add }),
        }))
            .addUserdata(CounterState, state1),
    );
}

pub fn main() !void {
    try capy.init();

    var window = try capy.Window.init();
    try window.set(capy.column(.{}, .{
        capy.column(.{ .name = "counters-column" }, .{
            counter(),
            counter(),
            counter(),
        }),
        capy.alignment(.{}, capy.button(.{ .label = "+" })),
    }));

    window.setTitle("Many Counters");
    window.setPreferredSize(800, 600);
    window.show();

    capy.runEventLoop();
}
