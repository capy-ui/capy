const std = @import("std");
const capy = @import("capy");
pub usingnamespace capy.cross_platform;

var opacity = capy.Atom(f32).of(1.0);

// TODO: switch back to *capy.Button_Impl when ziglang/zig#12325 is fixed
fn startAnimation(button_: *anyopaque) !void {
    const button = @as(*capy.Button, @ptrCast(@alignCast(button_)));

    // Ensure the current animation is done before starting another
    if (!opacity.hasAnimation()) {
        if (opacity.get() == 0) { // if hidden
            // Show the label in 1000ms
            opacity.animate(capy.Easings.In, 1, 1000);
            button.setLabel("Hide");
        } else {
            // Hide the label in 1000ms
            opacity.animate(capy.Easings.Out, 0, 1000);
            button.setLabel("Show");
        }
    }
}

pub fn main() !void {
    try capy.backend.init();

    var window = try capy.Window.init();
    // const imageData = try capy.ImageData.fromBuffer(capy.internal.lasting_allocator, @embedFile("ziglogo.png"));

    try window.set(
        capy.row(.{}, .{
            capy.expanded((try capy.row(.{}, .{
                capy.label(.{ .text = "Hello Zig" }),
                capy.expanded(
                    capy.image(.{ .url = "asset:///ziglogo.png", .scaling = .Fit, .opacity = 0 })
                        .bind("opacity", &opacity),
                ),
            }))),
            capy.button(.{ .label = "Hide", .onclick = startAnimation }),
        }),
    );

    window.setPreferredSize(800, 450);
    window.show();
    capy.runEventLoop();
}
