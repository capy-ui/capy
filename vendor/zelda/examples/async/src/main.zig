const std = @import("std");
const zelda = @import("zelda");

const out = std.log.scoped(.async_zelda);

const ConcurrentFetchCount = 10_000;
const SmallestIntegerForFetchCount = std.math.IntFittingRange(0, ConcurrentFetchCount);

pub const io_mode = .evented;

pub fn main() anyerror!void {
    var allocator = std.heap.c_allocator;

    // var client_frames: [ConcurrentFetchCount]@Frame(fetchAndPrint) = undefined;
    var client_frames = try allocator.alloc(@Frame(fetchAndPrint), ConcurrentFetchCount);
    defer allocator.free(client_frames);
    var client_index: usize = 0;

    while (client_index < ConcurrentFetchCount) : (client_index += 1) {
        client_frames[client_index] = async fetchAndPrint(allocator, @intCast(SmallestIntegerForFetchCount, client_index));
    }

    var timer = try std.time.Timer.start();

    for (client_frames) |*frame, index| {
        await frame catch |why| {
            out.info("Client {} failed with {}", .{ index, why });
        };
    }

    std.debug.print("Collected {} results in {}", .{ ConcurrentFetchCount, std.fmt.fmtDuration(timer.read()) });
}

pub fn fetchAndPrint(allocator: std.mem.Allocator, client_id: SmallestIntegerForFetchCount) !void {
    var client = try zelda.HttpClient.init(allocator, .{});
    defer client.deinit();

    var request = zelda.request.Request{
        .method = .GET,
        .url = "http://example.com",
        .use_global_connection_pool = false,
    };

    const response = try client.perform(request);

    // const response = try zelda.get(allocator, "http://example.com");

    if (response.body) |body| {
        out.info("[{}] got {} bytes", .{ client_id, body.len });
    } else {
        out.info("[{}] got no body", .{client_id});
    }
}
