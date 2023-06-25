const std = @import("std");
const internal = @import("internal.zig");
const lasting_allocator = internal.lasting_allocator;

pub var _runningTimers = std.ArrayList(*Timer).init(lasting_allocator);

pub const Timer = struct {
    single_shot: bool = false,
    started: ?std.time.Instant = null,
    duration: u64 = 0,
    tick: *const fn () void,

    // TODO: timeout events
    pub fn init() !*Timer {
        const timer = try lasting_allocator.create(Timer);
        timer.* = .{};
        return timer;
    }

    pub fn start(self: *Timer, duration: u64) !void {
        if (self.started != null) {
            return error.TimerAlreadyRunning;
        }
        self.started = try std.time.Instant.now();
        self.duration = duration * std.time.ns_per_ms;
        try _runningTimers.append(self);
    }

    pub fn stop(self: *Timer) void {
        _ = self;
        // TODO: remove from _runningTimers
    }
};
