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

pub const RadioButton = @import("components/RadioButton.zig").RadioButton;
pub const radioButton = @import("components/RadioButton.zig").radioButton;

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

// Canvas-based widgets
pub const Divider = @import("components/Divider.zig").Divider;
pub const divider = @import("components/Divider.zig").divider;

pub const ProgressBar = @import("components/ProgressBar.zig").ProgressBar;
pub const progressBar = @import("components/ProgressBar.zig").progressBar;

pub const Spinner = @import("components/Spinner.zig").Spinner;
pub const spinner = @import("components/Spinner.zig").spinner;

pub const SegmentedControl = @import("components/SegmentedControl.zig").SegmentedControl;
pub const segmentedControl = @import("components/SegmentedControl.zig").segmentedControl;

pub const MenuButton = @import("components/MenuButton.zig").MenuButton;
pub const menuButton = @import("components/MenuButton.zig").menuButton;

pub const AlertDialog = @import("components/AlertDialog.zig").AlertDialog;
pub const alertDialog = @import("components/AlertDialog.zig").alertDialog;

pub const FlyoutPanel = @import("components/FlyoutPanel.zig").FlyoutPanel;
pub const flyoutPanel = @import("components/FlyoutPanel.zig").flyoutPanel;
pub const Edge = @import("components/FlyoutPanel.zig").Edge;

pub const ContextMenu = @import("components/ContextMenu.zig").ContextMenu;
pub const contextMenu = @import("components/ContextMenu.zig").contextMenu;
pub const ContextMenuItem = @import("components/ContextMenu.zig").ContextMenuItem;

pub const Table = @import("components/Table.zig").Table;
pub const table = @import("components/Table.zig").table;
pub const ColumnDef = @import("components/Table.zig").ColumnDef;
pub const CellProvider = @import("components/Table.zig").CellProvider;

// Overlay utilities
pub const overlay = @import("overlay.zig");

// Containers
const containers = @import("containers.zig");
pub const Layout = containers.Layout;
pub const ColumnLayout = containers.ColumnLayout;
pub const RowLayout = containers.RowLayout;
pub const MarginLayout = containers.MarginLayout;
pub const StackLayout = containers.StackLayout;
pub const GridLayout = containers.GridLayout;
pub const GridLayoutConfig = containers.GridLayoutConfig;
pub const Container = containers.Container;
pub const GridConfig = containers.GridConfig;
pub const grid = containers.grid;
pub const expanded = containers.expanded;
pub const stack = containers.stack;
pub const row = containers.row;
pub const column = containers.column;
pub const margin = containers.margin;

// Color
const color_mod = @import("color.zig");
pub const Colorspace = color_mod.Colorspace;
pub const Color = color_mod.Color;
pub const Colors = color_mod.Colors;

// Data
const data_mod = @import("data.zig");
pub const lerp = data_mod.lerp;
pub const Easing = data_mod.Easing;
pub const Easings = data_mod.Easings;
pub const isAtom = data_mod.isAtom;
pub const isListAtom = data_mod.isListAtom;
pub const Atom = data_mod.Atom;
pub const ListAtom = data_mod.ListAtom;
pub const FormattedAtom = data_mod.FormattedAtom;
pub const Position = data_mod.Position;
pub const Size = data_mod.Size;
pub const Rectangle = data_mod.Rectangle;

// Image data
const image_mod = @import("image.zig");
pub const ImageData = image_mod.ImageData;
pub const ScalableVectorData = image_mod.ScalableVectorData;

// List
const list_mod = @import("list.zig");
pub const GenericListModel = list_mod.GenericListModel;
pub const List = list_mod.List;
pub const columnList = list_mod.columnList;

// Timer
const timer_mod = @import("timer.zig");
pub const Timer = timer_mod.Timer;

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
pub const testing = @import("testing.zig");
pub const event_simulator = @import("event_simulator.zig");
pub const icon = @import("icon.zig");
pub const icon_embed = @import("icon_embed.zig");

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
pub const FileDialogOptions = @import("backends/shared.zig").FileDialogOptions;

/// Opens a native file/directory selection dialog.
/// Returns the selected path, or null if cancelled.
/// Caller owns returned memory (free with `capy.allocator.free(result)`).
pub const openFileDialog = backend.openFileDialog;
pub const isDarkMode = backend.isDarkMode;
pub const SystemColors = @import("system_colors.zig");

// This is a private global variable used for safety.
var isCapyInitialized: bool = false;
pub fn init() !void {
    try backend.init();
    if (ENABLE_DEV_TOOLS) {
        try dev_tools.init();
    }

    Monitors.init();

    var timerListener = eventStep.listen(.{ .callback = @import("timer.zig").handleTimersTick }) catch @panic("OOM");
    // The listener is enabled only if there is at least 1 timer is running
    timerListener.enabled.dependOn(.{&@import("timer.zig").runningTimers.length}, &struct {
        fn a(num: usize) bool {
            return num >= 1;
        }
    }.a) catch @panic("OOM");
    @import("state_logger.zig").init();
    isCapyInitialized = true;
}

pub fn deinit() void {
    isCapyInitialized = false;
    @import("state_logger.zig").deinit();
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
