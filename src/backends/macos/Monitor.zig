const std = @import("std");
const objc = @import("objc");
const AppKit = @import("AppKit.zig");
const lib = @import("../../capy.zig");

const Monitor = @This();

var monitor_list: ?[]Monitor = null;

peer: objc.Object,
internal_name: ?[]const u8 = null,

pub fn getList() []Monitor {
    if (monitor_list) |list| return list;

    const NSScreen = objc.getClass("NSScreen") orelse return &[0]Monitor{};
    const screens = NSScreen.msgSend(objc.Object, "screens", .{});
    const count: usize = @intCast(screens.msgSend(u64, "count", .{}));
    if (count == 0) return &[0]Monitor{};

    const list = lib.internal.allocator.alloc(Monitor, count) catch @panic("OOM");
    for (0..count) |i| {
        const screen = screens.msgSend(objc.Object, "objectAtIndex:", .{@as(u64, @intCast(i))});
        list[i] = Monitor{ .peer = screen };
    }
    monitor_list = list;
    return list;
}

pub fn deinitAllPeers() void {
    if (monitor_list) |list| {
        for (list) |*monitor| monitor.deinitMonitor();
        lib.internal.allocator.free(list);
        monitor_list = null;
    }
}

pub fn getName(self: *const Monitor) []const u8 {
    const name_obj = self.peer.msgSend(objc.Object, "localizedName", .{});
    if (@intFromPtr(name_obj.value) == 0) return "Unknown Monitor";
    const cstr = name_obj.msgSend([*:0]const u8, "UTF8String", .{});
    return std.mem.sliceTo(cstr, 0);
}

pub fn getInternalName(self: *Monitor) []const u8 {
    if (self.internal_name) |n| return n;
    // Use the localized name as internal name on macOS
    const name = self.getName();
    self.internal_name = lib.internal.allocator.dupe(u8, name) catch @panic("OOM");
    return self.internal_name.?;
}

pub fn getWidth(self: *const Monitor) u32 {
    const frame = self.peer.msgSend(AppKit.CGRect, "frame", .{});
    const scale = self.peer.msgSend(AppKit.CGFloat, "backingScaleFactor", .{});
    return @intFromFloat(frame.size.width * scale);
}

pub fn getHeight(self: *const Monitor) u32 {
    const frame = self.peer.msgSend(AppKit.CGRect, "frame", .{});
    const scale = self.peer.msgSend(AppKit.CGFloat, "backingScaleFactor", .{});
    return @intFromFloat(frame.size.height * scale);
}

pub fn getRefreshRateMillihertz(self: *const Monitor) u32 {
    _ = self;
    // macOS doesn't expose refresh rate directly via NSScreen in a simple way.
    // Default to 60Hz. Could use CVDisplayLink for exact values.
    return 60000;
}

pub fn getDpi(self: *const Monitor) u32 {
    const scale = self.peer.msgSend(AppKit.CGFloat, "backingScaleFactor", .{});
    // Base DPI on macOS is 72, scaled by backing factor
    return @intFromFloat(72.0 * scale);
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

pub fn deinitMonitor(self: *Monitor) void {
    if (self.internal_name) |n| {
        lib.internal.allocator.free(n);
        self.internal_name = null;
    }
}
