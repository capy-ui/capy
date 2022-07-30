const capy = @import("capy");
pub usingnamespace capy.cross_platform;

pub fn main() !void {
    try capy.backend.init();

    var window = try capy.Window.init();
    try window.set(capy.Row(.{}, .{
        capy.Button(.{ .label = "Tree" }),
        capy.Expanded(capy.Button(.{ .label = "Main" })),
        capy.Button(.{ .label = "Misc" }),
    }));

    window.show();
    capy.runEventLoop();
}
