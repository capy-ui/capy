const std = @import("std");

const OutputStreamConfig = @import("audio.zig").OutputStreamConfig;
const StreamLayout = @import("audio.zig").StreamLayout;

pub const Dummy = struct {
    pub fn getOutputStream(allocator: std.mem.Allocator, config: OutputStreamConfig ) !OutputStream {
        _ = allocator;
        _ = config;
        return error.Unimplemented;
    }

    pub const OutputStream = struct {
        pub fn stop(_: *@This()) void {}
        pub fn deinit(_: *@This()) void {}
        pub fn start(_: *@This()) !void{}
    };
};
