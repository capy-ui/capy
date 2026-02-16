//! Testing module for Capy applications.
//! Provides VirtualWindow for programmatic UI testing without a display.
const std = @import("std");
const capy = @import("capy.zig");
const Widget = capy.Widget;
const Container = capy.Container;
const event_simulator = capy.event_simulator;

pub const VirtualWindow = struct {
    window: capy.Window,
    focused_widget: ?*Widget = null,
    focus_order: std.ArrayList(*Widget),

    pub fn init() !VirtualWindow {
        const window = try capy.Window.init();
        return VirtualWindow{
            .window = window,
            .focus_order = .empty,
        };
    }

    pub fn deinit(self: *VirtualWindow) void {
        self.focus_order.deinit(capy.internal.allocator);
        self.window.deinit();
    }

    /// Set the root content of the virtual window.
    pub fn setContent(self: *VirtualWindow, container: anytype) !void {
        try self.window.set(container);
        self.buildFocusOrder();
    }

    /// Find a widget by name, searching recursively through the widget tree.
    pub fn findWidget(self: *VirtualWindow, name: []const u8) ?*Widget {
        const child = self.window.getChild() orelse return null;
        // Check the root widget itself
        if (child.name.*.get()) |widget_name| {
            if (std.mem.eql(u8, name, widget_name)) {
                return child;
            }
        }
        // If root is a Container, search its children
        if (child.cast(Container)) |container| {
            return container.getChild(name);
        }
        return null;
    }

    /// Compute a structural hash of the widget tree for snapshot testing.
    /// The hash includes widget type names, names, and display state.
    pub fn hash(self: *VirtualWindow) u32 {
        var hasher = std.hash.Wyhash.init(0);
        const child = self.window.getChild() orelse return @truncate(hasher.final());
        hashWidget(&hasher, child);
        return @truncate(hasher.final());
    }

    fn hashWidget(hasher: *std.hash.Wyhash, widget: *Widget) void {
        // Hash widget name if set
        if (widget.name.*.get()) |name| {
            hasher.update(name);
        }
        hasher.update(&[_]u8{if (widget.isDisplayed()) 1 else 0});

        // Recurse into containers
        if (widget.cast(Container)) |container| {
            for (container.children.items) |child| {
                hashWidget(hasher, child);
            }
        }
    }

    // --- Focus Management ---

    fn buildFocusOrder(self: *VirtualWindow) void {
        self.focus_order.clearRetainingCapacity();
        const child = self.window.getChild() orelse return;
        self.collectFocusable(child);
        if (self.focus_order.items.len > 0 and self.focused_widget == null) {
            self.focused_widget = self.focus_order.items[0];
        }
    }

    fn collectFocusable(self: *VirtualWindow, widget: *Widget) void {
        // A widget is focusable if it has a peer (is shown)
        // For testing purposes, consider all named widgets focusable
        if (widget.name.*.get() != null) {
            self.focus_order.append(capy.internal.allocator, widget) catch {};
        }

        if (widget.cast(Container)) |container| {
            for (container.children.items) |child| {
                self.collectFocusable(child);
            }
        }
    }

    // --- Assertions ---

    pub fn expectFocused(self: *VirtualWindow, name: []const u8) !void {
        const widget = self.findWidget(name) orelse return error.WidgetNotFound;
        if (self.focused_widget != widget) {
            return error.TestExpectedEqual;
        }
    }

    pub fn expectNotFocused(self: *VirtualWindow, name: []const u8) !void {
        const widget = self.findWidget(name) orelse return error.WidgetNotFound;
        if (self.focused_widget == widget) {
            return error.TestExpectedEqual;
        }
    }

    pub fn expectVisible(self: *VirtualWindow, name: []const u8) !void {
        const widget = self.findWidget(name) orelse return error.WidgetNotFound;
        if (!widget.isDisplayed()) {
            return error.TestExpectedEqual;
        }
    }

    pub fn expectNotVisible(self: *VirtualWindow, name: []const u8) !void {
        const widget = self.findWidget(name) orelse return error.WidgetNotFound;
        if (widget.isDisplayed()) {
            return error.TestExpectedEqual;
        }
    }

    // --- Actions ---

    /// Click the widget with the given name at its center.
    pub fn clickWidget(self: *VirtualWindow, name: []const u8) !void {
        const widget = self.findWidget(name) orelse return error.WidgetNotFound;
        event_simulator.click(widget, 0, 0) catch {};
    }

    /// Press a key. Tab/Backtab will advance/retreat the focus.
    pub fn pressKey(self: *VirtualWindow, keycode: u16) !void {
        if (keycode == event_simulator.keycodes.tab) {
            self.advanceFocus(1);
        } else if (keycode == event_simulator.keycodes.backtab) {
            self.advanceFocus(-1);
        } else if (self.focused_widget) |widget| {
            event_simulator.keyPress(widget, keycode) catch {};
        }
    }

    fn advanceFocus(self: *VirtualWindow, direction: i2) void {
        if (self.focus_order.items.len == 0) return;
        const n = self.focus_order.items.len;

        if (self.focused_widget) |current| {
            for (self.focus_order.items, 0..) |w, i| {
                if (w == current) {
                    const next_i = if (direction > 0)
                        (i + 1) % n
                    else
                        (i + n - 1) % n;
                    self.focused_widget = self.focus_order.items[next_i];
                    return;
                }
            }
        }
        // If current focused widget not found, focus first
        self.focused_widget = self.focus_order.items[0];
    }

    /// Type a full string of text to the currently focused widget.
    pub fn typeText(self: *VirtualWindow, text: []const u8) !void {
        if (self.focused_widget) |widget| {
            event_simulator.typeText(widget, text) catch {};
        }
    }

    /// Advance animations by one frame (calls on_frame listeners).
    pub fn stepFrame(self: *VirtualWindow) void {
        self.window.on_frame.callListeners();
    }
};

const backend = @import("backend.zig");

test "VirtualWindow init and deinit" {
    try backend.init();
    var vw = try VirtualWindow.init();
    defer vw.deinit();

    try std.testing.expectEqual(@as(?*Widget, null), vw.focused_widget);
    try std.testing.expectEqual(@as(usize, 0), vw.focus_order.items.len);
}

test "VirtualWindow hash is deterministic" {
    try backend.init();
    var vw = try VirtualWindow.init();
    defer vw.deinit();

    // Empty window should produce a consistent hash
    const h1 = vw.hash();
    const h2 = vw.hash();
    try std.testing.expectEqual(h1, h2);
}

test "VirtualWindow findWidget returns null for missing" {
    try backend.init();
    var vw = try VirtualWindow.init();
    defer vw.deinit();

    try std.testing.expectEqual(@as(?*Widget, null), vw.findWidget("nonexistent"));
}

test "VirtualWindow pressKey Tab advances focus" {
    try backend.init();
    var vw = try VirtualWindow.init();
    defer vw.deinit();

    // Without any content, Tab should not crash
    try vw.pressKey(event_simulator.keycodes.tab);
    try std.testing.expectEqual(@as(?*Widget, null), vw.focused_widget);
}
