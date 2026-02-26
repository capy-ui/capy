//! This is a temporary module made in wait for Zig's async API to stabilise and get better.
//! Currently stubbed out because Zig 0.15 removed anyframe and std.atomic.Queue.
//! TODO: Rewrite using std.Thread or other async primitives when needed.
const std = @import("std");
const internal = @import("internal.zig");
