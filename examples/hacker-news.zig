const std = @import("std");
const capy = @import("capy");

const Story = struct {
    title: []const u8,
    score: u32,
    by: []const u8,
};

const max_stories = 30;

const stub_stories = [_]Story{
    .{ .title = "Show HN: A cross-platform GUI framework written in Zig", .score = 342, .by = "zigdev" },
    .{ .title = "Why SQLite is so popular for embedded databases", .score = 256, .by = "dbfan" },
    .{ .title = "The secret history of the TCP/IP protocol", .score = 189, .by = "nethistorian" },
    .{ .title = "Rust vs. Zig: A practical comparison for systems programming", .score = 412, .by = "compilerdev" },
    .{ .title = "How we reduced our cloud bill by 80% with bare metal", .score = 523, .by = "infraengineer" },
    .{ .title = "The unreasonable effectiveness of simple algorithms", .score = 287, .by = "mathprof" },
    .{ .title = "Show HN: I built a text editor in 1000 lines of C", .score = 198, .by = "minimalist" },
    .{ .title = "Why every programmer should learn assembly language", .score = 156, .by = "lowleveldev" },
    .{ .title = "The complete guide to memory-mapped I/O", .score = 134, .by = "osdev" },
    .{ .title = "A deep dive into Linux kernel networking", .score = 278, .by = "kernelhacker" },
    .{ .title = "WebAssembly is eating the world", .score = 367, .by = "wasmfan" },
    .{ .title = "How DNS works: a visual guide", .score = 445, .by = "networkguru" },
    .{ .title = "The economics of open source software", .score = 312, .by = "osseconomist" },
    .{ .title = "Building a compiler from scratch in 30 days", .score = 234, .by = "langdesigner" },
    .{ .title = "Ask HN: What's your most productive programming setup?", .score = 189, .by = "proddev" },
};

// Global state shared between main thread and fetch thread
var stories: [max_stories]Story = undefined;
var story_count: usize = 0;
var fetch_done = std.atomic.Value(bool).init(false);
var fetch_mutex: std.Thread.Mutex = .{};

const ListModel = struct {
    size: capy.Atom(usize) = capy.Atom(usize).of(0),
    arena: std.heap.ArenaAllocator = std.heap.ArenaAllocator.init(capy.internal.allocator),

    pub fn getComponent(self: *ListModel, index: usize) *capy.Label {
        fetch_mutex.lock();
        defer fetch_mutex.unlock();
        if (index < story_count) {
            const story = stories[index];
            return capy.label(.{
                .text = std.fmt.allocPrintSentinel(
                    self.arena.allocator(),
                    "{d}. {s} ({d} points by {s})",
                    .{ index + 1, story.title, story.score, story.by },
                    0,
                ) catch unreachable,
            });
        }
        return capy.label(.{
            .text = std.fmt.allocPrintSentinel(
                self.arena.allocator(),
                "Loading item {d}...",
                .{index + 1},
                0,
            ) catch unreachable,
        });
    }
};

fn fetchStories() void {
    const persistent = capy.internal.allocator;

    var client: std.http.Client = .{ .allocator = persistent };
    defer client.deinit();

    // Fetch top story IDs
    var aw: std.Io.Writer.Allocating = .init(persistent);
    defer aw.deinit();

    const result = client.fetch(.{
        .location = .{ .url = "https://hacker-news.firebaseio.com/v0/topstories.json" },
        .response_writer = &aw.writer,
    }) catch {
        // Network failure — keep stub data
        fetch_done.store(true, .release);
        capy.wakeEventLoop();
        return;
    };

    if (result.status != .ok) {
        fetch_done.store(true, .release);
        capy.wakeEventLoop();
        return;
    }

    const body = aw.writer.buffer[0..aw.writer.end];

    const parsed_ids = std.json.parseFromSlice([]const i64, persistent, body, .{}) catch {
        fetch_done.store(true, .release);
        capy.wakeEventLoop();
        return;
    };
    defer parsed_ids.deinit();

    const ids = parsed_ids.value;
    const count = @min(ids.len, max_stories);

    // Fetch individual stories into a temp buffer
    var temp_stories: [max_stories]Story = undefined;
    var fetched: usize = 0;

    for (ids[0..count]) |id| {
        var item_aw: std.Io.Writer.Allocating = .init(persistent);
        defer item_aw.deinit();

        var url_buf: [128]u8 = undefined;
        const url = std.fmt.bufPrint(&url_buf, "https://hacker-news.firebaseio.com/v0/item/{d}.json", .{id}) catch continue;

        const item_result = client.fetch(.{
            .location = .{ .url = url },
            .response_writer = &item_aw.writer,
        }) catch continue;

        if (item_result.status != .ok) continue;

        const item_body = item_aw.writer.buffer[0..item_aw.writer.end];

        const HnItem = struct {
            title: ?[]const u8 = null,
            score: ?i64 = null,
            by: ?[]const u8 = null,
        };

        const parsed_item = std.json.parseFromSlice(HnItem, persistent, item_body, .{
            .ignore_unknown_fields = true,
        }) catch continue;
        defer parsed_item.deinit();

        const item = parsed_item.value;
        if (item.title) |title| {
            // Copy strings so they survive after parsed_item.deinit()
            const title_copy = persistent.dupeZ(u8, title) catch continue;
            const by_copy = if (item.by) |by|
                (persistent.dupeZ(u8, by) catch continue)
            else
                (persistent.dupeZ(u8, "unknown") catch continue);

            temp_stories[fetched] = .{
                .title = title_copy,
                .score = if (item.score) |s| @intCast(@as(u64, @intCast(@max(s, 0)))) else 0,
                .by = by_copy,
            };
            fetched += 1;
        }
    }

    if (fetched > 0) {
        // Atomically swap stories under mutex
        fetch_mutex.lock();
        for (temp_stories[0..fetched], 0..) |s, i| {
            stories[i] = s;
        }
        story_count = fetched;
        fetch_mutex.unlock();
    }

    fetch_done.store(true, .release);
    capy.wakeEventLoop();
}

pub fn main() !void {
    try capy.init();
    defer capy.deinit();

    // Populate with stub data initially
    for (stub_stories, 0..) |s, i| {
        stories[i] = s;
    }
    story_count = stub_stories.len;

    var hn_list_model = ListModel{};
    hn_list_model.size.set(stub_stories.len);

    var window = try capy.Window.init();
    try window.set(
        capy.stack(.{
            capy.rect(.{ .color = capy.Color.comptimeFromString("#f6f6ef") }),
            capy.column(.{}, .{
                capy.stack(.{
                    capy.rect(.{
                        .color = capy.Color.comptimeFromString("#ff6600"),
                        .cornerRadius = .{ 0.0, 0.0, 5.0, 5.0 },
                    }),
                    capy.label(.{ .text = "Hacker News", .layout = .{ .alignment = .Center } }),
                }),
                capy.columnList(.{}, &hn_list_model),
            }),
        }),
    );
    window.setPreferredSize(600, 800);
    window.setTitle("Hacker News");
    window.show();

    // Spawn background fetch thread
    const fetch_thread = std.Thread.spawn(.{}, fetchStories, .{}) catch null;

    while (capy.stepEventLoop(.Blocking)) {
        if (fetch_done.load(.acquire)) {
            fetch_done.store(false, .release);
            fetch_mutex.lock();
            const count = story_count;
            fetch_mutex.unlock();
            hn_list_model.size.set(count);
        }
    }

    if (fetch_thread) |t| t.join();
}
