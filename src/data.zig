const std = @import("std");
const lasting_allocator = @import("internal.zig").lasting_allocator;

pub fn DataWrapper(comptime T: type) type {
    return struct {
        value: T,
        lock: std.Thread.Mutex = .{},
        onChange: std.ArrayList(ChangeListener),
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
        allocator: ?*std.mem.Allocator = null,

        const Self = @This();

        pub const ChangeListener = struct {
            function: fn(newValue: T, userdata: usize) void,
            userdata: usize = 0
        };

        pub fn of(value: T) Self {
            return Self {
                .value = value,
                .onChange = std.ArrayList(ChangeListener).init(lasting_allocator)
            };
        }

        pub fn addChangeListener(self: *Self, listener: ChangeListener) !usize {
            try self.onChange.append(listener);
            return self.onChange.items.len - 1; // index of the listener
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
            self.extendedSet(value, true);
        }

        /// Thread-safe set operation without calling change listeners
        /// This should only be used in widget implementations when calling
        /// change listeners would cause an infinite recursion.
        ///
        /// Example: A text field listens for data wrapper changes in order to
        /// change its text. When the user edits the text, it wants to
        /// change the data wrapper, but without setNoListen, it would
        /// cause an infinite recursion.
        pub fn setNoListen(self: *Self, value: T) void {
            self.extendedSet(value, false);
        }

        fn extendedSet(self: *Self, value: T, comptime callHandlers: bool) void {
            if (self.bindLock.tryAcquire()) |bindLock| {
                defer bindLock.release();

                const lock = self.lock.acquire();
                self.value = value;
                lock.release();
                if (callHandlers) {
                    for (self.onChange.items) |listener| {
                        listener.function(self.value, listener.userdata);
                    }
                }
                if (self.bindWrapper) |binding| {
                    binding.set(value);
                }
            } else {
                // Do nothing ...
            }
        }

        pub fn deinit(self: *Self) void {
            self.onChange.deinit();
            if (self.allocator) |allocator| {
                allocator.destroy(self);
            }
        }
    };
}

pub fn FormatDataWrapper(allocator: *std.mem.Allocator, comptime fmt: []const u8, childs: anytype) !*StringDataWrapper {
    const Self = struct {
        wrapper: StringDataWrapper,
        childs: @TypeOf(childs)
    };
    var self = try allocator.create(Self);
    const empty = try allocator.alloc(u8, 0); // alloc an empty string so it can be freed
    self.* = Self {
        .wrapper = StringDataWrapper.of(empty),
        .childs = childs
    };
    self.wrapper.allocator = allocator;

    const childTypes = comptime blk: {
        var types: []const type = &[_]type {};
        for (childs) |child| {
            const T = @TypeOf(child.value);
            types = types ++ &[_]type { T };
        }
        break :blk types;
    };
    const format = struct {
        fn format(ptr: *Self) void {
            const TupleType = std.meta.Tuple(childTypes);
            var tuple: TupleType = undefined;
            inline for (ptr.childs) |child, i| {
                tuple[i] = child.get();
            }

            var str = std.fmt.allocPrint(ptr.wrapper.allocator.?, fmt, tuple) catch unreachable;
            ptr.wrapper.allocator.?.free(ptr.wrapper.get());
            ptr.wrapper.set(str);
        }
    }.format;
    format(self);

    inline for (childs) |child| {
        const T = @TypeOf(child.value);
        _ = try child.addChangeListener(.{
            .userdata = @ptrToInt(self),
            .function = struct {
                fn callback(newValue: T, userdata: usize) void {
                    _ = newValue;
                    const ptr = @intToPtr(*Self, userdata);
                    format(ptr);
                }
            }.callback
        });
    }
    return &self.wrapper;
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
