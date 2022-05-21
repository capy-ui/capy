const std = @import("std");
const zgt = @import("zgt");
pub usingnamespace zgt.cross_platform;

var opacity = zgt.DataWrapper(f32).of(0);

fn startAnimation(button: *zgt.Button_Impl) !void {
    // Ensure the current animation is done before starting another
    if (!opacity.hasAnimation()) {
        if (opacity.get() == 0) { // if hidden
            // Show the label in 1000ms
            opacity.animate(zgt.Easings.In, 1, 1000);
            button.setLabel("Hide");
        } else {
            // Hide the label in 1000ms
            opacity.animate(zgt.Easings.Out, 0, 1000);
            button.setLabel("Show");
        }
    }
}

pub fn main() !void {
    try zgt.backend.init();

    var window = try zgt.Window.init();
    const imageData = try zgt.ImageData.fromFile(zgt.internal.lasting_allocator, "ziglogo.png");

    try window.set(zgt.Column(.{}, .{zgt.Row(.{}, .{
        zgt.Expanded((try zgt.Row(.{}, .{
            zgt.Expanded(zgt.Label(.{ .text = "Hello Zig" })),
            zgt.Image(.{ .data = imageData }),
        }))
            .bindOpacity(&opacity)),
        zgt.Button(.{ .label = "Show", .onclick = startAnimation }),
    })}));

    window.resize(800, 450);
    window.show();
    zgt.runEventLoop();
}
