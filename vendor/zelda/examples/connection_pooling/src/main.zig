const std = @import("std");
const zelda = @import("zelda");

const out = std.log.scoped(.connection_pooling);

const TestCount = 32;

pub fn main() anyerror!void {
    var arena = std.heap.ArenaAllocator.init(std.heap.c_allocator);
    defer arena.deinit();

    const url = "http://example.com";
    var timer = try std.time.Timer.start();
    const no_pool_average = try testConnection(arena.allocator(), url, false);
    std.debug.print("no pool took: {}\n", .{std.fmt.fmtDuration(timer.lap())});
    const pool_average = try testConnection(arena.allocator(), url, true);
    std.debug.print("pool took: {}\n", .{std.fmt.fmtDuration(timer.lap())});

    if (pool_average < no_pool_average)
        std.debug.print("{} runs ea: pooling saved an avg of {}\n", .{ TestCount, std.fmt.fmtDuration(no_pool_average - pool_average) })
    else
        std.debug.print("{} runs ea: pooling was slower by an avg of {}\n", .{ TestCount, std.fmt.fmtDuration(pool_average - no_pool_average) });
}

fn testConnection(allocator: std.mem.Allocator, url: []const u8, use_conn_pool: bool) anyerror!u64 {
    var times = std.ArrayList(u64).init(allocator);
    defer times.deinit();

    var count: usize = 0;
    var timer = try std.time.Timer.start();
    while (count < TestCount) : (count += 1) {
        timer.reset();
        var client = try zelda.HttpClient.init(allocator, .{});
        defer client.deinit();

        var request = zelda.request.Request{ .method = .GET, .url = url, .use_global_connection_pool = use_conn_pool };

        _ = try client.perform(request);

        const requestDuration = timer.lap();
        try times.append(requestDuration);
        out.info("[{}] request took {}", .{ count + 1, std.fmt.fmtDuration(requestDuration) });
    }

    var sum: u64 = 0;
    for (times.items) |time|
        sum += time;
    const avg = sum / times.items.len;
    out.info("pool={}, Avg {}", .{ use_conn_pool, std.fmt.fmtDuration(avg) });
    return avg;
}
