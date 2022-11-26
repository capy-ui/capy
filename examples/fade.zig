const std = @import("std");
const capy = @import("capy");
pub usingnamespace capy.cross_platform;

var opacity = capy.DataWrapper(f32).of(1.0);

// TODO: switch back to *capy.Button_Impl when ziglang/zig#12325 is fixed
fn startAnimation(button_: *anyopaque) !void {
    const button = @ptrCast(*capy.Button_Impl, @alignCast(@alignOf(capy.Button_Impl), button_));

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
    const imageData = try capy.ImageData.fromBuffer(capy.internal.lasting_allocator, @embedFile("ziglogo.png"));

    try window.set(
        capy.Row(.{}, .{
            capy.Expanded((try capy.Row(.{}, .{
                capy.Label(.{ .text = "Hello Zig" }),
                capy.Expanded(
                    capy.Image(.{ .data = imageData, .scaling = .Fit }),
                ),
            }))
                .bind("opacity", &opacity)),
            capy.Button(.{ .label = "Hide", .onclick = startAnimation }),
        }),
    );

    window.resize(800, 450);
    window.show();
    capy.runEventLoop();
}
