const std = @import("std");
const zgt = @import("zgt");
pub usingnamespace zgt.cross_platform;

var prng: std.rand.DefaultPrng = undefined; // initialized in main()
var random = prng.random();

pub fn animateRandomColor(button: *zgt.Button_Impl) !void {
    const root = button.getRoot().?;
    const rect = root.get("background-rectangle").?.as(zgt.Rect_Impl);
    const randomColor = zgt.Color{ .red = random.int(u8), .green = random.int(u8), .blue = random.int(u8) };
    rect.color.animate(zgt.Easings.InOut, randomColor, 1000);
}

pub fn main() !void {
    try zgt.backend.init();
    var window = try zgt.Window.init();
    prng = std.rand.DefaultPrng.init(@bitCast(u64, std.time.milliTimestamp()));

    window.resize(800, 600);
    try window.set(zgt.Stack(.{
        zgt.Rect(.{ .color = zgt.Color.transparent })
            .setName("background-rectangle"),
        zgt.Column(.{}, .{
            zgt.Button(.{ .label = "Random color", .onclick = animateRandomColor })
                .setAlignX(0.5),
        }),
    }));
    window.show();
    zgt.runEventLoop();
}
