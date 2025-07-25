const std = @import("std");
const internal = @import("internal.zig");
const lasting_allocator = internal.allocator;
const Atom = @import("data.zig").Atom;
const ListAtom = @import("data.zig").ListAtom;
const EventSource = @import("listener.zig").EventSource;

pub var runningTimers = ListAtom(*Timer).init(internal.allocator);

pub fn handleTimersTick(_: ?*anyopaque) void {
    const now = std.time.Instant.now() catch @panic("a monotonic clock is required for timers");

    var iterator = runningTimers.iterate();
    defer iterator.deinit();
    while (iterator.next()) |timer| {
        if (now.since(timer.started.?) >= timer.duration.get()) {
            timer.started = now;
            timer.tick();
            if (timer.single_shot) {
                timer.stop();
            }
        }
    }
}

pub const Timer = struct {
    /// Whether the timer should only fire once.
    single_shot: bool,
    started: ?std.time.Instant = null,
    /// Duration in nanoseconds
    /// Note that despite the fact that the duration is in nanoseconds, this does not mean
    /// that a sub-millisecond precision is guarenteed.
    duration: Atom(u64),
    /// The event source corresponding to the timer. It is fired every time the timer triggers.
    event_source: EventSource,

    pub const Options = struct {
        single_shot: bool,
        /// Duration in nanoseconds
        duration: u64,
    };

    pub fn init(options: Options) !*Timer {
        const timer = try lasting_allocator.create(Timer);
        timer.* = .{
            .single_shot = options.single_shot,
            .duration = Atom(u64).of(options.duration),
            .event_source = EventSource.init(lasting_allocator),
        };
        return timer;
    }

    pub fn start(self: *Timer) !void {
        if (self.started != null) {
            return error.TimerAlreadyRunning;
        }
        self.started = try std.time.Instant.now();
        try runningTimers.append(self);
    }

    pub fn bindFrequency(self: *Timer, frequency: *Atom(f32)) !void {
        var new_duration = Atom(u64).of(undefined);
        try new_duration.dependOn(.{frequency}, &computeDuration);
        self.duration.deinit();
        self.duration = new_duration;
    }

    fn computeDuration(frequency: f32) u64 {
        return @intFromFloat(1.0 / frequency * std.time.ns_per_ms);
    }

    fn tick(self: *Timer) void {
        self.event_source.callListeners();
    }

    pub fn stop(self: *Timer) void {
        // TODO: make it atomic so as to avoid race conditions
        const index = blk: {
            var iterator = runningTimers.iterate();
            defer iterator.deinit();

            break :blk std.mem.indexOfScalar(*Timer, iterator.getSlice(), self) orelse return;
        };
        std.debug.assert(runningTimers.swapRemove(index) == self);
    }
};
