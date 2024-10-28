const lib = @import("../../capy.zig");

const Monitor = @This();

var monitor_list: [0]Monitor = .{};

pub fn getList() []Monitor {
    return &monitor_list;
}

pub fn getNumberOfVideoModes(self: *Monitor) usize {
    _ = self;
    return 0;
}

pub fn getVideoMode(self: *Monitor, index: usize) lib.VideoMode {
    _ = self;
    _ = index;
    return .{
        .width = 0,
        .height = 0,
        .refresh_rate_millihertz = 0,
        .bit_depth = 0,
    };
}

pub fn deinitAllPeers() void {}
