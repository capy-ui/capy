const std = @import("std");
const Container_Impl = @import("containers.zig").Container_Impl;
const internal = @import("internal.zig");
const lasting_allocator = internal.lasting_allocator;
const trait = @import("trait.zig");

/// Linear interpolation between floats a and b with factor t.
fn lerpFloat(a: anytype, b: @TypeOf(a), t: f64) @TypeOf(a) {
    return a * (1 - @as(@TypeOf(a), @floatCast(t))) + b * @as(@TypeOf(a), @floatCast(t));
}

/// Linear interpolation between any two values a and b with factor t.
/// Both values must be of the same type and support linear interpolation!
pub fn lerp(a: anytype, b: @TypeOf(a), t: f64) @TypeOf(a) {
    const T = @TypeOf(a);

    if (comptime trait.isNumber(T)) {
        const a_casted = blk: {
            if (comptime trait.isIntegral(T)) {
                break :blk @as(f64, @floatFromInt(a));
            } else {
                break :blk a;
            }
        };

        const b_casted = blk: {
            if (comptime trait.isIntegral(T)) {
                break :blk @as(f64, @floatFromInt(b));
            } else {
                break :blk b;
            }
        };

        const result = lerpFloat(a_casted, b_casted, t);
        if (comptime trait.isIntegral(T)) {
            return @intFromFloat(@round(result));
        } else {
            return result;
        }
    } else if (comptime trait.isContainer(T) and @hasDecl(T, "lerp")) {
        return T.lerp(a, b, t);
    } else if (comptime trait.is(.Optional)(T)) {
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

pub const Easing = *const fn (t: f64) f64;
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
            const maxDiff = @as(f64, @floatFromInt(self.duration));
            const diff = @as(f64, @floatFromInt(std.time.milliTimestamp() - self.start));
            var t = diff / maxDiff;
            // Clamp t to [0, 1]
            t = std.math.clamp(t, 0.0, 1.0);
            // Transform 't' using the animation function
            t = self.animFn(t);

            return lerp(self.min, self.max, t);
        }
    };
}

pub fn isAtom(comptime T: type) bool {
    if (!comptime trait.is(.Struct)(T))
        return false;
    return @hasDecl(T, "ValueType") and T == Atom(T.ValueType);
}

pub var _animatedAtoms = std.ArrayList(struct {
    fnPtr: *const fn (data: *anyopaque) bool,
    userdata: *anyopaque,
}).init(lasting_allocator);
pub var _animatedAtomsLength = Atom(usize).of(0);
pub var _animatedAtomsMutex = std.Thread.Mutex{};

fn isAnimableType(comptime T: type) bool {
    if (trait.isNumber(T) or (trait.isContainer(T) and @hasDecl(T, "lerp"))) {
        return true;
    } else if (trait.is(.Optional)(T)) {
        return isAnimableType(std.meta.Child(T));
    }
    return false;
}

pub fn Atom(comptime T: type) type {
    return struct {
        value: if (isAnimable) union(enum) { Single: T, Animated: Animation(T) } else T,
        // TODO: switch to a lock that allow concurrent reads but one concurrent write
        lock: std.Thread.Mutex = .{},
        /// List of every change listener listening to this atom.
        /// A linked list is used for minimal stack overhead and to take
        /// advantage of the fact that most Atoms don't have a
        /// change listener.
        onChange: ChangeListenerList = .{},
        /// List of all Atoms this one is bound to.
        bindings: BindingList = .{},

        /// This boolean is used to protect from recursive relations between wrappers
        /// For example if there are two two-way binded atoms A and B:
        /// When A is set, B is set too. Since B is set, it will set A too. A is set, it will set B too, and so on..
        /// To prevent that, the bindLock is set to true when setting the value of the other.
        /// If the lock is equal to true, set() returns without calling the other. For example:
        /// When A is set, it sets the lock to true and sets B. Since B is set, it will set A too.
        /// A notices that bindLock is already set to true, and thus returns.
        /// TODO: make the bind lock more general and just use it for any change, and explicit how this favors completeness instead of consistency (in case an onChange triggers set method manually)
        bindLock: atomicValue(bool) = atomicValue(bool).init(false),

        /// If dependOn has been called, this is a pointer to the callback function
        depend_on_callback: ?*const anyopaque = null,
        /// If dependOn has been called, this is the list of atoms it depends on.
        depend_on_wrappers: []?*anyopaque = &.{},

        allocator: ?std.mem.Allocator = null,

        const Self = @This();
        const isAnimable = isAnimableType(T);
        const atomicValue = if (@hasDecl(std.atomic, "Value")) std.atomic.Value else std.atomic.Atomic; // support zig 0.11 as well as current master

        pub const ValueType = T;
        pub const ChangeListener = struct {
            function: *const fn (newValue: T, userdata: usize) void,
            userdata: usize = 0,
            type: enum { Change, Destroy } = .Change,
        };
        pub const Binding = struct {
            bound_to: *Self,
            link_id: u16,
        };

        const ChangeListenerList = std.SinglyLinkedList(ChangeListener);
        const BindingList = std.SinglyLinkedList(Binding);

        pub fn of(value: T) Self {
            if (isAnimable) {
                return Self{ .value = .{ .Single = value } };
            } else {
                return Self{ .value = value };
            }
        }

        /// Allocates a new atom and initializes it with the given value.
        /// This function assumes that there will be no memory errors.
        /// If you want to handle OutOfMemory, you must manually allocate the Atom
        pub fn alloc(value: T) *Self {
            const ptr = lasting_allocator.create(Self) catch |err| switch (err) {
                error.OutOfMemory => unreachable,
            };
            ptr.* = Self.of(value);
            ptr.allocator = lasting_allocator;
            return ptr;
        }

        /// Shorthand for Atom.of(undefined).dependOn(...)
        pub fn derived(tuple: anytype, function: anytype) !*Self {
            var wrapper = Self.alloc(undefined);
            try wrapper.dependOn(tuple, function);
            return wrapper;
        }

        /// Allocates a new atom and make it follow the value of the original atom, but
        /// with an animation.
        /// Note that the animated atom is automatically destroyed when the original atom is destroyed.
        pub fn animated(original: *Self, easing: Easing, duration: u64) !*Self {
            var self = Self.alloc(original.get());

            const AnimationParameters = struct {
                easing: Easing,
                duration: u64,
                self_ptr: *Self,
                is_deinit: bool = false,
            };

            const userdata = try self.allocator.?.create(AnimationParameters);
            userdata.* = .{ .easing = easing, .duration = duration, .self_ptr = self };

            const animate_fn = struct {
                fn a(new_value: T, int: usize) void {
                    const ptr = @as(*AnimationParameters, @ptrFromInt(int));
                    ptr.self_ptr.animate(ptr.easing, new_value, ptr.duration);
                }
            }.a;

            const destroy_fn = struct {
                fn a(_: T, int: usize) void {
                    const ptr = @as(*AnimationParameters, @ptrFromInt(int));
                    const allocator = lasting_allocator;
                    const is_deinit = ptr.is_deinit;
                    const self_ptr = ptr.self_ptr;
                    allocator.destroy(ptr);

                    if (!is_deinit) self_ptr.deinit();
                }
            }.a;

            const self_destroy_fn = struct {
                fn a(_: T, int: usize) void {
                    const ptr = @as(*AnimationParameters, @ptrFromInt(int));
                    ptr.is_deinit = true;
                }
            }.a;

            _ = try original.addChangeListener(.{
                .function = animate_fn,
                .userdata = @intFromPtr(userdata),
                .type = .Change,
            });
            _ = try original.addChangeListener(.{
                .function = destroy_fn,
                .userdata = @intFromPtr(userdata),
                .type = .Destroy,
            });
            _ = try self.addChangeListener(.{
                .function = self_destroy_fn,
                .userdata = @intFromPtr(userdata),
                .type = .Destroy,
            });
            return self;
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
            if (!isAnimable) return false;
            return self.update();
        }

        pub fn animate(self: *Self, anim: *const fn (f64) f64, target: T, duration: u64) void {
            if (!isAnimable) {
                @compileError("animate() called on data that is not animable");
            }
            const time = std.time.milliTimestamp();
            const currentValue = self.get();
            self.value = .{ .Animated = Animation(T){
                .start = time,
                .duration = @as(u32, @intCast(duration)),
                .min = currentValue,
                .max = target,
                .animFn = anim,
            } };

            var contains = false;
            _animatedAtomsMutex.lock();
            defer _animatedAtomsMutex.unlock();

            for (_animatedAtoms.items) |item| {
                if (@as(*anyopaque, @ptrCast(self)) == item.userdata) {
                    contains = true;
                    break;
                }
            }
            if (!contains) {
                _animatedAtoms.append(.{ .fnPtr = @as(*const fn (*anyopaque) bool, @ptrCast(&Self.update)), .userdata = self }) catch {};
                _animatedAtomsLength.set(_animatedAtoms.items.len);
            }
        }

        pub fn addChangeListener(self: *Self, listener: ChangeListener) !usize {
            const node = try lasting_allocator.create(ChangeListenerList.Node);
            node.* = .{ .data = listener };
            self.onChange.prepend(node);
            return self.onChange.len() - 1;
        }

        fn getNextBindId(self: *Self, other: *Self) u16 {
            var link_id: u16 = 0;

            var nullableNode = self.bindings.first;
            while (nullableNode) |node| {
                // if the link id is already used
                if (node.data.link_id == link_id) {
                    link_id += 1;
                }

                var nullableNode2 = other.bindings.first;
                while (nullableNode2) |node2| {
                    // if the link id is already used
                    if (node2.data.link_id == link_id) {
                        link_id += 1;
                    }
                    nullableNode2 = node2.next;
                }
                nullableNode = node.next;
            }

            nullableNode = other.bindings.first;
            while (nullableNode) |node| {
                // if the link id is already used
                if (node.data.link_id == link_id) {
                    link_id += 1;
                }
                nullableNode = node.next;
            }

            return link_id;
        }

        /// All writes to one change the value of the other
        pub fn bind(self: *Self, other: *Self) void {
            const link_id = self.getNextBindId(other);

            const node = lasting_allocator.create(BindingList.Node) catch unreachable;
            node.* = .{ .data = .{ .bound_to = other, .link_id = link_id } };
            self.bindings.prepend(node);

            const otherNode = lasting_allocator.create(BindingList.Node) catch unreachable;
            otherNode.* = .{ .data = .{ .bound_to = self, .link_id = link_id } };
            other.bindings.prepend(otherNode);
        }

        /// Updates binder's pointers so they point to this object.
        pub fn updateBinders(self: *Self) void {
            var nullableNode = self.bindings.first;
            while (nullableNode) |node| {
                const bound_to = node.data.bound_to;
                const link_id = node.data.link_id;
                std.debug.assert(bound_to != self);

                var otherNode = bound_to.bindings.first;
                while (otherNode) |node2| {
                    if (node2.data.link_id == link_id) {
                        node2.data.bound_to = self;
                    }
                    otherNode = node2.next;
                }
                nullableNode = node.next;
            }
        }

        /// Thread-safe get operation. If doing a read-modify-write operation
        /// you must use the rmw() method.
        pub fn get(self: *Self) T {
            self.lock.lock();
            defer self.lock.unlock();
            return self.getUnsafe();
        }

        /// This gets the value of the atom without accounting for
        /// multi-threading. Do not use it! If you have an app with only one thread,
        /// then use the single_threaded build flag, don't use this function.
        pub fn getUnsafe(self: Self) T {
            if (isAnimable) {
                return switch (self.value) {
                    .Single => |value| value,
                    .Animated => |animation| animation.get(),
                };
            } else {
                return self.value;
            }
        }

        /// Thread-safe set operation. If doing a read-modify-write operation
        /// you must use the rmw() method.
        /// This also removes any previously set animation!
        pub fn set(self: *Self, value: T) void {
            self.extendedSet(value, .{});
        }

        const ExtendedSetOptions = struct {
            /// If true, lock before setting the value and unlock after.
            /// If false, do not lock before setting the value, but still unlock after.
            locking: bool = true,
        };

        fn extendedSet(self: *Self, value: T, comptime options: ExtendedSetOptions) void {
            // This atomically checks if bindLock is false, and sets it to true if it was.
            // If the old value was false, it returns null, which is what we want.
            // Otherwise, it returns the old value, but since the only value other than false is true,
            // we're not interested in the result.
            if ((if (@hasDecl(atomicValue(bool), "cmpxchgStrong")) self.bindLock.cmpxchgStrong(false, true, .SeqCst, .SeqCst) else self.bindLock.cmpxchg(true, false, true, .SeqCst, .SeqCst) // support zig 0.11 as well as current master
            ) == null) {
                defer self.bindLock.store(false, .SeqCst);

                {
                    if (options.locking) self.lock.lock();
                    defer self.lock.unlock();

                    if (isAnimable) {
                        self.value = .{ .Single = value };
                    } else {
                        self.value = value;
                    }
                }

                self.callHandlers();

                // Update bound atoms
                var nullableNode = self.bindings.first;
                while (nullableNode) |node| {
                    node.data.bound_to.set(value);
                    nullableNode = node.next;
                }
            } else {
                // Do nothing ...
            }
        }

        /// Read-Modify-Write the value all in one step.
        /// If you want to RMW you must use this function in order to avoid concurrency issues.
        pub fn rmw(self: *Self, func: *const fn (value: T) T) void {
            self.lock.lock();
            // Don't unlock because extendedSet() will already unlocks it

            const current_value = self.getUnsafe();
            self.extendedSet(func(current_value), .{ .locking = false });
        }

        // TODO: constrain "function"'s type based on tuple
        // TODO: optionally provide the function with an arena allocator which will automatically
        // handle freeing and lifetime so it's less of a pain in the

        /// This makes the value of this atom entirely dependent
        /// on the given parameters (variable-based reactivity), it can only be reverted by calling set()
        /// 'tuple' must be a tuple with pointers to atoms
        /// 'function' must be a function accepting as arguments the value types of the atoms and returning a new value.
        /// This function relies on the atom not moving in memory and the self pointer still pointing at the same atom
        pub fn dependOn(self: *Self, tuple: anytype, function: anytype) !void {
            const FunctionType = @TypeOf(function);

            // Atom types
            // e.g. Atom(u32), Atom([]const u8)
            const AtomTypes = comptime blk: {
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
                    types[i] = AtomTypes[i].ValueType;
                }
                break :blk types;
            };

            const handler = struct {
                fn handler(data_wrapper: *Self, fn_ptr: ?*const anyopaque, wrappers: []?*anyopaque) void {
                    const callback = @as(FunctionType, @ptrCast(fn_ptr));
                    const ArgsTuple = std.meta.Tuple(&ValueTypes);

                    var args: ArgsTuple = undefined;
                    comptime var i: usize = 0;
                    inline while (i < AtomTypes.len) : (i += 1) {
                        const wrapper_ptr = wrappers[i];
                        const AtomType = AtomTypes[i];
                        const wrapper = @as(*AtomType, @ptrCast(@alignCast(wrapper_ptr)));
                        const value = wrapper.get();
                        args[i] = value;
                    }

                    const result = @call(.auto, callback, args);
                    data_wrapper.set(result);
                }
            }.handler;

            // List of Atoms, cast to ?*anyopaque
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
                            const self_ptr = @as(*Self, @ptrFromInt(userdata));
                            handler(self_ptr, self_ptr.depend_on_callback.?, self_ptr.depend_on_wrappers);
                        }
                    }.changeListener;
                    _ = try wrapper.addChangeListener(.{ .function = changeListener, .userdata = @intFromPtr(self) });
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
                if (node.data.type == .Change) {
                    node.data.function(value, node.data.userdata);
                }
                nullableNode = node.next;
            }
        }

        pub fn deinit(self: *Self) void {
            var nullableNode = self.onChange.first;
            while (nullableNode) |node| {
                nullableNode = node.next;
                if (node.data.type == .Destroy) {
                    node.data.function(undefined, node.data.userdata);
                }
                lasting_allocator.destroy(node);
            }
            if (self.allocator) |allocator| {
                allocator.destroy(self);
            }
        }
    };
}

// TODO: reimplement using Atom.derived and its arena allocator
pub fn FormattedAtom(allocator: std.mem.Allocator, comptime fmt: []const u8, childs: anytype) !*StringAtom {
    const Self = struct { wrapper: StringAtom, childs: @TypeOf(childs) };
    var self = try allocator.create(Self);
    const empty = try allocator.alloc(u8, 0); // alloc an empty string so it can be freed
    self.* = Self{ .wrapper = StringAtom.of(empty), .childs = childs };
    self.wrapper.allocator = allocator;

    const childTypes = comptime blk: {
        var types: []const type = &[_]type{};
        // Iterate over the 'childs' tuple for each atom
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
            inline for (std.meta.fields(@TypeOf(ptr.childs)), 0..) |childF, i| {
                const child = @field(ptr.childs, childF.name);
                tuple[i] = child.get();
            }

            const str = std.fmt.allocPrint(ptr.wrapper.allocator.?, fmt, tuple) catch unreachable;
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
        _ = try child.addChangeListener(.{ .userdata = @intFromPtr(self), .function = struct {
            fn callback(newValue: T, userdata: usize) void {
                _ = newValue;
                const ptr = @as(*Self, @ptrFromInt(userdata));
                format(ptr);
            }
        }.callback });
    }
    return &self.wrapper;
}

pub const StringAtom = Atom([]const u8);
pub const FloatAtom = Atom(f32);
pub const DoubleAtom = Atom(f64);

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
            .width = @max(a.width, b.width),
            .height = @max(a.height, b.height),
        };
    }

    /// Intersect two sizes by taking the lowest width and the lowest height
    pub fn intersect(a: Size, b: Size) Size {
        return Size{
            .width = @min(a.width, b.width),
            .height = @min(a.height, b.height),
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
    const floatTypes = .{ f16, f32, f64, f80, f128, c_longdouble };

    inline for (floatTypes) |Float| {
        try expectEqual(@as(Float, 0.0), lerp(@as(Float, 0), 1.0, 0.0)); // 0 |-0.0 > 1.0 = 0.0
        try expectEqual(@as(Float, 0.1), lerp(@as(Float, 0), 0.2, 0.5)); // 0 |-0.5 > 0.2 = 0.1
        try expectEqual(@as(Float, 0.5), lerp(@as(Float, 0), 1.0, 0.5)); // 0 |-0.5 > 1.0 = 0.5
        try expectEqual(@as(Float, 1.0), lerp(@as(Float, 0), 1.0, 1.0)); // 0 |-1.0 > 1.0 = 1.0
    }
}

test "atoms" {
    var testData = Atom(i32).of(0);
    testData.set(5);
    try expectEqual(@as(i32, 5), testData.get());
    try std.testing.expect(testData.hasAnimation() == false);
}

test "atom change listeners" {
    // TODO
}

test "format atom" {
    // FormattedAtom should be used with an arena allocator
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    // NOT PASSING DUE TO stage1 COMPILER BUGS
    // var dataSource1 = Atom(i32).of(5);
    // defer dataSource1.deinit();
    // var dataSource2 = Atom(f32).of(1.23);
    // defer dataSource2.deinit();
    //
    // var format = try FormattedAtom(allocator, "{} and {d}", .{ &dataSource1, &dataSource2 });
    // defer format.deinit();
    //
    // try std.testing.expectEqualStrings("5 and 1.23", format.get());
    // dataSource1.set(10);
    // try std.testing.expectEqualStrings("10 and 1.23", format.get());
    // dataSource2.set(1456.89);
    // try std.testing.expectEqualStrings("10 and 1456.89", format.get());

    var dataSource3 = Atom(i32).of(5);
    defer dataSource3.deinit();
    var dataSource4 = Atom(i32).of(1);
    defer dataSource4.deinit();

    var format2 = try FormattedAtom(allocator, "{} and {}", .{ &dataSource3, &dataSource4 });
    defer format2.deinit();
    try std.testing.expectEqualStrings("5 and 1", format2.get());
    dataSource3.set(10);
    try std.testing.expectEqualStrings("10 and 1", format2.get());
    dataSource4.set(42);
    try std.testing.expectEqualStrings("10 and 42", format2.get());
}

test "animated atom" {
    var original = Atom(i32).of(0);
    defer original.deinit();

    var animated = try Atom(i32).animated(&original, Easings.Linear, 1000);
    defer animated.deinit();
    defer _animatedAtoms.clearAndFree();
    defer _animatedAtomsLength.set(0);

    original.set(1000);
    try std.testing.expect(animated.hasAnimation());
}
