const capy = @import("capy");
pub usingnamespace capy.cross_platform;

pub fn main() !void {
    try capy.backend.init();

    var window = try capy.Window.init();

    try window.set(capy.Tabs(.{
        capy.Tab(.{ .label = "Border Layout" }, BorderLayoutExample()),
        capy.Tab(.{ .label = "Buttons" }, capy.Column(.{}, .{
            // alignX = 0 means buttons should be aligned to the left
            // TODO: use constraint layout (when it's added) to make all buttons same width
            capy.Button(.{ .label = "Button", .alignX = 0, .onclick = moveButton }),
            capy.Button(.{ .label = "Button (disabled)", .enabled = false, .alignX = 0 }),
        })),
    }));

    window.show();
    capy.runEventLoop();
}

// You can simulate a border layout using only Column, Row and Expanded
fn BorderLayoutExample() anyerror!capy.Container_Impl {
    return capy.Column(.{}, .{
        capy.Label(.{ .text = "Top" }),
        capy.Expanded(
            capy.Row(.{}, .{
                capy.Label(.{ .text = "Left" }),
                capy.Expanded(
                    capy.Label(.{ .text = "Center" }),
                ),
                capy.Label(.{ .text = "Right" }),
            }),
        ),
        capy.Label(.{ .text = "Bottom " }),
    });
}

fn moveButton(button_: *anyopaque) !void {
    const button = @ptrCast(*capy.Button_Impl, @alignCast(@alignOf(capy.Button_Impl), button_));
    const alignX = &button.dataWrappers.alignX;

    // Ensure the current animation is done before starting another
    if (!alignX.hasAnimation()) {
        if (alignX.get().? == 0) { // if on the left
            alignX.animate(capy.Easings.InOut, 1, 1000);
        } else {
            alignX.animate(capy.Easings.InOut, 0, 1000);
        }
    }
}