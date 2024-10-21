const std = @import("std");
const data = @import("data.zig");
const Atom = data.Atom;
const ListAtom = data.ListAtom;
const EventSource = @import("listener.zig").EventSource;
const Listener = @import("listener.zig").Listener;

pub const AnimationCallback = struct {
    fnPtr: *const fn (data: *anyopaque) bool,
    userdata: *anyopaque,
};

const AnimationController = @This();

animated_atoms: ListAtom(AnimationCallback),
on_frame: *EventSource,
listener: ?*Listener,

pub fn init(allocator: std.mem.Allocator, on_frame: *EventSource) !*AnimationController {
    const controller = try allocator.create(AnimationController);
    controller.* = .{
        .animated_atoms = ListAtom(AnimationCallback).init(allocator),
        .on_frame = on_frame,
        .listener = undefined,
    };

    const listener = try on_frame.listen(.{
        .callback = update,
        .userdata = controller,
    });
    try listener.enabled.dependOn(.{&controller.animated_atoms.length}, &struct {
        fn callback(length: usize) bool {
            return length > 0;
        }
    }.callback);
    controller.listener = listener;
    return controller;
}

fn update(ptr: ?*anyopaque) void {
    const self: *AnimationController = @ptrCast(@alignCast(ptr.?));
    var iterator = self.animated_atoms.iterate();
    defer iterator.deinit();

    while (iterator.next()) |item| {
        if (item.fnPtr(item.userdata) == true) {
            // TODO: remove.
        }
    }
}

pub fn deinit(self: *AnimationController) void {
    self.animated_atoms.deinit();
    if (self.listener) |listener| listener.deinit();
}

var null_animation_controller_instance = AnimationController{
    .animated_atoms = ListAtom(AnimationCallback).init(@import("internal.zig").lasting_allocator),
    .on_frame = &@import("listener.zig").null_event_source,
    .listener = null,
};

/// This is an animation controller that is never triggered. It's used by components while they
/// don't have a proper animation controller.
/// This controller cannot be deinitialized.
pub var null_animation_controller = &null_animation_controller_instance;
