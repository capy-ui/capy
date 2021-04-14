const std = @import("std");

// TODO: the answer is to use handles!! (even if it needs allocation underneath)
pub fn DataWrapper(comptime T: type) type {
    return struct {
        value: T,
        lock: std.Thread.Mutex = .{},
        onChangeFn: ?fn(newValue: T, userdata: usize) void = null,
        userdata: usize = 0,
        bind: ?*Self = null,

        const Self = @This();

        pub fn of(value: T) Self {
            return Self {
                .value = value
            };
        }

        pub fn bind(sender: *Self, receiver: *Self) void {
            sender.bind = receiver.bind;
        }

        /// Thread-safe get operation. If doing a read-modify-write operation
        /// manually changing the value and acquiring the lock is recommended.
        pub fn get(self: *Self) T {
            const lock = self.lock.acquire();
            defer lock.release();
            return self.value;
        }

        /// Thread-safe set operation. If doing a read-modify-write operation
        /// manually changing the value and acquiring the lock is recommended.
        pub fn set(self: *Self, value: T) void {
            const lock = self.lock.acquire();
            defer lock.release();
            self.value = value;
            if (self.onChangeFn) |func| {
                func(self.value, self.userdata);
            }
            if (self.bind) |binding| {
                binding.set(value);
            }
        }
    };
}

pub const StringDataWrapper = DataWrapper([]const u8);