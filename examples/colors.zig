const std = @import("std");
const capy = @import("capy");
pub usingnamespace capy.cross_platform;

var prng: std.rand.DefaultPrng = undefined; // initialized in main()
var random = prng.random();

pub fn animateRandomColor(button: *capy.Button_Impl) !void {
    const root = button.getRoot().?;
    const rect = root.get("background-rectangle").?.as(capy.Rect_Impl);
    const randomColor = capy.Color{ .red = random.int(u8), .green = random.int(u8), .blue = random.int(u8) };
    rect.color.animate(capy.Easings.InOut, randomColor, 1000);
}

pub fn main() !void {
    try capy.backend.init();
    var window = try capy.Window.init();
    prng = std.rand.DefaultPrng.init(@bitCast(u64, std.time.milliTimestamp()));

    window.resize(800, 600);
    try window.set(capy.Stack(.{
        capy.Rect(.{ .color = capy.Color.transparent })
            .setName("background-rectangle"),
        capy.Column(.{}, .{
            capy.Button(.{ .label = "Random color", .onclick = animateRandomColor })
                .setAlignX(0.5),
        }),
    }));
    window.show();
    capy.runEventLoop();
}
