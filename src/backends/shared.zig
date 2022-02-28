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
    KeyType
};
// zig fmt: on

pub const EventLoopStep = enum { Blocking, Asynchronous };

pub const BackendError = error{ UnknownError, InitializationError } || std.mem.Allocator.Error;
