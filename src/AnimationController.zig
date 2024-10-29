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
            return length >= 0;
        }
    }.callback);
    controller.listener = listener;
    return controller;
}

fn update(ptr: ?*anyopaque) void {
    const self: *AnimationController = @ptrCast(@alignCast(ptr.?));

    // List of atoms that are no longer animated and that need to be removed from the list
    var toRemove = std.BoundedArray(usize, 64).init(0) catch unreachable;
    {
        var iterator = self.animated_atoms.iterate();
        defer iterator.deinit();
        {
            var i: usize = 0;
            while (iterator.next()) |item| : (i += 1) {
                if (item.fnPtr(item.userdata) == false) { // animation ended
                    toRemove.append(i) catch |err| switch (err) {
                        error.Overflow => {}, // It can be removed on the next call to animateAtoms()
                    };
                }
            }
        }

        // The following code is part of the same block as swapRemove relies on the caller locking
        // the mutex
        {
            // The index list is ordered in increasing index order
            const indexList = toRemove.constSlice();
            // So we iterate it backward in order to avoid indices being invalidated
            if (indexList.len > 0) {
                var i: usize = indexList.len - 1;
                while (i >= 0) {
                    _ = self.animated_atoms.swapRemove(indexList[i]);
                    if (i == 0) {
                        break;
                    } else {
                        i -= 1;
                    }
                }
            }
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

/// This animation controller is never triggered. It is used by components that don't have a proper
/// animation controller.
/// It cannot be deinitialized.
pub const null_animation_controller = &null_animation_controller_instance;
