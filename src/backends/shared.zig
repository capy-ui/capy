//! This file contains declarations shared between all backends. Most of those
//! shared declarations are enums and error sets.
const std = @import("std");

// zig fmt: off
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
    /// This corresponds to a key beign pressed (e.g. Shift)
    KeyPress,
};
// zig fmt: on

pub const EventLoopStep = enum { Blocking, Asynchronous };

pub const BackendError = error{ UnknownError, InitializationError } || std.mem.Allocator.Error;
