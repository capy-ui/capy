usingnamespace @import("zgt");

pub fn run() !void {
    var window = try Window.init();

    try window.set(
        Row(.{}, .{
            Button(.{ .label = "Tree" }),
            Expanded(
                Button(.{ .label = "Main" })
            ),
            Button(.{ .label = "Misc" })
        })
    );

    window.show();
    window.run();
}