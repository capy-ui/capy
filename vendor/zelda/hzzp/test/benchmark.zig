const std = @import("std");
const hzzp = @import("hzzp");

fn read_timer() u64 {
    return asm volatile (
        \\rdtsc
        \\shlq $32, %%rdx
        \\orq %%rdx, %%rax
        : [ret] "={rax}" (-> u64),
        :
        : "rax", "rdx"
    );
}

const tests = .{
    "response1.http",
    "response2.http",
    "response3.http",
};

const BenchmarkTime = struct {
    lowest: u64 = std.math.maxInt(u64),
    highest: u64 = std.math.minInt(u64),

    total: u64 = 0,
    count: usize = 0,
    bytes: usize = 0,

    fn add(self: *BenchmarkTime, time: u64, bytes: usize) void {
        if (time > self.highest) {
            self.highest = time;
        }

        if (time < self.lowest) {
            self.lowest = time;
        }

        self.total += time;
        self.count += 1;

        // this shouldn't change, but we take it from the first response
        self.bytes = bytes;
    }

    fn average(self: BenchmarkTime) f64 {
        return @intToFloat(f64, self.total) / @intToFloat(f64, self.count);
    }

    pub fn format(self: BenchmarkTime, comptime _: []const u8, _: std.fmt.FormatOptions, writer: anytype) !void {
        try writer.print("Lo-Hi {d: >6} -> {d: <6} | Avg {d: <9.3} | {d:.6} B/C | {d} entries", .{
            self.lowest,
            self.highest,
            self.average(),
            @intToFloat(f64, self.bytes) / self.average(),
            self.count,
        });
    }
};

const Benchmark = struct {
    initialization: BenchmarkTime,
    status_line: BenchmarkTime,
    headers: BenchmarkTime,
    payload: BenchmarkTime,
};

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();

    const allocator = gpa.allocator();

    inline for (tests) |name| {
        const response_content = try std.fs.cwd().readFileAlloc(allocator, name, 2048);
        defer allocator.free(response_content);

        var initialization = BenchmarkTime{};
        var status_line = BenchmarkTime{};
        var headers = BenchmarkTime{};
        var payload = BenchmarkTime{};
        var other = BenchmarkTime{};

        var trial: u32 = 0;
        while (trial < 1_000_000) : (trial += 1) {
            var response = std.io.fixedBufferStream(response_content);
            const reader = response.reader();

            var start: u64 = undefined;
            var stop: u64 = undefined;

            var pos_start: usize = undefined;
            var pos_stop: usize = undefined;

            start = read_timer();

            var buffer: [256]u8 = undefined;
            var client = hzzp.base.client.create(&buffer, reader, std.io.null_writer);

            stop = read_timer();

            initialization.add(stop - start, 0);

            pos_start = response.pos;
            start = read_timer();
            while (try client.next()) |event| {
                stop = read_timer();
                pos_stop = response.pos;

                switch (event) {
                    .status => status_line.add(stop - start, pos_stop - pos_start),
                    .header => headers.add(stop - start, pos_stop - pos_start),
                    .payload => payload.add(stop - start, pos_stop - pos_start),
                    else => other.add(stop - start, pos_stop - pos_start),
                }

                pos_start = response.pos;
                start = read_timer();
            }
        }

        std.debug.print("Test {s}\n", .{name});
        std.debug.print("Initialization: {d}\n", .{initialization});
        std.debug.print("Status Line:    {d}\n", .{status_line});
        std.debug.print("Headers:        {d}\n", .{headers});
        std.debug.print("Payload:        {d}\n", .{payload});
        std.debug.print("Other:          {d}\n", .{other});
    }
}

// zig run benchmark.zig --pkg-begin hzzp ../src/main.zig --pkg-end
