const std = @import("std");
const capy = @import("capy");

pub fn main() !void {
    try capy.init();

    var window = try capy.Window.init();
    try window.set(capy.column(.{}, .{
        capy.alignment(.{}, capy.label(.{ .text = "A", .name = "label-a" })),
        capy.alignment(.{}, capy.button(.{ .label = "Transition", .onclick = @ptrCast(&buttonTransition) })),
    }));

    window.setPreferredSize(800, 600);
    window.show();
    capy.runEventLoop();
}

fn buttonTransition(button: *capy.Button) !void {
    _ = button;
    // const root = button.getRoot().?.as(capy.Container);
    // try root.autoAnimate(doTransition);
}

fn doTransition(root: *capy.Container) void {
    const labelA = root.getChild("label-a").?.as(capy.Label);
    labelA.getParent().?.as(capy.Alignment).x.set(0.0);
    labelA.text.set("B");
}
