const std = @import("std");
const lasting_allocator = @import("internal.zig").lasting_allocator;
const Atom = @import("data.zig").Atom;

pub const EventSource = struct {
    // TODO: use ListAtom(*Listener)
    listeners: std.ArrayList(*Listener),

    pub fn init(allocator: std.mem.Allocator) EventSource {
        return .{ .listeners = std.ArrayList(*Listener).init(allocator) };
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
        const index = std.mem.indexOfScalar(*Listener, self.listeners.items, listener) orelse return;
        std.debug.assert(self.listeners.swapRemove(index) == listener);
    }

    pub fn callListeners(self: *const EventSource) void {
        for (self.listeners.items) |listener| {
            if (listener.enabled.get()) {
                listener.call();
            }
        }
    }

    /// Returns true if there is atleast one listener listening to this event source
    pub fn hasEnabledListeners(self: *const EventSource) bool {
        var result = false;

        for (self.listeners.items) |listener| {
            if (listener.enabled.get()) {
                result = true;
            }
        }

        return result;
    }

    /// Deinits all listeners associated to this event source.
    /// Make sure this is executed at last resort as this will make every Listener invalid and cause a
    /// use-after-free if you still use them. So be sure their lifetime is all over.
    pub fn deinitAllListeners(self: *const EventSource) void {
        for (self.listeners.items) |listener| {
            listener.deinit();
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
