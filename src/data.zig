const std = @import("std");
const Container_Impl = @import("containers.zig").Container_Impl;
const internal = @import("internal.zig");
const lasting_allocator = internal.lasting_allocator;
const trait = @import("trait.zig");
const AnimationController = @import("AnimationController.zig");

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
    } else if (comptime trait.is(.optional)(T)) {
        if (a != null and b != null) {
            return lerp(a.?, b.?, t);
        } else {
            return b;
        }
    } else {
        @compileError("type " ++ @typeName(T) ++ " does not support linear interpolation");
    }
}

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

fn Animation(comptime T: type) type {
    return struct {
        start: std.time.Instant,
        /// Assume animation won't last more than 4000000 seconds
        duration: u32,
        min: T,
        max: T,
        animFn: *const fn (t: f64) f64,

        /// Get the current value from the animation
        pub fn get(self: @This()) T {
            const now = std.time.Instant.now() catch @panic("a monotonic clock is required for animations");
            const maxDiff = @as(f64, @floatFromInt(self.duration)) * @as(f64, std.time.ns_per_ms);
            const diff: f64 = @floatFromInt(now.since(self.start));
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
    if (!comptime trait.is(.@"struct")(T))
        return false;
    return @hasDecl(T, "ValueType") and T == Atom(T.ValueType);
}

test isAtom {
    try std.testing.expect(isAtom(Atom(u8)));
    try std.testing.expect(!isAtom(Size));
}

pub fn isListAtom(comptime T: type) bool {
    if (!comptime trait.is(.@"struct")(T))
        return false;
    return @hasDecl(T, "ValueType") and T == ListAtom(T.ValueType);
}

test isListAtom {
    try std.testing.expect(isListAtom(ListAtom([]const u8)));
    try std.testing.expect(!isListAtom(Atom([][]const u8)));
    try std.testing.expect(!isListAtom(Rectangle));
}

fn isAnimatableType(comptime T: type) bool {
    if (trait.isNumber(T) or (comptime trait.isContainer(T) and @hasDecl(T, "lerp"))) {
        return true;
    } else if (comptime trait.is(.optional)(T)) {
        return isAnimatableType(std.meta.Child(T));
    }
    return false;
}

test isAnimatableType {
    try std.testing.expect(isAnimatableType(@import("color.zig").Color));
    try std.testing.expect(isAnimatableType(f64));
    try std.testing.expect(!isAnimatableType([]const u8));
}

fn isPointer(comptime T: type) bool {
    return @typeInfo(T) == .pointer and std.meta.activeTag(@typeInfo(std.meta.Child(T))) != .@"fn";
}

test isPointer {
    try std.testing.expect(isPointer([]const u8));
    try std.testing.expect(isPointer(*u8));
    try std.testing.expect(!isPointer(*const fn (usize) bool));
}

/// An atom is used to add binding, change listening, thread safety and animation capabilities to
/// a value. It is used for all component properties.
///
/// For a guide on how to use it, see TODO.
///
/// Atom is a generic struct, which means you need to put the type `T` of your data in `Atom(T)`.
/// Then, you can use `Atom(T).of` in order to a get an atom for the given value.
pub fn Atom(comptime T: type) type {
    return struct {
        value: if (isAnimatable) union(enum) { Single: T, Animated: Animation(T) } else T,
        // TODO: switch to a lock that allow concurrent reads but one concurrent write
        lock: std.Thread.Mutex = .{},
        /// List of every change listener listening to this atom.
        /// A linked list is used for minimal stack overhead and to take
        /// advantage of the fact that most Atoms don't have a
        /// change listener.
        onChange: ChangeListenerList = .{},
        /// List of all Atoms this one is bound to.
        bindings: BindingList = .{},
        /// The checksum is used to compare the equality of the old value and the new value
        /// when calling the set() function. For instance, a real usecase is as follow:
        /// a string at address 0x1000 has content "abc", it then changes to "def" and
        /// Atom.set() is called. Without the checksum, Atom.set() wouldn't be able to know
        /// whether there's been a change or not.
        checksum: if (hasChecksum) u8 else void,

        /// If dependOn has been called, this is a pointer to the callback function
        depend_on_callback: ?*const anyopaque = null,
        /// If dependOn has been called, this is the list of atoms it depends on.
        depend_on_wrappers: []?*anyopaque = &.{},

        allocator: ?std.mem.Allocator = null,

        const Self = @This();
        const isAnimatable = isAnimatableType(T);
        const hasChecksum = isPointer(T);

        pub const ValueType = T;
        pub const ChangeListener = struct {
            function: *const fn (newValue: T, userdata: ?*anyopaque) void,
            userdata: ?*anyopaque = null,
            type: enum { Change, Destroy } = .Change,
        };
        pub const ChangeListenerListData = struct {
            listener: ChangeListener,
            id: usize,
        };
        pub const Binding = struct {
            bound_to: *Self,
            link_id: u16,
        };

        const ChangeListenerList = std.SinglyLinkedList(ChangeListenerListData);
        const BindingList = std.SinglyLinkedList(Binding);

        fn computeChecksum(value: T) u8 {
            const Crc = std.hash.crc.Crc8Wcdma;

            // comptime causes a lot of problems with hashing, so we just set the checksum to
            // 0, it's only used to detect potentially changed states, so it is not a problem.
            if (@inComptime()) return 0;

            return switch (@typeInfo(T).pointer.size) {
                .one => Crc.hash(std.mem.asBytes(value)),
                .many, .c, .slice => Crc.hash(std.mem.sliceAsBytes(value)),
            };
        }

        pub fn of(value: T) Self {
            if (isAnimatable) {
                // A pointer or a slice can't be animated, so no need to support
                // hasChecksum in this branch.
                return Self{ .value = .{ .Single = value }, .checksum = {} };
            } else {
                if (hasChecksum) {
                    return Self{ .value = value, .checksum = computeChecksum(value) };
                } else {
                    return Self{ .value = value, .checksum = {} };
                }
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

        /// Shorthand for Atom.alloc(undefined).dependOn(...)
        pub fn derived(tuple: anytype, function: anytype) !*Self {
            var wrapper = Self.alloc(undefined);
            try wrapper.dependOn(tuple, function);
            return wrapper;
        }

        /// Allocates a new atom and make it follow the value of the original atom, but
        /// with an animation.
        /// Note that the animated atom is automatically destroyed when the original atom is destroyed.
        pub fn withImplicitAnimation(original: *Self, controller: *AnimationController, easing: Easing, duration: u64) !*Self {
            var self = Self.alloc(original.get());
            try self.implicitlyAnimate(original, controller, easing, duration);
            return self;
        }

        /// Makes the atom follow the value of the given atom, but with an animation added.
        /// Note that the animated atom is automatically destroyed when the original atom is destroyed.
        pub fn implicitlyAnimate(self: *Self, original: *Self, controller: *AnimationController, easing: Easing, duration: u64) !void {
            self.set(original.get());
            const AnimationParameters = struct {
                easing: Easing,
                duration: u64,
                self_ptr: *Self,
                original_ptr: *Self,
                is_deinit: bool = false,
                change_listener_id: usize,
                controller: *AnimationController,
            };

            const userdata = try internal.lasting_allocator.create(AnimationParameters);
            userdata.* = .{
                .easing = easing,
                .duration = duration,
                .self_ptr = self,
                .original_ptr = original,
                .change_listener_id = undefined,
                .controller = controller,
            };

            const animate_fn = struct {
                fn a(new_value: T, uncast: ?*anyopaque) void {
                    const ptr: *AnimationParameters = @ptrCast(@alignCast(uncast));
                    ptr.self_ptr.animate(ptr.controller, ptr.easing, new_value, ptr.duration);
                }
            }.a;

            const destroy_fn = struct {
                fn a(_: T, uncast: ?*anyopaque) void {
                    const ptr: *AnimationParameters = @ptrCast(@alignCast(uncast));
                    const allocator = lasting_allocator;
                    const is_deinit = ptr.is_deinit;
                    const self_ptr = ptr.self_ptr;
                    allocator.destroy(ptr);

                    if (!is_deinit) self_ptr.deinit();
                }
            }.a;

            const self_destroy_fn = struct {
                fn a(_: T, uncast: ?*anyopaque) void {
                    const ptr: *AnimationParameters = @ptrCast(@alignCast(uncast));
                    ptr.is_deinit = true;
                    ptr.original_ptr.removeChangeListener(ptr.change_listener_id);
                }
            }.a;

            userdata.change_listener_id = try original.addChangeListener(.{
                .function = animate_fn,
                .userdata = userdata,
                .type = .Change,
            });
            _ = try original.addChangeListener(.{
                .function = destroy_fn,
                .userdata = userdata,
                .type = .Destroy,
            });
            _ = try self.addChangeListener(.{
                .function = self_destroy_fn,
                .userdata = userdata,
                .type = .Destroy,
            });
        }

        /// This function updates any current animation.
        /// It returns true if the animation isn't done, false otherwises.
        pub fn update(self: *Self) bool {
            if (!isAnimatable) return false;
            switch (self.value) {
                .Animated => |animation| {
                    const now = std.time.Instant.now() catch @panic("a monotonic clock is required for animations");
                    if (now.since(animation.start) >= @as(u64, animation.duration) * std.time.ns_per_ms) {
                        self.value = .{ .Single = animation.max };
                        self.callHandlers();
                        return false;
                    } else {
                        self.callHandlers();
                        return true;
                    }
                },
                .Single => return false,
            }
        }

        /// Returns true if there is currently an animation playing. This method doesn't lock the
        /// Atom.
        pub fn hasAnimation(self: *const Self) bool {
            if (!isAnimatable) return false;
            switch (self.value) {
                .Animated => |animation| {
                    const now = std.time.Instant.now() catch return false;
                    return now.since(animation.start) < @as(u64, animation.duration) * std.time.ns_per_ms;
                },
                .Single => return false,
            }
        }

        /// Starts an animation on the atom, from the current value to the `target` value. The
        /// animation will last `duration` milliseconds.
        pub fn animate(self: *Self, controller: *AnimationController, anim: *const fn (f64) f64, target: T, duration: u64) void {
            if (comptime !isAnimatable) {
                @compileError("animate() called on data that is not animatable");
            }
            const currentValue = self.get();
            self.value = .{ .Animated = Animation(T){
                .start = std.time.Instant.now() catch @panic("a monotonic clock is required for animations"),
                .duration = @as(u32, @intCast(duration)),
                .min = currentValue,
                .max = target,
                .animFn = anim,
            } };

            const is_already_animated = blk: {
                var iterator = controller.animated_atoms.iterate();
                defer iterator.deinit();
                while (iterator.next()) |item| {
                    if (@as(*anyopaque, @ptrCast(self)) == item.userdata) {
                        break :blk true;
                    }
                }
                break :blk false;
            };

            if (!is_already_animated) {
                controller.animated_atoms.append(.{
                    .fnPtr = @as(*const fn (*anyopaque) bool, @ptrCast(&Self.update)),
                    .userdata = self,
                }) catch {};
            }
        }

        fn changeListenerExists(self: *Self, id: usize) bool {
            var nullable_node = self.onChange.first;
            while (nullable_node) |node| {
                if (node.data.id == id) return true;
                nullable_node = node.next;
            }
            return false;
        }

        pub fn addChangeListener(self: *Self, listener: ChangeListener) !usize {
            // Generate a new ID for the change listener
            var id: usize = 0;
            while (self.changeListenerExists(id)) {
                id += 1;
            }

            // Add the new change listener to the linked list
            const node = try lasting_allocator.create(ChangeListenerList.Node);
            node.* = .{ .data = .{ .listener = listener, .id = id } };
            self.onChange.prepend(node);
            return id;
        }

        pub fn removeChangeListener(self: *Self, id: usize) void {
            var target_node: ?*ChangeListenerList.Node = null;
            var nullable_node = self.onChange.first;
            while (nullable_node) |node| {
                if (node.data.id == id) target_node = node;
                nullable_node = node.next;
            }

            if (target_node) |node| {
                self.onChange.remove(node);
                lasting_allocator.destroy(node);
            } else {
                // The node wasn't found (as it may have already been removed)
            }
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

        /// Binds both atoms both ways. This means that they will always have the same value.
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
        /// This function must be called whenever the Atom moves in memory.
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

        /// Thread-safe get operation. If what is desired is a read-modify-write operation
        /// then you must use the rmw() method.
        pub fn get(self: *Self) T {
            self.lock.lock();
            defer self.lock.unlock();
            return self.getUnsafe();
        }

        /// This gets the value of the atom without locking access to the value, which
        /// might cause race conditions. Do not use this! If you have an app with only one thread,
        /// then use the single_threaded build flag, don't use this function.
        pub fn getUnsafe(self: Self) T {
            if (isAnimatable) {
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
        /// Overall, this function will:
        /// - clear the current animation, if any
        /// - call all the change listeners
        /// - update all atoms that are bound to it
        pub fn set(self: *Self, value: T) void {
            self.extendedSet(value, .{});
        }

        const ExtendedSetOptions = struct {
            /// If true, lock before setting the value and unlock after.
            /// If false, do not lock before setting the value, but still unlock after.
            locking: bool = true,
        };

        fn extendedSet(self: *Self, value: T, comptime options: ExtendedSetOptions) void {
            // Whether the Atom changed to a new value or not.
            // The variable becomes true only if the new value is different from the older one.
            var didChange = false;
            {
                if (options.locking) self.lock.lock();
                defer self.lock.unlock();

                const old_value = self.getUnsafe();
                // This doesn't account for the fact that some data types don't have a unique representation.
                // This is, however, not problematic, as the goal is to avoid infinite loops where A sets B and
                // B sets A and so on. As the exact byte representation is copied when setting the value of an atom,
                // the fact that the value doesn't have a unique representation is not a problem.
                didChange = !std.meta.eql(old_value, value);

                // For slices and pointers, we need to handle the fact that the pointer and length
                // can stay the same but the content can change. Sadly, we don't have access to the
                // previous content as it may have been overwritten just before the call to the set()
                // function. So we need to rely on a small checksum.
                if (comptime isPointer(T)) {
                    const new_checksum = computeChecksum(value);
                    didChange = didChange or (new_checksum != self.checksum);
                    self.checksum = new_checksum;
                }

                if (isAnimatable) {
                    self.value = .{ .Single = value };
                } else {
                    self.value = value;
                }
            }

            if (didChange) {
                self.callHandlers();

                // Update bound atoms
                var nullableNode = self.bindings.first;
                while (nullableNode) |node| {
                    node.data.bound_to.set(value);
                    nullableNode = node.next;
                }
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
                    const callback = @as(FunctionType, @alignCast(@ptrCast(fn_ptr)));
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
                    if (comptime @typeInfo(@TypeOf(tuple[i])) != .pointer) {
                        @compileError("Dependencies must be pointers to atoms and not atoms themselves.");
                    }
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
                        fn changeListener(_: WrapperValueType, userdata: ?*anyopaque) void {
                            const self_ptr: *Self = @ptrCast(@alignCast(userdata.?));
                            handler(self_ptr, self_ptr.depend_on_callback.?, self_ptr.depend_on_wrappers);
                        }
                    }.changeListener;
                    _ = try wrapper.addChangeListener(.{ .function = changeListener, .userdata = self });
                }
            }

            self.depend_on_callback = fn_ptr;
            self.depend_on_wrappers = wrappers;
        }

        test dependOn {
            var a = Atom(u64).of(1);
            defer a.deinit();
            var b = Atom([]const u8).of("Hello");
            defer b.deinit();

            const cFunction = struct {
                fn cFunction(int: u64, string: []const u8) u64 {
                    return int + string.len;
                }
            }.cFunction;

            // Alternatively, you could use Atom.derived instead of .of(undefined)
            var c = Atom(u64).of(undefined);
            defer c.deinit();
            try c.dependOn(.{ &a, &b }, &cFunction);
            // now c is equal to 6 because 1 + 5 = 6

            a.set(5);
            // now c is equal to 10
            try std.testing.expectEqual(10, c.get());

            b.set("no");
            // and now c is equal to 7
            try std.testing.expectEqual(7, c.get());
        }

        fn callHandlers(self: *Self) void {
            // Iterate over each node of the linked list
            var nullableNode = self.onChange.first;
            const value = self.get();
            while (nullableNode) |node| {
                if (node.data.listener.type == .Change) {
                    node.data.listener.function(value, node.data.listener.userdata);
                }
                nullableNode = node.next;
            }
        }

        pub fn deinit(self: *Self) void {
            {
                var nullableNode = self.bindings.first;
                while (nullableNode) |node| {
                    nullableNode = node.next;
                    lasting_allocator.destroy(node);
                }
            }
            if (self.depend_on_wrappers.len > 0) {
                lasting_allocator.free(self.depend_on_wrappers);
            }
            {
                var nullableNode = self.onChange.first;
                while (nullableNode) |node| {
                    nullableNode = node.next;
                    if (node.data.listener.type == .Destroy) {
                        node.data.listener.function(undefined, node.data.listener.userdata);
                    }
                    lasting_allocator.destroy(node);
                }
            }
            if (self.allocator) |allocator| {
                allocator.destroy(self);
            }
        }
    };
}

/// A list of atoms, that is itself an atom.
pub fn ListAtom(comptime T: type) type {
    return struct {
        backing_list: ListType,
        length: Atom(usize),
        // TODO: since RwLock doesn't report deadlocks in Debug mode like Mutex does, do it manually here in ListAtom
        lock: std.Thread.RwLock = .{},
        /// List of every change listener listening to this atom.
        onChange: ChangeListenerList = .{},
        allocator: std.mem.Allocator,

        pub const ValueType = T;
        const Self = @This();
        const ListType = std.ArrayListUnmanaged(T);

        pub const ChangeListener = struct {
            function: *const fn (list: *Self, userdata: ?*anyopaque) void,
            userdata: ?*anyopaque = null,
            type: enum { Change, Destroy } = .Change,
        };

        const ChangeListenerList = std.SinglyLinkedList(ChangeListener);

        // Possible events to be handled by ListAtom:
        // - list size changed
        // - an item in the list got replaced by another

        pub const Iterator = struct {
            lock: *std.Thread.RwLock,
            items: []const T,
            index: usize = 0,

            pub fn next(self: *Iterator) ?T {
                const item = if (self.index < self.items.len) self.items[self.index] else null;
                self.index += 1;
                return item;
            }

            /// Returns a slice representing all the items in the ListAtom.
            /// The slice should only be used during the iterator's lifetime.
            pub fn getSlice(self: Iterator) []const T {
                return self.items;
            }

            pub fn deinit(self: Iterator) void {
                self.lock.unlockShared();
            }
        };

        pub fn init(allocator: std.mem.Allocator) Self {
            const list: ListType = ListType.initCapacity(allocator, 0) catch unreachable;
            return Self{
                .backing_list = list,
                .length = Atom(usize).of(0),
                .allocator = internal.lasting_allocator,
            };
        }

        // TODO: init from list like .{ "a", "b", "c" }

        pub fn get(self: *Self, index: usize) T {
            self.lock.lockShared();
            defer self.lock.unlockShared();

            return self.backing_list.items[index];
        }

        // The returned pointer is a constant pointer because if an edit
        // was made on the pointer itself, the replace event wouldn't be
        // invoked.
        pub fn getPtr(self: *Self, index: usize) *const T {
            self.lock.lockShared();
            defer self.lock.unlockShared();

            return &self.backing_list.items[index];
        }

        pub fn getLength(self: *Self) usize {
            return self.length.get();
        }

        pub fn set(self: *Self, index: usize, value: T) void {
            {
                self.lock.lock();
                defer self.lock.unlock();

                self.backing_list.items[index] = value;
            }
            self.callHandlers();
        }

        pub fn append(self: *Self, value: T) !void {
            {
                self.lock.lock();
                defer self.lock.unlock();
                // Given that the length is updated only at the end, the operation doesn't need a lock

                try self.backing_list.append(self.allocator, value);
                self.length.set(self.backing_list.items.len);
            }
            self.callHandlers();
        }

        pub fn popOrNull(self: *Self) ?T {
            const result = blk: {
                self.lock.lock();
                defer self.lock.unlock();

                const result = self.backing_list.pop();
                self.length.set(self.backing_list.items.len);
                break :blk result;
            };
            self.callHandlers();
            return result;
        }

        pub fn pop(self: *Self) T {
            std.debug.assert(self.getLength() > 0);
            return self.popOrNull().?;
        }

        pub fn swapRemove(self: *Self, index: usize) T {
            // self.lock.lock();
            // defer self.lock.unlock();

            const result = self.backing_list.swapRemove(index);
            self.length.set(self.backing_list.items.len);
            self.callHandlers();
            return result;
        }

        pub fn orderedRemove(self: *Self, index: usize) T {
            const result = blk: {
                self.lock.lock();
                defer self.lock.unlock();

                const result = self.backing_list.orderedRemove(index);
                self.length.set(self.backing_list.items.len);
                break :blk result;
            };
            self.callHandlers();
            return result;
        }

        pub fn clear(self: *Self, mode: enum { free, retain_capacity }) void {
            {
                self.lock.lock();
                defer self.lock.unlock();

                switch (mode) {
                    .free => self.backing_list.clearAndFree(self.allocator),
                    .retain_capacity => self.backing_list.clearRetainingCapacity(),
                }
                self.length.set(0);
            }
            self.callHandlers();
        }

        /// Lock the list and return an iterator.
        /// The iterator MUST be deinit otherwise the list will remain locked forever.
        pub fn iterate(self: *Self) Iterator {
            self.lock.lockShared();
            return Iterator{
                .lock = &self.lock,
                .items = self.backing_list.items,
            };
        }

        pub fn map(self: *Self, comptime U: type, func: *const fn (T) U) *ListAtom(U) {
            _ = self;
            _ = func;
            return undefined;
        }

        pub fn addChangeListener(self: *Self, listener: ChangeListener) !usize {
            const node = try lasting_allocator.create(ChangeListenerList.Node);
            node.* = .{ .data = listener };
            self.onChange.prepend(node);
            return self.onChange.len() - 1;
        }

        fn callHandlers(self: *Self) void {
            // Iterate over each node of the linked list
            var nullableNode = self.onChange.first;
            while (nullableNode) |node| {
                if (node.data.type == .Change) {
                    node.data.function(self, node.data.userdata);
                }
                nullableNode = node.next;
            }
        }

        pub fn deinit(self: *Self) void {
            self.lock.lock();
            defer self.lock.unlock();

            {
                var nullableNode = self.onChange.first;
                while (nullableNode) |node| {
                    nullableNode = node.next;
                    if (node.data.type == .Destroy) {
                        node.data.function(self, node.data.userdata);
                    }
                    lasting_allocator.destroy(node);
                }
            }

            self.length.deinit();
            self.backing_list.deinit(self.allocator);
        }
    };
}

test ListAtom {
    var list = ListAtom(u32).init(std.testing.allocator);
    defer list.deinit();

    try list.append(1);
    try std.testing.expectEqual(1, list.getLength());
    try list.append(2);
    try std.testing.expectEqual(2, list.getLength());

    try std.testing.expectEqual(1, list.get(0));
    const tail = list.pop();
    try std.testing.expectEqual(2, tail);

    list.clear(.free);
    try std.testing.expectEqual(0, list.getLength());
}

// TODO: reimplement using Atom.derived and its arena allocator
pub fn FormattedAtom(allocator: std.mem.Allocator, comptime fmt: []const u8, childs: anytype) !*Atom([]const u8) {
    const Self = struct { wrapper: Atom([]const u8), childs: @TypeOf(childs) };
    var self = try allocator.create(Self);
    const empty = try allocator.alloc(u8, 0); // alloc an empty string so it can be freed
    self.* = Self{ .wrapper = Atom([]const u8).of(empty), .childs = childs };
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
        _ = try child.addChangeListener(.{ .userdata = self, .function = struct {
            fn callback(newValue: T, userdata: ?*anyopaque) void {
                _ = newValue;
                const ptr: *Self = @ptrCast(@alignCast(userdata.?));
                format(ptr);
            }
        }.callback });
    }
    const deinitFn = struct {
        fn deinit(_: []const u8, userdata: ?*anyopaque) void {
            const ptr: *Self = @ptrCast(@alignCast(userdata));
            ptr.wrapper.allocator.?.free(ptr.wrapper.get());
        }
    }.deinit;
    _ = try self.wrapper.addChangeListener(.{
        .function = deinitFn,
        .userdata = self,
        .type = .Destroy,
    });

    return &self.wrapper;
}

/// A position expressed in display pixels.
pub const Position = struct {
    x: f32,
    y: f32,

    /// Shorthand for struct initialization
    pub fn init(x: f32, y: f32) Position {
        return Position{ .x = x, .y = y };
    }

    pub fn lerp(a: Position, b: Position, t: f64) Position {
        return Position{
            .x = lerpFloat(a.x, b.x, t),
            .y = lerpFloat(a.y, b.y, t),
        };
    }
};

/// A size expressed in display pixels.
pub const Size = struct {
    width: f32,
    height: f32,

    /// Shorthand for struct initialization
    pub fn init(width: f32, height: f32) Size {
        std.debug.assert(width >= 0);
        std.debug.assert(height >= 0);
        return Size{ .width = width, .height = height };
    }

    /// Returns the size with the least area
    pub fn min(a: Size, b: Size) Size {
        std.debug.assert(a.width >= 0 and a.height >= 0);
        std.debug.assert(b.width >= 0 and b.height >= 0);
        if (a.width * a.height < b.width * b.height) {
            return a;
        } else {
            return b;
        }
    }

    /// Returns the size with the most area
    pub fn max(a: Size, b: Size) Size {
        std.debug.assert(a.width >= 0 and a.height >= 0);
        std.debug.assert(b.width >= 0 and b.height >= 0);
        if (a.width * a.height > b.width * b.height) {
            return a;
        } else {
            return b;
        }
    }

    /// Combine two sizes by taking the largest width and the largest height
    pub fn combine(a: Size, b: Size) Size {
        std.debug.assert(a.width >= 0 and a.height >= 0);
        std.debug.assert(b.width >= 0 and b.height >= 0);
        return Size{
            .width = @max(a.width, b.width),
            .height = @max(a.height, b.height),
        };
    }

    /// Intersect two sizes by taking the lowest width and the lowest height
    pub fn intersect(a: Size, b: Size) Size {
        std.debug.assert(a.width >= 0 and a.height >= 0);
        std.debug.assert(b.width >= 0 and b.height >= 0);
        return Size{
            .width = @min(a.width, b.width),
            .height = @min(a.height, b.height),
        };
    }

    pub fn lerp(a: Size, b: Size, t: f64) Size {
        std.debug.assert(a.width >= 0 and a.height >= 0);
        std.debug.assert(b.width >= 0 and b.height >= 0);
        return Size{
            .width = lerpFloat(a.width, b.width, t),
            .height = lerpFloat(a.height, b.height, t),
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

    pub fn init(ox: f32, oy: f32, owidth: f32, oheight: f32) Rectangle {
        return Rectangle{
            .origin = Position.init(ox, oy),
            .size = Size.init(owidth, oheight),
        };
    }

    pub fn lerp(a: Rectangle, b: Rectangle, t: f64) Rectangle {
        return Rectangle{
            .origin = Position.lerp(a.origin, b.origin, t),
            .size = Size.lerp(a.size, b.size, t),
        };
    }

    pub fn x(self: Rectangle) f32 {
        return self.origin.x;
    }

    pub fn y(self: Rectangle) f32 {
        return self.origin.y;
    }

    pub fn width(self: Rectangle) f32 {
        return self.size.width;
    }

    pub fn height(self: Rectangle) f32 {
        return self.size.height;
    }

    pub fn combine(a: Rectangle, b: Rectangle) Rectangle {
        // The X coordinate of the right-most point of the first rectangle.
        const right = a.origin.x + a.size.width;
        // The Y coordinate of the bottom point of the first rectangle.
        const bottom = a.origin.y + a.size.height;

        const new_origin = Position{
            .x = @min(a.origin.x, b.origin.x),
            .y = @min(a.origin.y, b.origin.y),
        };
        return .{
            .origin = new_origin,
            .size = .{
                .width = @max(right, b.origin.x + b.size.width) - new_origin.x,
                .height = @max(bottom, b.origin.y + b.size.height) - new_origin.y,
            },
        };
    }

    pub fn intersection(a: Rectangle, b: Rectangle) Rectangle {
        _ = a;
        _ = b;
        return undefined;
    }
};

const expectEqual = std.testing.expectEqual;

test lerp {
    const floatTypes = .{ f16, f32, f64, f80, f128, c_longdouble };

    inline for (floatTypes) |Float| {
        try expectEqual(@as(Float, 0.0), lerp(@as(Float, 0), 1.0, 0.0)); // 0 |-0.0 > 1.0 = 0.0
        try expectEqual(@as(Float, 0.1), lerp(@as(Float, 0), 0.2, 0.5)); // 0 |-0.5 > 0.2 = 0.1
        try expectEqual(@as(Float, 0.5), lerp(@as(Float, 0), 1.0, 0.5)); // 0 |-0.5 > 1.0 = 0.5
        try expectEqual(@as(Float, 1.0), lerp(@as(Float, 0), 1.0, 1.0)); // 0 |-1.0 > 1.0 = 1.0
    }
}

test Atom {
    var testData = Atom(i32).of(0);
    testData.set(5);
    try expectEqual(@as(i32, 5), testData.get());
    try std.testing.expect(testData.hasAnimation() == false);
}

test "atom change listeners" {
    // TODO
}

test FormattedAtom {
    // FormattedAtom should be used with an arena allocator
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var dataSource1 = Atom(i32).of(5);
    defer dataSource1.deinit();
    var dataSource2 = Atom(f32).of(1.23);
    defer dataSource2.deinit();

    var format = try FormattedAtom(allocator, "{} and {d}", .{ &dataSource1, &dataSource2 });
    defer format.deinit();

    try std.testing.expectEqualStrings("5 and 1.23", format.get());
    dataSource1.set(10);
    try std.testing.expectEqualStrings("10 and 1.23", format.get());
    dataSource2.set(1456.89);
    try std.testing.expectEqualStrings("10 and 1456.89", format.get());

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

    {
        var on_frame = @import("listener.zig").EventSource.init(std.testing.allocator);
        defer on_frame.deinitAllListeners();
        var animation_controller = try AnimationController.init(std.testing.allocator, &on_frame);
        defer animation_controller.deinit();
        var animated = try Atom(i32).withImplicitAnimation(
            &original,
            animation_controller,
            Easings.Linear,
            5000,
        );
        defer animated.deinit();

        original.set(1000);
        try std.testing.expect(animated.hasAnimation());
    }

    // Should still work even after the animated atom is destroyed
    original.set(500);
}
