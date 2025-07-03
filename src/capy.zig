const std = @import("std");

pub const Window = @import("window.zig").Window;
pub const Widget = @import("widget.zig").Widget;

// Components
pub const Alignment = @import("components/Alignment.zig").Alignment;
pub const alignment = @import("components/Alignment.zig").alignment;

pub const Button = @import("components/Button.zig").Button;
pub const button = @import("components/Button.zig").button;

pub const Canvas = @import("components/Canvas.zig").Canvas;
pub const canvas = @import("components/Canvas.zig").canvas;
pub const DrawContext = Canvas.DrawContext;
pub const Rect = @import("components/Canvas.zig").Rect;
pub const rect = @import("components/Canvas.zig").rect;

pub const CheckBox = @import("components/CheckBox.zig").CheckBox;
pub const checkBox = @import("components/CheckBox.zig").checkBox;

pub const Dropdown = @import("components/Dropdown.zig").Dropdown;
pub const dropdown = @import("components/Dropdown.zig").dropdown;

pub const Image = @import("components/Image.zig").Image;
pub const image = @import("components/Image.zig").image;

pub const Label = @import("components/Label.zig").Label;
pub const label = @import("components/Label.zig").label;
pub const spacing = @import("components/Label.zig").spacing;

pub const MenuItem = @import("components/Menu.zig").MenuItem;
pub const menu = @import("components/Menu.zig").menu;
pub const menuItem = @import("components/Menu.zig").menuItem;
pub const MenuBar = @import("components/Menu.zig").MenuBar;
pub const menuBar = @import("components/Menu.zig").menuBar;

pub const Navigation = @import("components/Navigation.zig").Navigation;
pub const navigation = @import("components/Navigation.zig").navigation;

pub const NavigationSidebar = @import("components/NavigationSidebar.zig").NavigationSidebar;
pub const navigationSidebar = @import("components/NavigationSidebar.zig").navigationSidebar;

pub const Slider = @import("components/Slider.zig").Slider;
pub const slider = @import("components/Slider.zig").slider;
pub const Orientation = @import("components/Slider.zig").Orientation;

pub const Scrollable = @import("components/Scrollable.zig").Scrollable;
pub const scrollable = @import("components/Scrollable.zig").scrollable;

pub const Tabs = @import("components/Tabs.zig").Tabs;
pub const tabs = @import("components/Tabs.zig").tabs;
pub const Tab = @import("components/Tabs.zig").Tab;
pub const tab = @import("components/Tabs.zig").tab;

pub const TextArea = @import("components/TextArea.zig").TextArea;
pub const textArea = @import("components/TextArea.zig").textArea;

pub const TextField = @import("components/TextField.zig").TextField;
pub const textField = @import("components/TextField.zig").textField;

// Misc.
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

const misc = @import("misc.zig");
pub const TextLayout = misc.TextLayout;
pub const Font = misc.Font;
pub const TextAlignment = misc.TextAlignment;

pub const internal = @import("internal.zig");
pub const backend = @import("backend.zig");
pub const http = @import("http.zig");
pub const dev_tools = @import("dev_tools.zig");
pub const audio = @import("audio.zig");

pub const allocator = internal.allocator;

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

    if (eventStep.hasEnabledListeners()) {
        // TODO: don't do that and instead encourage to use something like Window.vsync
        return backend.runStep(.Asynchronous);
    }
    return backend.runStep(stepType);
}

var eventStepInstance: EventSource = EventSource.init(internal.allocator);
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
