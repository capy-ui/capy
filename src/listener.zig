const std = @import("std");
const lasting_allocator = @import("internal.zig").lasting_allocator;
const Atom = @import("data.zig").Atom;

pub const EventSource = struct {
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
        self.listeners.swapRemove(index);
    }

    pub fn callListeners(self: *const EventSource) void {
        for (self.listeners.items) |listener| {
            if (listener.enabled.get()) {
                listener.call();
            }
        }
    }

    pub fn hasEnabledListeners(self: *const EventSource) bool {
        var result = false;

        for (self.listeners.items) |listener| {
            if (listener.enabled.get()) {
                result = true;
            }
        }

        return result;
    }
};

pub const Listener = struct {
    listened: *EventSource,
    callback: *const fn (userdata: ?*anyopaque) void,
    userdata: ?*anyopaque = null,
    /// The listener is called only if enabled is set to true.
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
        lasting_allocator.destroy(self);
    }
};
