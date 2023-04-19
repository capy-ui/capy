//! This is a temporary module made in wait for Zig's async API to stabilise and get better
//! It doesn't directly implement async I/O, but it does implement multiple threads in order to do so.
const std = @import("std");
const internal = @import("internal.zig");
const Futex = std.Thread.Futex;

pub const ThreadPool = struct {
    list: std.ArrrayList(ThreadEntry),
    /// A lock for creating new tasks and removing previous ones.
    /// Given the length of the tasks, the overhead of a mutex is negligible.
    lock: std.Thread.Mutex,
    pending_tasks: TaskQueue,

    const ThreadEntry = struct {
        thread: std.Thread,
        /// The last time a task was executed on this thread, in milliseconds.
        last_used: i64,
        busy: std.atomic.Atomic(bool) = false,
    };

    pub fn init(allocator: std.mem.Allocator) ThreadPool {
        return ThreadPool{
            .list = std.ArrayList(ThreadEntry).init(allocator),
        };
    }

    /// Returns an index into a free thread
    pub fn getFreeThread(self: *ThreadPool) !usize {
        var free: ?usize = null;
        for (self.list.items, 0..) |entry, idx| {
            if (!entry.busy) {
                free = idx;
            }
        }

        if (free != null) {
            return free.?;
        } else {
            // TODO: create thread
            var thread = std.Thread.spawn(.{}, taskRunner, .{});
        }
    }

    /// The loop in charge of running tasks on each thread.
    fn taskRunner() void {
        while (true) {
            Futex.timedWait(num_tasks, 0, 100 * std.time.ns_per_ms) catch |err| switch (err) {
                error.Timeout => {},
            };
        }
    }
};

pub const Loop = struct {
    pool: ThreadPool,
    pending_tasks: TaskQueue,

    const Task = struct {
        frame: anyframe,
    };

    const TaskQueue = std.atomic.Queue(Task);

    pub fn init() Loop {
        return Loop{
            .pool = ThreadPool.init(internal.lasting_allocator),
            .pending_tasks = TaskQueue.init(),
        };
    }
};

pub var loop_instance: Loop = Loop.init();
const root = @import("root");
pub var loop = if (@hasDecl(root, "capy_loop"))
    &root.capy_loop
else
    &loop_instance;
