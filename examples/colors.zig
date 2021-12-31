const std = @import("std");
const zgt = @import("zgt");
pub usingnamespace zgt.cross_platform;

var prng: std.rand.DefaultPrng = std.rand.DefaultPrng.init(0);
var random = prng.random();

pub fn animateRandomColor(button: *zgt.Button_Impl) !void {
    const root = button.getRoot().?;
    const rect = root.get("background-rectangle").?.as(zgt.Rect_Impl);
    const randomColor = zgt.Color {
        .red = random.int(u8),
        .green = random.int(u8),
        .blue = random.int(u8)
    };
    rect.color.animate(zgt.Easings.InOut, randomColor, 1000);
}

pub fn main() !void {
    try zgt.backend.init();
    var window = try zgt.Window.init();

    window.resize(800, 600);
    try window.set(
        zgt.Stack(.{
            zgt.Rect(.{ .color = zgt.Color.transparent })
                .setName("background-rectangle"),
            zgt.Column(.{}, .{
                zgt.Button(.{ .label = "Random color", .onclick = animateRandomColor })
            })
        })
    );
    window.show();
    zgt.runEventLoop();
}
