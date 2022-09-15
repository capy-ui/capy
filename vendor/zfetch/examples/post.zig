const std = @import("std");

const zfetch = @import("zfetch");

pub fn main() !void {
    try zfetch.init();
    defer zfetch.deinit();

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();
    defer _ = gpa.deinit();

    var headers = zfetch.Headers.init(allocator);
    defer headers.deinit();

    try headers.appendValue("Accept", "application/json");
    try headers.appendValue("Content-Type", "text/plain");

    var req = try zfetch.Request.init(allocator, "https://httpbin.org/post", null);
    defer req.deinit();

    try req.do(.POST, headers, "Hello, World!");

    const stdout = std.io.getStdOut().writer();

    try stdout.print("status: {d} {s}\n", .{ req.status.code, req.status.reason });
    try stdout.print("headers:\n", .{});
    for (req.headers.list.items) |header| {
        try stdout.print("  {s}: {s}\n", .{ header.name, header.value });
    }
    try stdout.print("body:\n", .{});

    const reader = req.reader();

    var buf: [1024]u8 = undefined;
    while (true) {
        const read = try reader.read(&buf);
        if (read == 0) break;

        try stdout.writeAll(buf[0..read]);
    }
}
