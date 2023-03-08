pub const Window = @import("window.zig").Window;
pub const Widget = @import("widget.zig").Widget;

pub usingnamespace @import("components/Align.zig");
pub usingnamespace @import("components/Button.zig");
pub usingnamespace @import("components/Canvas.zig");
pub usingnamespace @import("components/CheckBox.zig");
pub usingnamespace @import("components/Image.zig");
pub usingnamespace @import("components/Label.zig");
pub usingnamespace @import("components/Menu.zig");
pub usingnamespace @import("components/Navigation.zig");
pub usingnamespace @import("components/Slider.zig");
pub usingnamespace @import("components/Scrollable.zig");
pub usingnamespace @import("components/Tabs.zig");
pub usingnamespace @import("components/TextArea.zig");
pub usingnamespace @import("components/TextField.zig");
pub usingnamespace @import("containers.zig");

pub usingnamespace @import("color.zig");
pub usingnamespace @import("data.zig");
pub usingnamespace @import("image.zig");
pub usingnamespace @import("list.zig");

pub const internal = @import("internal.zig");
pub const backend = @import("backend.zig");
pub const http = @import("http.zig");
pub const dev_tools = @import("dev_tools.zig");

const ENABLE_DEV_TOOLS = if (@hasDecl(@import("root"), "enable_dev_tools"))
    @import("root").enable_dev_tools
else
    @import("builtin").mode == .Debug;

pub const cross_platform = if (@hasDecl(backend, "backendExport"))
    backend.backendExport
else
    struct {};

pub const GlBackend = @import("backends/gles/backend.zig");

pub const EventLoopStep = @import("backends/shared.zig").EventLoopStep;
pub const MouseButton = @import("backends/shared.zig").MouseButton;

pub fn init() !void {
    try backend.init();
    if (ENABLE_DEV_TOOLS) {
        try dev_tools.init();
    }
}

pub fn deinit() void {
    if (ENABLE_DEV_TOOLS) {
        dev_tools.deinit();
    }
}

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
        data._animatedDataWrappersMutex.lock();
        defer data._animatedDataWrappersMutex.unlock();

        for (data._animatedDataWrappers.items, 0..) |item, i| {
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
