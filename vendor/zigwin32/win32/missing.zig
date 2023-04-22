//! Includes definitions that are currently missing from win32metadata

const win32 = @import("../win32.zig");

// NOTE: all previous missing types have been removed, this is now a placeholder
//       to put new missing types should they come up in the future

const std = @import("std");
test {
    std.testing.refAllDecls(@This());
}
