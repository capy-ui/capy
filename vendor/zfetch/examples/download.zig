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

    var req = try zfetch.Request.init(allocator, "https://speed.hetzner.de/100MB.bin", null);
    defer req.deinit();

    try req.do(.GET, headers, null);

    const file = try std.fs.cwd().createFile("file.txt", .{});
    const writer = file.writer();

    if (req.status.code != 200) {
        std.log.err("request failed", .{});
    }

    const reader = req.reader();

    var timer = std.time.Timer.start() catch unreachable;
    var size: usize = 0;

    var buf: [65535]u8 = undefined;
    while (true) {
        const read = try reader.read(&buf);
        if (read == 0) break;

        std.debug.print("\r{} bytes", .{size});

        size += read;
        try writer.writeAll(buf[0..read]);
    }

    const took = timer.read();
    std.log.info("\ndownloaded: {} bytes in {} seconds", .{ size, took / 1_000_000_000 });
}
