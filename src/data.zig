const std = @import("std");

pub fn DataWrapper(comptime T: type) type {
    return struct {
        value: T,
        lock: std.Thread.Mutex = .{},
        // TODO: multiple on change functions
        onChangeFn: ?fn(newValue: T, userdata: usize) void = null,
        userdata: usize = 0,
        // TODO: multiple bindings and binders
        /// The object this wrapper is binded by
        binderWrapper: ?*Self = null,
        /// The object this wrapper is binded to
        bindWrapper: ?*Self = null,
        /// This lock is used to protect from recursive relations between wrappers
        /// For example if there are two two-way binded data wrappers A and B:
        /// When A is set, B is set too. Since B is set, it will set A too. A is set, it will set B too, and so on..
        /// To prevent that, the bindLock is acquired when setting the value of the other.
        /// If the lock has already been acquired, set() returns without calling the other. For example:
        /// When A is set, it acquires its lock and sets B. Since B is set, it will set A too.
        /// A notices it already acquired the binding lock, and thus returns.
        bindLock: std.Thread.Mutex = .{},

        const Self = @This();

        pub fn of(value: T) Self {
            return Self {
                .value = value
            };
        }

        /// All writes to sender will also change the value of receiver
        pub fn bindOneWay(sender: *Self, receiver: *Self) void {
            sender.bindWrapper = receiver;
            receiver.binderWrapper = sender;
        }

        /// All writes to one change the value of the other
        pub fn bind(self: *Self, other: *Self) void {
            self.bindOneWay(other);
            other.bindOneWay(self);
        }

        /// Updates binder's pointers so they point to this object.
        pub fn updateBinders(self: *Self) void {
            if (self.binderWrapper) |binder| {
                binder.bindWrapper = self;
            }
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
            if (self.bindLock.tryAcquire()) |bindLock| {
                defer bindLock.release();

                const lock = self.lock.acquire();
                defer lock.release();
                self.value = value;
                if (self.onChangeFn) |func| {
                    func(self.value, self.userdata);
                }
                if (self.bindWrapper) |binding| {
                    binding.set(value);
                }
            } else {
                // Do nothing ...
            }
        }
    };
}

pub const StringDataWrapper = DataWrapper([]const u8);

/// The size expressed in display pixels.
pub const Size = struct {
    width: u32,
    height: u32,

    pub fn init(width: u32, height: u32) Size {
        return Size { .width = width, .height = height };
    }

    /// Returns the size with the least area
    pub fn min(a: Size, b: Size) Size {
        if (a.width * a.height < b.width * b.height) {
            return a;
        } else {
            return b;
        }
    }

    /// Returns the size with the most area
    pub fn max(a: Size, b: Size) Size {
        if (a.width * a.height > b.width * b.height) {
            return a;
        } else {
            return b;
        }
    }

    pub fn combine(a: Size, b: Size) Size {
        return Size {
            .width = std.math.max(a.width, b.width),
            .height = std.math.max(a.height, b.height)
        };
    }

    pub fn intersect(a: Size, b: Size) Size {
        return Size {
            .width = std.math.min(a.width, b.width),
            .height = std.math.min(a.height, b.height)
        };
    }
};

pub const Rectangle = struct {
    left: u32,
    top: u32,
    right: u32,
    bottom: u32
};
