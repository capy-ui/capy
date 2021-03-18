usingnamespace @import("zgt");
const std = @import("std");

var area: TextArea_Impl = undefined;

pub fn run() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}) {};
    const allocator = &gpa.allocator;
    defer _ = gpa.deinit();

    var window = try Window.init();

    var file = try std.fs.cwd().openFileZ("zide.zig", .{ .read = true });
    defer file.close();
    const text = try file.readToEndAlloc(allocator, std.math.maxInt(usize));
    defer allocator.free(text);

    area = TextArea(.{ .text = text });
    try window.set(
        try Column(.{}, .{
            try Row(.{}, .{
                Button(.{ .label = "Save" }),
                Button(.{ .label = "Run"  })
            }),
            try Expanded(&area)
        })
    );

    try window.resize(800, 600);
    window.show();
    window.run();
}
