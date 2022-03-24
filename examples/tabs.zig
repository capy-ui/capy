const zgt = @import("zgt");
pub usingnamespace zgt.cross_platform;

pub fn main() !void {
    try zgt.backend.init();

    var window = try zgt.Window.init();
    try window.set(
        zgt.Tabs(.{
            zgt.Tab(.{ .name = "Tab 1" }, zgt.Button(.{ .label = "Test" })),
            zgt.Tab(.{ .name = "Tab 2" }, zgt.Button(.{ .label = "Test 2" })),
        })
    );

    window.show();
    zgt.runEventLoop();
}
