const std = @import("std");
const internal = @import("internal.zig");
const lasting_allocator = internal.lasting_allocator;
const Atom = @import("data.zig").Atom;
const EventSource = @import("listener.zig").EventSource;

pub var _runningTimers = std.ArrayList(*Timer).init(lasting_allocator);

pub fn handleTimersTick() void {
    const now = std.time.Instant.now() catch unreachable;
    for (_runningTimers.items) |timer| {
        if (now.since(timer.started.?) >= timer.duration.get()) {
            timer.started = now;
            timer.tick(timer);
        }
    }
}

pub const Timer = struct {
    single_shot: bool = false,
    started: ?std.time.Instant = null,
    /// Duration in milliseconds
    duration: Atom(u64) = Atom(u64).of(0),
    event_source: EventSource,

    pub fn init() !*Timer {
        const timer = try lasting_allocator.create(Timer);
        timer.* = .{
            .event_source = EventSource.init(lasting_allocator),
        };
        return timer;
    }

    pub fn start(self: *Timer, duration: u64) !void {
        if (self.started != null) {
            return error.TimerAlreadyRunning;
        }
        self.started = try std.time.Instant.now();
        self.duration = Atom(u64).of(duration * std.time.ns_per_ms);
        try _runningTimers.append(self);
    }

    pub fn bindFrequency(self: *Timer, frequency: Atom(f32)) void {
        const duration = Atom(u64).derived(.{frequency}, computeDuration);
        self.duration.deinit();
        self.duration = duration;
    }

    fn computeDuration(frequency: f32) void {
        return @intFromFloat(1.0 / frequency * std.time.ns_per_ms);
    }

    pub fn stop(self: *Timer) void {
        const index = std.mem.indexOfScalar(Timer, _runningTimers.items, self);
        _runningTimers.swapRemove(index);
    }
};
