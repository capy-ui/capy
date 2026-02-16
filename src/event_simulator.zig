const std = @import("std");
const backend = @import("backend.zig");
const shared = @import("backends/shared.zig");
const Widget = @import("widget.zig").Widget;

pub const MouseButton = shared.MouseButton;

pub const Error = error{ NoPeer, NotImplemented };

// --- Convenience keycode constants ---
pub const keycodes = struct {
    pub const tab: u16 = 0x09;
    pub const backtab: u16 = 0x19;
    pub const space: u16 = 0x20;
    pub const @"return": u16 = 0x0D;
    pub const enter: u16 = 0x03;
    pub const escape: u16 = 0x1B;
    // macOS hardware keycodes for modifiers
    pub const shift: u16 = 56;
    pub const command: u16 = 55;
    pub const option: u16 = 58;
    pub const control: u16 = 59;
    // Arrow keys (macOS unicode values)
    pub const arrow_up: u16 = 0xF700;
    pub const arrow_down: u16 = 0xF701;
    pub const arrow_left: u16 = 0xF702;
    pub const arrow_right: u16 = 0xF703;
};

// ============================================================
// Internal: get EventUserData from a Widget
// ============================================================
fn getEventData(widget: *Widget) Error!*backend.EventUserData {
    const peer = widget.peer orelse return Error.NoPeer;
    return backend.getEventUserData(peer);
}

// ============================================================
// Component-level event injection
// ============================================================

/// Simulate a left click at (x, y)
pub fn click(widget: *Widget, x: i32, y: i32) Error!void {
    return clickButton(widget, .Left, x, y);
}

/// Simulate a click with a specific button
pub fn clickButton(widget: *Widget, button: MouseButton, x: i32, y: i32) Error!void {
    const data = try getEventData(widget);
    const class_data = @intFromPtr(data);
    const user_data = data.userdata;
    // Press
    if (data.class.mouseButtonHandler) |h| h(button, true, x, y, class_data);
    if (data.user.mouseButtonHandler) |h| h(button, true, x, y, user_data);
    // Release
    if (data.class.mouseButtonHandler) |h| h(button, false, x, y, class_data);
    if (data.user.mouseButtonHandler) |h| h(button, false, x, y, user_data);
    // Click callback (for buttons)
    if (data.class.clickHandler) |h| h(class_data);
    if (data.user.clickHandler) |h| h(user_data);
}

/// Simulate a double-click at (x, y)
pub fn doubleClick(widget: *Widget, x: i32, y: i32) Error!void {
    try click(widget, x, y);
    try click(widget, x, y);
}

/// Simulate a right-click at (x, y)
pub fn rightClick(widget: *Widget, x: i32, y: i32) Error!void {
    return clickButton(widget, .Right, x, y);
}

/// Press a mouse button (without releasing)
pub fn mouseDown(widget: *Widget, button: MouseButton, x: i32, y: i32) Error!void {
    const data = try getEventData(widget);
    if (data.class.mouseButtonHandler) |h| h(button, true, x, y, @intFromPtr(data));
    if (data.user.mouseButtonHandler) |h| h(button, true, x, y, data.userdata);
}

/// Release a mouse button
pub fn mouseUp(widget: *Widget, button: MouseButton, x: i32, y: i32) Error!void {
    const data = try getEventData(widget);
    if (data.class.mouseButtonHandler) |h| h(button, false, x, y, @intFromPtr(data));
    if (data.user.mouseButtonHandler) |h| h(button, false, x, y, data.userdata);
}

/// Move mouse to (x, y)
pub fn mouseMove(widget: *Widget, x: i32, y: i32) Error!void {
    const data = try getEventData(widget);
    if (data.class.mouseMotionHandler) |h| h(x, y, @intFromPtr(data));
    if (data.user.mouseMotionHandler) |h| h(x, y, data.userdata);
}

/// Drag from (x1,y1) to (x2,y2) with left button, with `steps` intermediate moves
pub fn drag(widget: *Widget, x1: i32, y1: i32, x2: i32, y2: i32, steps: u32) Error!void {
    try mouseDown(widget, .Left, x1, y1);
    const n = if (steps == 0) 1 else steps;
    var i: u32 = 1;
    while (i <= n) : (i += 1) {
        const t_x = x1 + @divTrunc((x2 - x1) * @as(i32, @intCast(i)), @as(i32, @intCast(n)));
        const t_y = y1 + @divTrunc((y2 - y1) * @as(i32, @intCast(i)), @as(i32, @intCast(n)));
        try mouseMove(widget, t_x, t_y);
    }
    try mouseUp(widget, .Left, x2, y2);
}

/// Scroll by (dx, dy)
pub fn scroll(widget: *Widget, dx: f32, dy: f32) Error!void {
    const data = try getEventData(widget);
    if (data.class.scrollHandler) |h| h(dx, dy, @intFromPtr(data));
    if (data.user.scrollHandler) |h| h(dx, dy, data.userdata);
}

/// Simulate a key press (hardware keycode)
pub fn keyPress(widget: *Widget, keycode: u16) Error!void {
    const data = try getEventData(widget);
    if (data.class.keyPressHandler) |h| h(keycode, @intFromPtr(data));
    if (data.user.keyPressHandler) |h| h(keycode, data.userdata);
}

/// Simulate a key down (alias for keyPress)
pub fn keyDown(widget: *Widget, keycode: u16) Error!void {
    return keyPress(widget, keycode);
}

/// Simulate a key release (hardware keycode)
pub fn keyUp(widget: *Widget, keycode: u16) Error!void {
    const data = try getEventData(widget);
    if (data.class.keyReleaseHandler) |h| h(keycode, @intFromPtr(data));
    if (data.user.keyReleaseHandler) |h| h(keycode, data.userdata);
}

/// Simulate typing a character/string
pub fn keyType(widget: *Widget, str: []const u8) Error!void {
    const data = try getEventData(widget);
    if (data.class.keyTypeHandler) |h| h(str, @intFromPtr(data));
    if (data.user.keyTypeHandler) |h| h(str, data.userdata);
}

/// Type a full string, one character at a time
pub fn typeText(widget: *Widget, text: []const u8) Error!void {
    var i: usize = 0;
    while (i < text.len) {
        const len = std.unicode.utf8ByteSequenceLength(text[i]) catch 1;
        try keyType(widget, text[i..][0..len]);
        i += len;
    }
}

/// Fire the TextChanged handler chain (simulates native text change notification).
/// Caller must set the backend peer's text first (that part is widget-type-specific).
pub fn fireTextChanged(widget: *Widget) Error!void {
    const data = try getEventData(widget);
    if (data.class.changedTextHandler) |h| h(@intFromPtr(data));
    if (data.user.changedTextHandler) |h| h(data.userdata);
}

// ============================================================
// Native-level stubs (future implementation)
// ============================================================

pub fn native_click(_: *Widget, _: i32, _: i32) Error!void {
    return Error.NotImplemented;
}

pub fn native_doubleClick(_: *Widget, _: i32, _: i32) Error!void {
    return Error.NotImplemented;
}

pub fn native_rightClick(_: *Widget, _: i32, _: i32) Error!void {
    return Error.NotImplemented;
}

pub fn native_mouseDown(_: *Widget, _: MouseButton, _: i32, _: i32) Error!void {
    return Error.NotImplemented;
}

pub fn native_mouseUp(_: *Widget, _: MouseButton, _: i32, _: i32) Error!void {
    return Error.NotImplemented;
}

pub fn native_mouseMove(_: *Widget, _: i32, _: i32) Error!void {
    return Error.NotImplemented;
}

pub fn native_drag(_: *Widget, _: i32, _: i32, _: i32, _: i32, _: u32) Error!void {
    return Error.NotImplemented;
}

pub fn native_scroll(_: *Widget, _: f32, _: f32) Error!void {
    return Error.NotImplemented;
}

pub fn native_keyPress(_: *Widget, _: u16) Error!void {
    return Error.NotImplemented;
}

pub fn native_keyDown(_: *Widget, _: u16) Error!void {
    return Error.NotImplemented;
}

pub fn native_keyUp(_: *Widget, _: u16) Error!void {
    return Error.NotImplemented;
}

pub fn native_keyType(_: *Widget, _: []const u8) Error!void {
    return Error.NotImplemented;
}

pub fn native_typeText(_: *Widget, _: []const u8) Error!void {
    return Error.NotImplemented;
}

// ============================================================
// Integration tests: component-level event simulation
// ============================================================

test "TextField text input updates atom" {
    const TextField = @import("components/TextField.zig").TextField;

    try backend.init();
    var field = TextField.alloc(.{ .text = "Ada" });
    defer {
        // Free the owned text buffer that textChanged allocates (not freed by generic deinit)
        if (field.text_alloc) |ta| std.testing.allocator.free(ta);
        field.deinit();
    }
    try field.show();
    // Wire the Widget.peer so getEventData can find the native peer
    field.widget_data.widget.peer = field.peer.?.peer;

    // Verify initial state
    try std.testing.expectEqualStrings("Ada", field.text.get());

    // Simulate: OS changes the native text, then fires the changed notification
    field.peer.?.setText("Peter");
    try fireTextChanged(field.asWidget());

    // The atom should now reflect the native change
    try std.testing.expectEqualStrings("Peter", field.text.get());
}

test "CheckBox click toggles checked atom" {
    const CheckBox = @import("components/CheckBox.zig").CheckBox;

    try backend.init();
    var checkbox = CheckBox.alloc(.{});
    defer checkbox.deinit();
    try checkbox.show();
    checkbox.widget_data.widget.peer = checkbox.peer.?.peer;

    // Verify initial state: unchecked
    try std.testing.expect(!checkbox.checked.get());

    // Simulate: OS toggles the native check state, then fires click
    checkbox.peer.?.setChecked(true);
    try click(checkbox.asWidget(), 0, 0);

    // The atom should now reflect the native change
    try std.testing.expect(checkbox.checked.get());
}

test "addKeyReleaseHandler fires on simulated keyUp" {
    const TextField = @import("components/TextField.zig").TextField;

    try backend.init();
    var field = TextField.alloc(.{});
    defer field.deinit();
    try field.show();
    field.widget_data.widget.peer = field.peer.?.peer;

    // Track handler invocation via mutable statics
    const State = struct {
        var called: bool = false;
        var received_keycode: u16 = 0;
    };
    State.called = false;
    State.received_keycode = 0;

    try field.addKeyReleaseHandler(&struct {
        fn handler(_: *anyopaque, kc: u16) anyerror!void {
            State.called = true;
            State.received_keycode = kc;
        }
    }.handler);

    // Simulate a key release via the event simulator
    try keyUp(field.asWidget(), keycodes.space);

    try std.testing.expect(State.called);
    try std.testing.expectEqual(keycodes.space, State.received_keycode);
}
