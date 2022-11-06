const std = @import("std");
const zelda = @import("zelda");

const IPResponse = struct {
    ip: []const u8,
};

pub fn main() anyerror!void {
    var arena = std.heap.ArenaAllocator.init(std.heap.c_allocator);
    defer arena.deinit();

    try printIPFromRaw(arena.allocator());
    try printIPFromJson(arena.allocator());
}

pub fn printIPFromJson(allocator: std.mem.Allocator) !void {
    const response = try zelda.getAndParseResponse(IPResponse, .{ .allocator = allocator }, allocator, "https://api64.ipify.org/?format=json");
    defer std.json.parseFree(IPResponse, response, .{ .allocator = allocator });

    var stdout = std.io.getStdOut().writer();

    try stdout.print("My ip is {s}\n", .{response.ip});
}

pub fn printIPFromRaw(allocator: std.mem.Allocator) !void {
    var response = try zelda.get(allocator, "http://api64.ipify.org/");
    defer response.deinit();

    var stdout = std.io.getStdOut().writer();

    if (response.body) |body|
        try stdout.print("My ip is {s}\n", .{body})
    else
        try stdout.writeAll("Failed to receive body from ipify\n");
}
