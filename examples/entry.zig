usingnamespace @import("zgt");
const std = @import("std");

pub fn run() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}) {};
    const allocator = &gpa.allocator;
    defer _ = gpa.deinit();

    var window = try Window.init();

    try window.set(
        try Column(.{}, .{
            TextField(.{ .text = "something here" }),
            try Expanded(try Row(.{}, .{

            }))
        })
    );

    try window.resize(800, 600);
    window.show();
    window.run();
}
