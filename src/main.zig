pub const Window = @import("window.zig").Window;
pub const Widget = @import("widget.zig").Widget;

pub usingnamespace @import("button.zig");
pub usingnamespace @import("label.zig");
pub usingnamespace @import("text.zig");
pub usingnamespace @import("canvas.zig");
pub usingnamespace @import("containers.zig");
pub usingnamespace @import("data.zig");
pub usingnamespace @import("image.zig");
pub usingnamespace @import("color.zig");

pub const internal = @import("internal.zig");
pub const backend  = @import("backend.zig");

pub const cross_platform = if (@hasDecl(backend, "backendExport"))
    backend.backendExport
else
    struct {};

pub const GlBackend = @import("backends/gles/backend.zig");

pub const MouseButton = backend.MouseButton;

pub const EventLoopStep = enum {
    Blocking,
    Asynchronous
};

/// Posts an empty event to finish the current step started in zgt.stepEventLoop
pub fn wakeEventLoop() void {
    backend.postEmptyEvent();
}

/// Returns false if the last window has been closed.
pub fn stepEventLoop(stepType: EventLoopStep) bool {
    return backend.runStep(stepType);
}

pub fn runEventLoop() void {
    while (true) {
        if (@import("std").io.is_async) {
            if (!backend.runStep(.Asynchronous)) {
                break;
            }
            
            if (@import("std").event.Loop.instance) |*loop| {
                loop.yield();
            }
        } else {
            if (!backend.runStep(.Blocking)) {
                break;
            }
        }
    }
}

// TODO: widget types with comptime reflection (some sort of vtable)
