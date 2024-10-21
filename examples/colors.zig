const std = @import("std");
const capy = @import("capy");
pub usingnamespace capy.cross_platform;

var prng: std.Random.DefaultPrng = undefined; // initialized in main()
var random = prng.random();

pub fn animateRandomColor(button_: *anyopaque) !void {
    // This part is a workaround to ziglang/zig#12325
    const button: *capy.Button = @ptrCast(@alignCast(button_));

    const root = button.getRoot().?.as(capy.Container);
    const rect = root.getChild("background-rectangle").?.as(capy.Rect);
    const randomColor = capy.Color{ .red = random.int(u8), .green = random.int(u8), .blue = random.int(u8) };
    rect.color.animate(capy.Easings.InOut, randomColor, 1000);
}

pub fn main() !void {
    try capy.init();
    var window = try capy.Window.init();
    prng = std.Random.DefaultPrng.init(@as(u64, @bitCast(std.time.milliTimestamp())));

    window.setPreferredSize(800, 600);

    const selectedValue = capy.Atom([]const u8).alloc("");
    defer selectedValue.deinit();

    try window.set(capy.stack(.{
        capy.rect(.{ .name = "background-rectangle", .color = capy.Colors.transparent }),
        capy.column(.{}, .{
            capy.alignment(.{}, capy.button(.{ .label = "Random color", .onclick = animateRandomColor })),
            // dropdown,
            capy.label(.{})
                .bind("text", selectedValue),
        }),
    }));
    window.show();
    capy.runEventLoop();
}
