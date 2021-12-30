const std = @import("std");
const Container_Impl = @import("containers.zig").Container_Impl;
const lasting_allocator = @import("internal.zig").lasting_allocator;
const milliTimestamp = @import("internal.zig").milliTimestamp;

fn lerp(a: anytype, b: @TypeOf(a), t: f64) @TypeOf(a) {
    return a * (1 - @floatCast(@TypeOf(a), t)) + b * @floatCast(@TypeOf(a), t);
}

pub const Easings = struct {
    pub fn Linear(t: f64) f64 {
        return t;
    }

    pub fn In(t: f64) f64 {
        return t * t;
    }

    pub fn Out(t: f64) f64 {
        return 1 - (1 - t) * (1 - t);
    }

    pub fn InOut(t: f64) f64 {
        return lerp(In(t), Out(t), t);
    }
};

pub fn Animation(comptime T: type) type {
    return struct {
        start: i64,
        end: i64,
        min: T,
        max: T,
        animFn: fn (t: f64) f64,

        /// Get the current value from the animation
        pub fn get(self: *@This()) T {
            const maxDiff = @intToFloat(f64, self.end - self.start);
            const diff = @intToFloat(f64, milliTimestamp() - self.start);
            var t = diff / maxDiff;

            // Clamp t to [0, 1]
            if (t > 1.0) t = 1.0;
            if (t < 0.0) t = 0.0;
            t = self.animFn(t); // transform 't' using the animation function

            const min = comptime blk: {
                if (std.meta.trait.isIntegral(T)) {
                    break :blk @intToFloat(f64, self.min);
                } else {
                    break :blk self.min;
                }
            };

            const max = comptime blk: {
                if (std.meta.trait.isIntegral(T)) {
                    break :blk @intToFloat(f64, self.max);
                } else {
                    break :blk self.max;
                }
            };

            // Do a linear interpolation
            const result = lerp(min, max, t);
            if (comptime std.meta.trait.isIntegral(T)) {
                return @floatToInt(T, @round(result));
            } else {
                return result;
            }
        }
    };
}

const Updater = struct {
    /// Pointer to some function
    fnPtr: usize,
    // TODO: list of data wrappers that it called
};

// Atomic stack with list of current 'updater' that are being proned
// this would allow for it to work with external data wrappers, and in fact with all data wrappers
// with minimal change
const UpdaterQueue = std.atomic.Queue(Updater);
var pronedUpdaterQueue = UpdaterQueue.init();

/// This is used for tracking whether a data wrapper's value has been accessed or not.
/// This is mostly used for the 'updater' pattern to automatically detect on
/// which properties an updater depends.
pub fn proneUpdater(updater: anytype, root: *Container_Impl) !void {
    var node = try lasting_allocator.create(UpdaterQueue.Node);
    defer lasting_allocator.destroy(node);
    node.data = .{ .fnPtr = @ptrToInt(updater) };

    pronedUpdaterQueue.put(node);
    defer _ = pronedUpdaterQueue.remove(node);

    _ = updater(root);
}

pub fn isDataWrapper(comptime T: type) bool {
    if (!comptime std.meta.trait.is(.Struct)(T))
        return false;
    return @hasField(T, "bindLock"); // TODO: check all properties using comptime
}

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
        allocator: ?std.mem.Allocator = null,
        animation: if (IsNumber) ?Animation(T) else void = if (IsNumber) null else {},
        updater: ?fn (*Container_Impl) T = null,

        const Self = @This();
        const IsNumber = std.meta.trait.isNumber(T);

        pub const ChangeListener = struct { function: fn (newValue: T, userdata: usize) void, userdata: usize = 0 };

        pub fn of(value: T) Self {
            return Self{ .value = value, .onChange = std.ArrayList(ChangeListener).init(lasting_allocator) };
        }

        /// This function updates any current animation.
        /// It returns true if the animation isn't done, false otherwises.
        pub fn update(self: *Self) bool {
            if (self.animation) |*anim| {
                self.extendedSet(anim.get(), true, false);
                if (milliTimestamp() >= anim.end) {
                    self.animation = null;
                    return false;
                } else {
                    return true;
                }
            } else {
                return false;
            }
        }

        /// Returns true if there is currently an animation playing.
        pub fn hasAnimation(self: *Self) bool {
            return self.animation != null;
        }

        pub fn animate(self: *Self, anim: fn (f64) f64, target: T, duration: i64) void {
            if (!IsNumber) {
                @compileError("animate only supported on numbers");
            }

            const time = milliTimestamp();
            self.animation = Animation(T){ .start = time, .end = time + duration, .min = self.value, .max = target, .animFn = anim };
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
            self.lock.lock();
            defer self.lock.unlock();
            return self.value;
        }

        /// Thread-safe set operation. If doing a read-modify-write operation
        /// manually changing the value and acquiring the lock is recommended.
        /// This also removes any previously set animation!
        pub fn set(self: *Self, value: T) void {
            self.extendedSet(value, true, true);
        }

        /// Thread-safe set operation without calling change listeners
        /// This should only be used in widget implementations when calling
        /// change listeners would cause an infinite recursion.
        /// This also removes any previously set animation!
        ///
        /// Example: A text field listens for data wrapper changes in order to
        /// change its text. When the user edits the text, it wants to
        /// change the data wrapper, but without setNoListen, it would
        /// cause an infinite recursion.
        pub fn setNoListen(self: *Self, value: T) void {
            self.extendedSet(value, false, true);
        }

        fn extendedSet(self: *Self, value: T, comptime callHandlers: bool, comptime resetAnimation: bool) void {
            if (self.bindLock.tryLock()) {
                defer self.bindLock.unlock();

                self.lock.lock();
                self.value = value;
                if (IsNumber and resetAnimation) {
                    self.animation = null;
                }
                self.lock.unlock();
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

pub fn FormatDataWrapper(allocator: std.mem.Allocator, comptime fmt: []const u8, childs: anytype) !*StringDataWrapper {
    const Self = struct { wrapper: StringDataWrapper, childs: @TypeOf(childs) };
    var self = try allocator.create(Self);
    const empty = try allocator.alloc(u8, 0); // alloc an empty string so it can be freed
    self.* = Self{ .wrapper = StringDataWrapper.of(empty), .childs = childs };
    self.wrapper.allocator = allocator;

    const childTypes = comptime blk: {
        var types: []const type = &[_]type{};
        for (std.meta.fields(@TypeOf(childs))) |field| {
            const T = @TypeOf(@field(childs, field.name).value);
            types = types ++ &[_]type{ T };
        }
        break :blk types;
    };
    const format = struct {
        fn format(ptr: *Self) void {
            const TupleType = std.meta.Tuple(childTypes);
            var tuple: TupleType = undefined;
            inline for (std.meta.fields(@TypeOf(ptr.childs))) |childF,i| {
                const child = @field(ptr.childs, childF.name);
                tuple[i] = child.get();
            }

            var str = std.fmt.allocPrint(ptr.wrapper.allocator.?, fmt, tuple) catch unreachable;
            ptr.wrapper.allocator.?.free(ptr.wrapper.get());
            ptr.wrapper.set(str);
        }
    }.format;
    format(self);
    
    const childFs = std.meta.fields(@TypeOf(childs));
    comptime var i = 0;
    inline while (i < childFs.len) : (i += 1) {
        const childF = childFs[i];
        const child = @field(childs, childF.name);
        const T = @TypeOf(child.value);
        _ = try child.addChangeListener(.{ .userdata = @ptrToInt(self), .function = struct {
            fn callback(newValue: T, userdata: usize) void {
                _ = newValue;
                const ptr = @intToPtr(*Self, userdata);
                format(ptr);
            }
        }.callback });
    }
    return &self.wrapper;
}

pub const StringDataWrapper = DataWrapper([]const u8);

pub const FloatDataWrapper = DataWrapper(f32);
pub const DoubleDataWrapper = DataWrapper(f64);

/// The size expressed in display pixels.
pub const Size = struct {
    width: u32,
    height: u32,

    /// Shorthand for struct initialization
    pub fn init(width: u32, height: u32) Size {
        return Size{ .width = width, .height = height };
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

    /// Combine two sizes by taking the largest width and the largest height
    pub fn combine(a: Size, b: Size) Size {
        return Size{ .width = std.math.max(a.width, b.width), .height = std.math.max(a.height, b.height) };
    }

    /// Intersect two sizes by taking the lowest width and the lowest height
    pub fn intersect(a: Size, b: Size) Size {
        return Size{ .width = std.math.min(a.width, b.width), .height = std.math.min(a.height, b.height) };
    }

    test "Size.max" {
        const a = Size.init(200, 10);
        const b = Size.init(2001, 1);
        try std.testing.expectEqual(b, Size.max(a, b));
        try std.testing.expectEqual(b, Size.max(b, a));
    }

    test "Size.min" {
        const a = Size.init(200, 10);
        const b = Size.init(2001, 1);
        try std.testing.expectEqual(a, Size.min(a, b));
        try std.testing.expectEqual(a, Size.min(b, a));
    }

    test "Size.combine" {
        const a = Size.init(202, 12);
        const b = Size.init(14, 153);
        const expected = Size.init(202, 153);

        try std.testing.expectEqual(expected, Size.combine(a, b));
        try std.testing.expectEqual(expected, Size.combine(b, a));
    }

    test "Size.intersect" {
        const a = Size.init(202, 12);
        const b = Size.init(14, 153);
        const expected = Size.init(14, 12);

        try std.testing.expectEqual(expected, Size.intersect(a, b));
        try std.testing.expectEqual(expected, Size.intersect(b, a));
    }
};

pub const Rectangle = struct { left: u32, top: u32, right: u32, bottom: u32 };

const expectEqual = std.testing.expectEqual;

test "lerp" {
    const floatTypes = .{ f16, f32, f64, f128 };

    inline for (floatTypes) |Float| {
        try expectEqual(@as(Float, 0.0), lerp(@as(Float, 0), 1.0, 0.0)); // 0 |-0.0 > 1.0 = 0.0
        try expectEqual(@as(Float, 0.1), lerp(@as(Float, 0), 0.2, 0.5)); // 0 |-0.5 > 0.2 = 0.1
        try expectEqual(@as(Float, 0.5), lerp(@as(Float, 0), 1.0, 0.5)); // 0 |-0.5 > 1.0 = 0.5
        try expectEqual(@as(Float, 1.0), lerp(@as(Float, 0), 1.0, 1.0)); // 0 |-1.0 > 1.0 = 1.0
    }
}

test "data wrappers" {
    var testData = DataWrapper(i32).of(0);
    testData.set(5);
    try expectEqual(@as(i32, 5), testData.get());
}

test "data wrapper change listeners" {
    // TODO
}

test "format data wrapper" {
    // FormatDataWrapper should be used with an arena allocator
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    // NOT PASSING DUE TO stage1 COMPILER BUGS
    // var dataSource1 = DataWrapper(i32).of(5);
    // defer dataSource1.deinit();
    // var dataSource2 = DataWrapper(f32).of(1.23);
    // defer dataSource2.deinit();
    // 
    // var format = try FormatDataWrapper(allocator, "{} and {d}", .{ &dataSource1, &dataSource2 });
    // defer format.deinit();
    // 
    // try std.testing.expectEqualStrings("5 and 1.23", format.get());
    // dataSource1.set(10);
    // try std.testing.expectEqualStrings("10 and 1.23", format.get());
    // dataSource2.set(1456.89);
    // try std.testing.expectEqualStrings("10 and 1456.89", format.get());

    var dataSource3 = DataWrapper(i32).of(5);
    defer dataSource3.deinit();
    var dataSource4 = DataWrapper(i32).of(1);
    defer dataSource4.deinit();

    var format2 = try FormatDataWrapper(allocator, "{} and {}", .{ &dataSource3, &dataSource4 });
    defer format2.deinit();
    try std.testing.expectEqualStrings("5 and 1", format2.get());
    dataSource3.set(10);
    try std.testing.expectEqualStrings("10 and 1", format2.get());
    dataSource4.set(42);
    try std.testing.expectEqualStrings("10 and 42", format2.get());
}
