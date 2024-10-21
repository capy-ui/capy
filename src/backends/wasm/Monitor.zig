//! For now, this implementation returns a dummy monitor.

// This implementation will use the Window Management API, whenever it's available.
// Otherwise, it will return a dummy monitor that has the size of the browser window.
const std = @import("std");
const lib = @import("../../capy.zig");
const Monitor = @This();

var monitor_list: ?[]Monitor = null;

// peer: *c.GdkMonitor,
// internal_name: ?[]const u8 = null,

pub fn getList() []Monitor {
    if (monitor_list) |list| {
        return list;
    } else {
        // TODO: proper monitor detection
        const n = 1;
        const list = lib.internal.lasting_allocator.alloc(Monitor, n) catch @panic("OOM");
        list[0] = .{};
        monitor_list = list;
        return list;
    }
}

pub fn deinitAllPeers() void {
    if (monitor_list) |list| {
        for (list) |*monitor| monitor.deinit();
        lib.internal.lasting_allocator.free(list);
        monitor_list = null;
    }
}

pub fn getName(self: *Monitor) []const u8 {
    _ = self;
    return "Dummy Monitor";
}

pub fn getInternalName(self: *Monitor) []const u8 {
    _ = self;
    return "Dummy Monitor";
}

pub fn getWidth(self: *Monitor) u32 {
    _ = self;
    return 1920;
}

pub fn getHeight(self: *Monitor) u32 {
    _ = self;
    return 1080;
}

pub fn getRefreshRateMillihertz(self: *Monitor) u32 {
    _ = self;
    return 60000;
}

pub fn getDpi(self: *Monitor) u32 {
    _ = self;
    return 72;
}

pub fn getNumberOfVideoModes(self: *Monitor) usize {
    _ = self;
    return 1;
}

pub fn getVideoMode(self: *Monitor, index: usize) lib.VideoMode {
    _ = index;
    return .{
        .width = self.getWidth(),
        .height = self.getHeight(),
        .refresh_rate_millihertz = self.getRefreshRateMillihertz(),
        .bit_depth = 32,
    };
}

pub fn deinit(self: *Monitor) void {
    _ = self;
}
