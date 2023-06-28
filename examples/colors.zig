const std = @import("std");
const capy = @import("capy");
pub usingnamespace capy.cross_platform;

var prng: std.rand.DefaultPrng = undefined; // initialized in main()
var random = prng.random();

pub fn animateRandomColor(button_: *anyopaque) !void {
    // This part is a workaround to ziglang/zig#12325
    const button: *capy.Button_Impl = @ptrCast(@alignCast(button_));

    const root = button.getRoot().?.as(capy.Container_Impl);
    const rect = root.getChild("background-rectangle").?.as(capy.Rect_Impl);
    const randomColor = capy.Color{ .red = random.int(u8), .green = random.int(u8), .blue = random.int(u8) };
    rect.color.animate(capy.Easings.InOut, randomColor, 1000);
}

pub fn main() !void {
    try capy.init();
    var window = try capy.Window.init();
    prng = std.rand.DefaultPrng.init(@as(u64, @bitCast(std.time.milliTimestamp())));

    window.setPreferredSize(800, 600);
    try window.set(capy.Stack(.{
        capy.Rect(.{ .name = "background-rectangle", .color = capy.Color.transparent }),
        capy.Column(.{}, .{
            capy.Align(.{}, capy.Button(.{ .label = "Random color", .onclick = animateRandomColor })),
        }),
    }));
    window.show();
    capy.runEventLoop();
}
