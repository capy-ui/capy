//! This file contains declarations shared between all backends. Most of those
//! shared declarations are enums and error sets.
const std = @import("std");
const capy = @import("../capy.zig");

pub const BackendEventType = enum {
    Click,
    Draw,
    MouseButton,
    MouseMotion,
    Scroll,
    TextChanged,
    Resize,
    /// This corresponds to a character being typed (e.g. Shift+e = 'E')
    KeyType,
    /// This corresponds to a key being pressed (e.g. Shift)
    KeyPress,
    PropertyChange,
};

pub const MouseButton = enum(c_uint) {
    Left,
    Middle,
    Right,
    _,

    /// Returns the ID of the pressed or released finger or null if it is a mouse.
    pub fn getFingerId(self: MouseButton) ?u8 {
        _ = self;
        return null;
    }
};

pub fn EventFunctions(comptime Backend: type) type {
    // TODO: remove Backend parameter
    _ = Backend;
    return struct {
        /// Only works for buttons
        clickHandler: ?*const fn (data: usize) void = null,
        mouseButtonHandler: ?*const fn (button: MouseButton, pressed: bool, x: i32, y: i32, data: usize) void = null,
        // TODO: Mouse object with pressed buttons and more data
        mouseMotionHandler: ?*const fn (x: i32, y: i32, data: usize) void = null,
        keyTypeHandler: ?*const fn (str: []const u8, data: usize) void = null,
        keyPressHandler: ?*const fn (hardwareKeycode: u16, data: usize) void = null,
        // TODO: dx and dy are in pixels, not in lines
        scrollHandler: ?*const fn (dx: f32, dy: f32, data: usize) void = null,
        resizeHandler: ?*const fn (width: u32, height: u32, data: usize) void = null,
        /// Only works for canvas (althought technically it isn't required to)
        drawHandler: ?*const fn (ctx: *@import("../backend.zig").DrawContext, data: usize) void = null,
        changedTextHandler: ?*const fn (data: usize) void = null,
        propertyChangeHandler: ?*const fn (name: []const u8, value: *const anyopaque, data: usize) void = null,
    };
}

pub const EventLoopStep = enum { Blocking, Asynchronous };

pub const MessageType = enum { Information, Warning, Error };

pub const BackendError = error{ UnknownError, InitializationError } || std.mem.Allocator.Error;

pub const LinearGradient = struct {
    x0: f32,
    y0: f32,
    x1: f32,
    y1: f32,
    stops: []const Stop,

    pub const Stop = struct {
        offset: f32,
        color: capy.Color,
    };
};
