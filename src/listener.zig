const std = @import("std");
const lasting_allocator = @import("internal.zig").allocator;
const Atom = @import("data.zig").Atom;
const ListAtom = @import("data.zig").ListAtom;
const internal = @import("internal.zig");

/// This event source is never triggered.
pub var null_event_source = EventSource.init(internal.allocator);

pub const EventSource = struct {
    listeners: ListAtom(*Listener),

    pub fn alloc(allocator: std.mem.Allocator) !*EventSource {
        const source = try allocator.create(EventSource);
        source.* = EventSource.init(allocator);
        return source;
    }

    pub fn init(allocator: std.mem.Allocator) EventSource {
        return .{ .listeners = ListAtom(*Listener).init(allocator) };
    }

    /// Create a new Listener tied to this EventSource.
    pub fn listen(self: *EventSource, config: Listener.Config) std.mem.Allocator.Error!*Listener {
        const listener = try Listener.init(self, config);
        try self.listeners.append(listener);
        return listener;
    }

    pub fn add(self: *EventSource, listener: *Listener) std.mem.Allocator.Error!void {
        try self.listeners.append(listener);
    }

    pub fn remove(self: *EventSource, listener: *Listener) void {
        const index = blk: {
            var iterator = self.listeners.iterate();
            defer iterator.deinit();

            break :blk std.mem.indexOfScalar(*Listener, iterator.getSlice(), listener) orelse return;
        };
        std.debug.assert(self.listeners.swapRemove(index) == listener);
    }

    pub fn callListeners(self: *EventSource) void {
        var iterator = self.listeners.iterate();
        defer iterator.deinit();

        while (iterator.next()) |listener| {
            if (listener.enabled.get()) {
                listener.call();
            }
        }
    }

    /// Returns true if there is atleast one listener listening to this event source
    pub fn hasEnabledListeners(self: *EventSource) bool {
        var result = false;

        var iterator = self.listeners.iterate();
        defer iterator.deinit();
        while (iterator.next()) |listener| {
            if (listener.enabled.get()) {
                result = true;
            }
        }

        return result;
    }

    /// Deinits all listeners associated to this event source.
    /// Make sure this is executed at last resort as this will make every Listener invalid and cause a
    /// use-after-free if you still use them. So be sure their lifetime is all over.
    pub fn deinitAllListeners(self: *EventSource) void {
        {
            var iterator = self.listeners.iterate();
            defer iterator.deinit();

            while (iterator.next()) |listener| {
                listener.deinit();
            }
        }
        self.listeners.deinit();
    }
};

pub const Listener = struct {
    listened: *EventSource,
    callback: *const fn (userdata: ?*anyopaque) void,
    userdata: ?*anyopaque = null,
    /// The listener is called only when it is enabled.
    enabled: Atom(bool) = Atom(bool).of(true),

    pub const Config = struct {
        callback: *const fn (userdata: ?*anyopaque) void,
        userdata: ?*anyopaque = null,
        /// The listener is called only if enabled is set to true.
        enabled: bool = true,
    };

    fn init(listened: *EventSource, config: Listener.Config) std.mem.Allocator.Error!*Listener {
        const listener = try lasting_allocator.create(Listener);
        listener.* = .{
            .listened = listened,
            .callback = config.callback,
            .userdata = config.userdata,
            .enabled = Atom(bool).of(config.enabled),
        };
        return listener;
    }

    pub fn call(self: *const Listener) void {
        self.callback(self.userdata);
    }

    pub fn deinit(self: *Listener) void {
        self.listened.remove(self);
        self.enabled.deinit();
        lasting_allocator.destroy(self);
    }
};
