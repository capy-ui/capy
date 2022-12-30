const std = @import("std");
const Container_Impl = @import("containers.zig").Container_Impl;
const internal = @import("internal.zig");
const lasting_allocator = internal.lasting_allocator;

/// Linear interpolation between floats a and b with factor t.
fn lerpFloat(a: anytype, b: @TypeOf(a), t: f64) @TypeOf(a) {
    return a * (1 - @floatCast(@TypeOf(a), t)) + b * @floatCast(@TypeOf(a), t);
}

/// Linear interpolation between any two values a and b with factor t.
/// Both values must be of the same type and support linear interpolation!
pub fn lerp(a: anytype, b: @TypeOf(a), t: f64) @TypeOf(a) {
    const T = @TypeOf(a);

    if (comptime std.meta.trait.isNumber(T)) {
        const a_casted = comptime blk: {
            if (std.meta.trait.isIntegral(T)) {
                break :blk @intToFloat(f64, a);
            } else {
                break :blk a;
            }
        };

        const b_casted = comptime blk: {
            if (std.meta.trait.isIntegral(T)) {
                break :blk @intToFloat(f64, b);
            } else {
                break :blk b;
            }
        };

        const result = lerpFloat(a_casted, b_casted, t);
        if (comptime std.meta.trait.isIntegral(T)) {
            return @floatToInt(T, @round(result));
        } else {
            return result;
        }
    } else if (comptime std.meta.trait.isContainer(T) and @hasDecl(T, "lerp")) {
        return T.lerp(a, b, t);
    } else if (comptime std.meta.trait.is(.Optional)(T)) {
        if (a != null and b != null) {
            return lerp(a.?, b.?, t);
        } else {
            return b;
        }
    } else {
        @compileError("type " ++ @typeName(T) ++ " does not support linear interpolation");
    }
}
const lerpInt = lerp;

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
        /// Assume animation won't last more than 4000000 seconds
        duration: u32,
        min: T,
        max: T,
        animFn: *const fn (t: f64) f64,

        /// Get the current value from the animation
        pub fn get(self: @This()) T {
            const maxDiff = @intToFloat(f64, self.duration);
            const diff = @intToFloat(f64, std.time.milliTimestamp() - self.start);
            var t = diff / maxDiff;
            // Clamp t to [0, 1]
            t = std.math.clamp(t, 0.0, 1.0);
            // Transform 't' using the animation function
            t = self.animFn(t);

            return lerp(self.min, self.max, t);
        }
    };
}

pub fn isDataWrapper(comptime T: type) bool {
    if (!comptime std.meta.trait.is(.Struct)(T))
        return false;
    return @hasDecl(T, "ValueType") and T == DataWrapper(T.ValueType);
}

pub var _animatedDataWrappers = std.ArrayList(struct {
    fnPtr: *const fn (data: *anyopaque) bool,
    userdata: *anyopaque,
}).init(lasting_allocator);

fn isAnimable(comptime T: type) bool {
    if (std.meta.trait.isNumber(T) or (std.meta.trait.isContainer(T) and @hasDecl(T, "lerp"))) {
        return true;
    } else if (std.meta.trait.is(.Optional)(T)) {
        return isAnimable(std.meta.Child(T));
    }
    return false;
}

pub fn DataWrapper(comptime T: type) type {
    return struct {
        value: if (IsAnimable) union(enum) { Single: T, Animated: Animation(T) } else T,
        // TODO: switch to a lock that allow concurrent reads but one concurrent write
        lock: std.Thread.Mutex = .{},
        /// List of every change listener listening to this data wrapper.
        /// A linked list is used for minimal stack overhead and to take
        /// advantage of the fact that most DataWrappers don't have a
        /// change listener.
        onChange: ChangeListenerList = .{},
        // TODO: multiple bindings and binders
        /// The object this wrapper is binded by
        binderWrapper: ?*Self = null,
        /// The object this wrapper is binded to
        bindWrapper: ?*Self = null,
        /// This boolean is used to protect from recursive relations between wrappers
        /// For example if there are two two-way binded data wrappers A and B:
        /// When A is set, B is set too. Since B is set, it will set A too. A is set, it will set B too, and so on..
        /// To prevent that, the bindLock is set to true when setting the value of the other.
        /// If the lock is equal to true, set() returns without calling the other. For example:
        /// When A is set, it sets the lock to true and sets B. Since B is set, it will set A too.
        /// A notices that bindLock is already set to true, and thus returns.
        bindLock: std.atomic.Atomic(bool) = std.atomic.Atomic(bool).init(false),

        /// If dependOn has been called, this is a pointer to the callback function
        depend_on_callback: ?*const anyopaque = null,
        /// If dependOn has been called, this is the list of data wrappers it depends on.
        depend_on_wrappers: []?*anyopaque = &.{},

        allocator: ?std.mem.Allocator = null,

        const Self = @This();
        const IsAnimable = isAnimable(T);

        pub const ValueType = T;
        pub const ChangeListener = struct { function: *const fn (newValue: T, userdata: usize) void, userdata: usize = 0 };
        const ChangeListenerList = std.SinglyLinkedList(ChangeListener);

        pub fn of(value: T) Self {
            if (IsAnimable) {
                return Self{ .value = .{ .Single = value } };
            } else {
                return Self{ .value = value };
            }
        }

        /// This function updates any current animation.
        /// It returns true if the animation isn't done, false otherwises.
        pub fn update(self: *Self) bool {
            switch (self.value) {
                .Animated => |animation| {
                    if (std.time.milliTimestamp() >= animation.start + animation.duration) {
                        self.value = .{ .Single = animation.max };
                        return false;
                    } else {
                        self.callHandlers();
                        return true;
                    }
                },
                .Single => return false,
            }
        }

        /// Returns true if there is currently an animation playing.
        pub fn hasAnimation(self: *Self) bool {
            if (!IsAnimable) return false;
            return self.update();
        }

        pub fn animate(self: *Self, anim: *const fn (f64) f64, target: T, duration: u64) void {
            if (!IsAnimable) {
                @compileError("animate() called on data that is not animable");
            }
            const time = std.time.milliTimestamp();
            const currentValue = self.get();
            self.value = .{ .Animated = Animation(T){
                .start = time,
                .duration = @intCast(u32, duration),
                .min = currentValue,
                .max = target,
                .animFn = anim,
            } };

            var contains = false;
            for (_animatedDataWrappers.items) |item| {
                if (@ptrCast(*anyopaque, self) == item.userdata) {
                    contains = true;
                    break;
                }
            }
            if (!contains) {
                _animatedDataWrappers.append(.{ .fnPtr = @ptrCast(*const fn (*anyopaque) bool, &Self.update), .userdata = self }) catch {};
            }
        }

        pub fn addChangeListener(self: *Self, listener: ChangeListener) !usize {
            const node = try lasting_allocator.create(ChangeListenerList.Node);
            node.* = .{ .data = listener };
            self.onChange.prepend(node);
            return self.onChange.len() - 1;
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
            return self.getUnsafe();
        }

        /// This gets the value of the data wrapper without accounting for
        /// multi-threading. Do not use it! If you have an app with only one thread,
        /// then use the single_threaded build flag, don't use this function.
        pub fn getUnsafe(self: Self) T {
            if (IsAnimable) {
                return switch (self.value) {
                    .Single => |value| value,
                    .Animated => |animation| animation.get(),
                };
            } else {
                return self.value;
            }
        }

        /// Thread-safe set operation. If doing a read-modify-write operation
        /// manually changing the value and acquiring the lock is recommended.
        /// This also removes any previously set animation!
        pub fn set(self: *Self, value: T) void {
            self.extendedSet(value, true);
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
            self.extendedSet(value, false);
        }

        fn extendedSet(self: *Self, value: T, comptime doCallHandlers: bool) void {
            // This atomically checks if bindLock is false, and sets it to true if it was.
            // bindLock.compareToSwap(false, true, .SeqCst, .SeqCst) is equivalent to
            // fn compareAndSwapButNotAtomic(ptr: *bool) ?bool {
            //     const old_value = ptr.*;
            //     if (old_value == false) {
            //         ptr.* = true;
            //         return null;
            //     } else {
            //         return old_value;
            //     }
            // }
            // As you can see, if the old value was false, it returns null, which is what we want.
            // Otherwise, it returns the old value, but since the only value other than false is true,
            // we're not interested in the result.
            if (self.bindLock.compareAndSwap(false, true, .SeqCst, .SeqCst) == null) {
                defer self.bindLock.store(false, .SeqCst);

                self.lock.lock();
                if (IsAnimable) {
                    self.value = .{ .Single = value };
                } else {
                    self.value = value;
                }
                self.lock.unlock();
                if (doCallHandlers) {
                    self.callHandlers();
                }
                if (self.bindWrapper) |binding| {
                    binding.set(value);
                }
            } else {
                // Do nothing ...
            }
        }

        /// This makes the value of this data wrapper entirely dependent
        /// on the given parameters, it can only be reverted by calling set()
        /// 'tuple' must be a tuple with pointers to data wrappers
        /// 'function' must be a function accepting as arguments the value types of the data wrappers and returning a new value.
        pub fn dependOn(self: *Self, tuple: anytype, function: anytype) !void {
            const FunctionType = @TypeOf(function);

            // Data Wrapper types
            // e.g. DataWrapper(u32), DataWrapper([]const u8)
            const DataWrapperTypes = comptime blk: {
                var types: [tuple.len]type = undefined;
                var i: usize = 0;
                while (i < tuple.len) : (i += 1) {
                    types[i] = internal.DereferencedType(@TypeOf(tuple[i]));
                }
                break :blk types;
            };

            // Value types
            // e.g. u32, []const u8
            const ValueTypes = comptime blk: {
                var types: [tuple.len]type = undefined;
                var i: usize = 0;
                while (i < tuple.len) : (i += 1) {
                    types[i] = DataWrapperTypes[i].ValueType;
                }
                break :blk types;
            };

            const handler = struct {
                fn handler(data_wrapper: *Self, fn_ptr: ?*const anyopaque, wrappers: []?*anyopaque) void {
                    const callback = @ptrCast(FunctionType, fn_ptr);
                    const ArgsTuple = std.meta.Tuple(&ValueTypes);

                    var args: ArgsTuple = undefined;
                    comptime var i: usize = 0;
                    inline while (i < DataWrapperTypes.len) : (i += 1) {
                        const wrapper_ptr = wrappers[i];
                        const DataWrapperType = DataWrapperTypes[i];
                        const wrapper = @ptrCast(*DataWrapperType, @alignCast(@alignOf(DataWrapperType), wrapper_ptr));
                        const value = wrapper.get();
                        args[i] = value;
                    }

                    const result = @call(.auto, callback, args);
                    data_wrapper.set(result);
                }
            }.handler;

            // List of DataWrappers, casted to ?*anyopaque
            const wrappers = try lasting_allocator.alloc(?*anyopaque, tuple.len);
            {
                comptime var i: usize = 0;
                inline while (i < tuple.len) : (i += 1) {
                    const wrapper = tuple[i];
                    wrappers[i] = wrapper;
                }
            }

            // Call the handler once for initialization
            const fn_ptr = @as(?*const anyopaque, function);
            handler(self, fn_ptr, wrappers);

            {
                comptime var i: usize = 0;
                inline while (i < tuple.len) : (i += 1) {
                    const wrapper = tuple[i];
                    const WrapperValueType = ValueTypes[i];
                    const changeListener = struct {
                        fn changeListener(_: WrapperValueType, userdata: usize) void {
                            const self_ptr = @intToPtr(*Self, userdata);
                            handler(self_ptr, self_ptr.depend_on_callback.?, self_ptr.depend_on_wrappers);
                        }
                    }.changeListener;
                    _ = try wrapper.addChangeListener(.{ .function = changeListener, .userdata = @ptrToInt(self) });
                }
            }

            self.depend_on_callback = fn_ptr;
            self.depend_on_wrappers = wrappers;
        }

        fn callHandlers(self: *Self) void {
            // Iterate over each node of the linked list
            var nullableNode = self.onChange.first;
            const value = self.get();
            while (nullableNode) |node| {
                node.data.function(value, node.data.userdata);
                nullableNode = node.next;
            }
        }

        pub fn deinit(self: *Self) void {
            var nullableNode = self.onChange.first;
            while (nullableNode) |node| {
                nullableNode = node.next;
                lasting_allocator.destroy(node);
            }
            if (self.allocator) |allocator| {
                allocator.destroy(self);
            }
        }
    };
}

// TODO: reimplement using DataWrapper.dependOn
pub fn FormatDataWrapper(allocator: std.mem.Allocator, comptime fmt: []const u8, childs: anytype) !*StringDataWrapper {
    const Self = struct { wrapper: StringDataWrapper, childs: @TypeOf(childs) };
    var self = try allocator.create(Self);
    const empty = try allocator.alloc(u8, 0); // alloc an empty string so it can be freed
    self.* = Self{ .wrapper = StringDataWrapper.of(empty), .childs = childs };
    self.wrapper.allocator = allocator;

    const childTypes = comptime blk: {
        var types: []const type = &[_]type{};
        // Iterate over the 'childs' tuple for each data wrapper
        for (std.meta.fields(@TypeOf(childs))) |field| {
            const T = @import("internal.zig").DereferencedType(
                @TypeOf(@field(childs, field.name)),
            );
            types = types ++ &[_]type{T.ValueType};
        }
        break :blk types;
    };
    const format = struct {
        fn format(ptr: *Self) void {
            const TupleType = std.meta.Tuple(childTypes);
            var tuple: TupleType = undefined;
            inline for (std.meta.fields(@TypeOf(ptr.childs))) |childF, i| {
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
        const T = @TypeOf(child.*).ValueType;
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

/// A position expressed in display pixels.
pub const Position = struct {
    x: i32,
    y: i32,

    /// Shorthand for struct initialization
    pub fn init(x: i32, y: i32) Position {
        return Position{ .x = x, .y = y };
    }

    pub fn lerp(a: Position, b: Position, t: f64) Position {
        return Position{
            .x = lerpInt(a.x, b.x, t),
            .y = lerpInt(a.y, b.y, t),
        };
    }
};

/// A size expressed in display pixels.
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
        return Size{
            .width = std.math.max(a.width, b.width),
            .height = std.math.max(a.height, b.height),
        };
    }

    /// Intersect two sizes by taking the lowest width and the lowest height
    pub fn intersect(a: Size, b: Size) Size {
        return Size{
            .width = std.math.min(a.width, b.width),
            .height = std.math.min(a.height, b.height),
        };
    }

    pub fn lerp(a: Size, b: Size, t: f64) Size {
        return Size{
            .width = lerpInt(a.width, b.width, t),
            .height = lerpInt(a.height, b.height, t),
        };
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

    test "Size.lerp" {
        const a = Size.init(100, 200);
        const b = Size.init(200, 600);
        const expected = Size.init(150, 400);
        const got = Size.lerp(a, b, 0.5);

        try std.testing.expectEqual(expected.width, got.width);
        try std.testing.expectEqual(expected.height, got.height);
    }
};

pub const Rectangle = struct {
    origin: Position,
    size: Size,

    pub fn init(ox: i32, oy: i32, owidth: u32, oheight: u32) Rectangle {
        return Rectangle{
            .origin = .{ .x = ox, .y = oy },
            .size = .{ .width = owidth, .height = oheight },
        };
    }

    pub fn lerp(a: Rectangle, b: Rectangle, t: f64) Rectangle {
        return Rectangle{
            .origin = Position.lerp(a.origin, b.origin, t),
            .size = Size.lerp(a.size, b.size, t),
        };
    }

    pub fn x(self: Rectangle) i32 {
        return self.origin.x;
    }

    pub fn y(self: Rectangle) i32 {
        return self.origin.y;
    }

    pub fn width(self: Rectangle) u32 {
        return self.size.width;
    }

    pub fn height(self: Rectangle) u32 {
        return self.size.height;
    }
};

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
    try std.testing.expect(testData.hasAnimation() == false);
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
