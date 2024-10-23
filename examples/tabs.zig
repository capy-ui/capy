const capy = @import("capy");
pub usingnamespace capy.cross_platform;

pub fn main() !void {
    try capy.init();

    var window = try capy.Window.init();
    try window.set(capy.tabs(.{
        capy.tab(.{ .label = "Tab 1" }, capy.column(.{}, .{
            capy.button(.{ .label = "Test" }),
        })),
        capy.tab(.{ .label = "Tab 2" }, capy.button(.{ .label = "Test 2" })),
    }));

    window.show();
    capy.runEventLoop();
}
