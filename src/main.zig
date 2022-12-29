pub const Window = @import("window.zig").Window;
pub const Widget = @import("widget.zig").Widget;

pub usingnamespace @import("align.zig");
pub usingnamespace @import("button.zig");
pub usingnamespace @import("checkbox.zig");
pub usingnamespace @import("label.zig");
pub usingnamespace @import("text.zig");
pub usingnamespace @import("canvas.zig");
pub usingnamespace @import("containers.zig");
pub usingnamespace @import("list.zig");
pub usingnamespace @import("tabs.zig");
pub usingnamespace @import("scrollable.zig");
pub usingnamespace @import("menu.zig");
pub usingnamespace @import("data.zig");
pub usingnamespace @import("image.zig");
pub usingnamespace @import("color.zig");

pub const internal = @import("internal.zig");
pub const backend = @import("backend.zig");
pub const http = @import("http.zig");

pub const cross_platform = if (@hasDecl(backend, "backendExport"))
    backend.backendExport
else
    struct {};

pub const GlBackend = @import("backends/gles/backend.zig");

pub const EventLoopStep = @import("backends/shared.zig").EventLoopStep;
pub const MouseButton = @import("backends/shared.zig").MouseButton;

/// Posts an empty event to finish the current step started in zgt.stepEventLoop
pub fn wakeEventLoop() void {
    backend.postEmptyEvent();
}

/// Returns false if the last window has been closed.
/// Even if the wanted step type is Blocking, zgt has the right
/// to request an asynchronous step to the backend in order to animate
/// data wrappers.
pub fn stepEventLoop(stepType: EventLoopStep) bool {
    const data = @import("data.zig");
    if (data._animatedDataWrappers.items.len > 0) {
        for (data._animatedDataWrappers.items) |item, i| {
            if (item.fnPtr(item.userdata) == false) { // animation ended
                _ = data._animatedDataWrappers.swapRemove(i);
            }
        }
        return backend.runStep(.Asynchronous);
    } else {
        return backend.runStep(stepType);
    }
}

pub fn runEventLoop() void {
    while (true) {
        if (@import("std").io.is_async) {
            if (!stepEventLoop(.Asynchronous)) {
                break;
            }

            if (@import("std").event.Loop.instance) |loop| {
                loop.yield();
            }
        } else {
            if (!stepEventLoop(.Blocking)) {
                break;
            }
        }
    }
}

test {
    _ = @import("fuzz.zig"); // testing the fuzzing library
}
