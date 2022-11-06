const std = @import("std");

pub const client = @import("client.zig");
// pub const server = @import("server.zig");

comptime {
    std.testing.refAllDecls(@This());
}
