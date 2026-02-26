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

pub fn getName(self: *const Monitor) []const u8 {
    _ = self;
    return "Unknown Monitor";
}

pub fn getInternalName(self: *const Monitor) []const u8 {
    _ = self;
    return "unknown";
}

pub fn getRefreshRateMillihertz(self: *const Monitor) u32 {
    _ = self;
    return 60000;
}

pub fn getDpi(self: *const Monitor) u32 {
    _ = self;
    return 96;
}

pub fn getWidth(self: *const Monitor) u32 {
    _ = self;
    return 0;
}

pub fn getHeight(self: *const Monitor) u32 {
    _ = self;
    return 0;
}

pub fn deinitAllPeers() void {}
