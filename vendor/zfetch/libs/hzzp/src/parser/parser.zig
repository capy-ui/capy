const std = @import("std");

pub const request = @import("request.zig");
pub const response = @import("response.zig");

comptime {
    std.testing.refAllDecls(@This());
}
