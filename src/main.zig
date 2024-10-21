const std = @import("std");

pub const Window = @import("window.zig").Window;
pub const Widget = @import("widget.zig").Widget;

pub usingnamespace @import("components/Alignment.zig");
pub usingnamespace @import("components/Button.zig");
pub usingnamespace @import("components/Canvas.zig");
pub usingnamespace @import("components/CheckBox.zig");
pub usingnamespace @import("components/Dropdown.zig");
pub usingnamespace @import("components/Image.zig");
pub usingnamespace @import("components/Label.zig");
pub usingnamespace @import("components/Menu.zig");
pub usingnamespace @import("components/Navigation.zig");
pub usingnamespace @import("components/NavigationSidebar.zig");
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
pub usingnamespace @import("timer.zig");

pub const Monitor = @import("monitor.zig").Monitor;
pub const Monitors = @import("monitor.zig").Monitors;
pub const VideoMode = @import("monitor.zig").VideoMode;

pub const AnimationController = @import("AnimationController.zig");

pub const Listener = @import("listener.zig").Listener;
pub const EventSource = @import("listener.zig").EventSource;

pub const internal = @import("internal.zig");
pub const backend = @import("backend.zig");
pub const http = @import("http.zig");
pub const dev_tools = @import("dev_tools.zig");
pub const audio = @import("audio.zig");

pub const lasting_allocator = internal.lasting_allocator;
pub const scratch_allocator = internal.scratch_allocator;

const ENABLE_DEV_TOOLS = if (@hasDecl(@import("root"), "enable_dev_tools"))
    @import("root").enable_dev_tools
else
    @import("builtin").mode == .Debug and false;

pub const cross_platform = if (@hasDecl(backend, "backendExport"))
    backend.backendExport
else
    struct {};

pub const EventLoopStep = @import("backends/shared.zig").EventLoopStep;
pub const MouseButton = @import("backends/shared.zig").MouseButton;

// This is a private global variable used for safety.
var isCapyInitialized: bool = false;
pub fn init() !void {
    try backend.init();
    if (ENABLE_DEV_TOOLS) {
        try dev_tools.init();
    }

    Monitors.init();

    var listener = eventStep.listen(.{ .callback = animateAtoms }) catch unreachable;
    // The listener is enabled only if there is at least 1 atom currently being animated
    listener.enabled.dependOn(.{&@import("data.zig")._animatedAtomsLength}, &struct {
        fn a(num: usize) bool {
            return num >= 1;
        }
    }.a) catch unreachable;

    var timerListener = eventStep.listen(.{ .callback = @import("timer.zig").handleTimersTick }) catch unreachable;
    // The listener is enabled only if there is at least 1 timer is running
    timerListener.enabled.dependOn(.{&@import("timer.zig").runningTimers.length}, &struct {
        fn a(num: usize) bool {
            return num >= 1;
        }
    }.a) catch unreachable;
    isCapyInitialized = true;
}

pub fn deinit() void {
    isCapyInitialized = false;
    Monitors.deinit();

    @import("data.zig")._animatedAtoms.deinit();
    @import("data.zig")._animatedAtomsLength.deinit();
    @import("timer.zig").runningTimers.deinit();

    eventStep.deinitAllListeners();
    if (ENABLE_DEV_TOOLS) {
        dev_tools.deinit();
    }
}

/// Posts an empty event to finish the current step started in capy.stepEventLoop
pub fn wakeEventLoop() void {
    backend.postEmptyEvent();
}

/// Returns false if the last window has been closed.
/// Even if the wanted step type is Blocking, capy has the right
/// to request an asynchronous step to the backend in order to animate
/// data wrappers.
pub fn stepEventLoop(stepType: EventLoopStep) bool {
    std.debug.assert(isCapyInitialized);
    eventStep.callListeners();

    // const timer = @import("timer.zig");
    // if (timer._runningTimers.items.len > 0) {
    //     const now = std.time.Instant.now() catch unreachable;
    //     // TODO: mutex
    //     for (timer._runningTimers.items, 0..) |item, i| {
    //         _ = i;
    //         if (now.since(item.started.?) >= item.duration.get()) {
    //             // TODO: tick timer
    //             item.started = now;
    //             item.tick(item);
    //         }
    //     }
    //     return backend.runStep(.Asynchronous);
    // }

    // if (timer._runningTimers.items.len > 0) {
    //     return backend.runStep(.Asynchronous);
    // }
    if (eventStep.hasEnabledListeners()) {
        // TODO: don't do that and instead encourage to use something like Window.vsync
        return backend.runStep(.Asynchronous);
    }
    return backend.runStep(stepType);
}

var eventStepInstance: EventSource = EventSource.init(internal.lasting_allocator);
pub const eventStep = &eventStepInstance;

fn animateAtoms(_: ?*anyopaque) void {
    const data = @import("data.zig");
    data._animatedAtomsMutex.lock();
    defer data._animatedAtomsMutex.unlock();

    // List of atoms that are no longer animated and that need to be removed from the list
    var toRemove = std.BoundedArray(usize, 64).init(0) catch unreachable;
    for (data._animatedAtoms.items, 0..) |item, i| {
        if (item.fnPtr(item.userdata) == false) { // animation ended
            toRemove.append(i) catch |err| switch (err) {
                error.Overflow => {}, // It can be removed on the next call to animateAtoms()
            };
        }
    }

    // The index list is ordered in increasing index order
    const indexList = toRemove.constSlice();
    // So we iterate it backward in order to avoid indices being invalidated
    if (indexList.len > 0) {
        var i: usize = indexList.len - 1;
        while (i >= 0) {
            _ = data._animatedAtoms.swapRemove(indexList[i]);
            if (i == 0) {
                break;
            } else {
                i -= 1;
            }
        }
    }
    data._animatedAtomsLength.set(data._animatedAtoms.items.len);
}

pub fn runEventLoop() void {
    while (true) {
        if (!stepEventLoop(.Blocking)) {
            break;
        }
    }
}

test {
    _ = @import("fuzz.zig"); // testing the fuzzing library
    std.testing.refAllDeclsRecursive(@This());
    _ = @import("components/Alignment.zig");
}
