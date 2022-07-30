const capy = @import("capy");
pub usingnamespace capy.cross_platform;

pub fn main() !void {
    try capy.backend.init();

    var window = try capy.Window.init();
    try window.set(capy.Tabs(.{
        capy.Tab(.{ .label = "Tab 1" }, capy.Column(.{}, .{
            capy.Button(.{ .label = "Test" }),
        })),
        capy.Tab(.{ .label = "Tab 2" }, capy.Button(.{ .label = "Test 2" })),
    }));

    window.show();
    capy.runEventLoop();
}
