pub const Window = @import("window.zig").Window;

pub usingnamespace @import("button.zig");
pub usingnamespace @import("label.zig");
pub usingnamespace @import("text.zig");
pub usingnamespace @import("canvas.zig");
pub usingnamespace @import("containers.zig");
pub usingnamespace @import("data.zig");

pub const internal = @import("internal.zig");
pub const backend  = @import("backend.zig");

pub const EventLoopStep = enum {
    Blocking,
    Asynchronous
};

/// Returns true if the last window has been closed.
pub fn stepEventLoop(stepType: EventLoopStep) bool {
    return backend.runStep(stepType);
}

pub fn runEventLoop() void {
    while (true) {
        if (@import("std").io.is_async) {
            if (backend.runStep(.Asynchronous)) {
                break;
            }
            
            if (@import("std").event.Loop.instance) |*loop| {
                loop.yield();
            }
        } else {
            if (backend.runStep(.Blocking)) {
                break;
            }
        }
    }
}

// TODO: widget types with comptime reflection (some sort of vtable)
