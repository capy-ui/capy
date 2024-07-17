const std = @import("std");
const lib = @import("../../main.zig");

const win32Backend = @import("win32.zig");
const zigwin32 = @import("zigwin32");
const win32 = zigwin32.everything;
const Monitor = @This();

var monitor_list: ?[]Monitor = null;

adapter_win32_name: [:0]const u16,
win32_name: [:0]const u16,
device_name: []const u8,
internal_name: ?[]const u8 = null,

pub fn getList() []Monitor {
    if (monitor_list) |list| {
        return list;
    } else {
        const allocator = lib.internal.lasting_allocator;
        var monitors = std.ArrayList(Monitor).init(allocator);
        defer monitors.deinit();

        var adapters = std.ArrayList([:0]const u16).init(allocator);
        defer adapters.deinit();
        defer for (adapters.items) |item| allocator.free(item);

        // List all adapters
        {
            var i: u32 = 0;
            var display_device = std.mem.zeroInit(
                win32.DISPLAY_DEVICEW,
                .{ .cb = @sizeOf(win32.DISPLAY_DEVICEW) },
            );
            while (win32.EnumDisplayDevicesW(null, i, &display_device, 0) != 0) : (i += 1) {
                if (display_device.StateFlags & win32.DISPLAY_DEVICE_ATTACHED_TO_DESKTOP != 0) {
                    const device_name: [:0]const u16 = std.mem.span(@as([*:0]u16, @ptrCast(&display_device.DeviceName)));
                    const cloned_device_name = allocator.dupeZ(u16, device_name) catch unreachable;
                    adapters.append(cloned_device_name) catch unreachable;
                }
            }
        }

        var monitor_names = std.ArrayList(struct {
            adapter: [:0]const u16,
            monitor_name: [:0]const u16,
            monitor_friendly_name: []const u8,
        }).init(allocator);
        defer monitor_names.deinit();
        defer for (monitor_names.items) |item| {
            allocator.free(item.monitor_name);
            allocator.free(item.monitor_friendly_name);
        };

        // List all monitor names
        {
            var display_device = std.mem.zeroInit(
                win32.DISPLAY_DEVICEW,
                .{ .cb = @sizeOf(win32.DISPLAY_DEVICEW) },
            );
            for (adapters.items) |adapter| {
                var i: u32 = 0;
                while (win32.EnumDisplayDevicesW(adapter, i, &display_device, 0) != 0) : (i += 1) {
                    const device_name: [:0]const u16 = std.mem.span(@as([*:0]u16, @ptrCast(&display_device.DeviceName)));
                    const cloned_device_name = allocator.dupeZ(u16, device_name) catch unreachable;
                    const device_string: [:0]const u16 = std.mem.span(@as([*:0]u16, @ptrCast(&display_device.DeviceString)));
                    const cloned_device_string = std.unicode.utf16LeToUtf8Alloc(allocator, device_string) catch unreachable;
                    monitor_names.append(.{ .adapter = adapter, .monitor_name = cloned_device_name, .monitor_friendly_name = cloned_device_string }) catch unreachable;
                }
            }
        }

        for (monitor_names.items) |name| {
            monitors.append(Monitor{
                .adapter_win32_name = allocator.dupeZ(u16, name.adapter) catch unreachable,
                .win32_name = allocator.dupeZ(u16, name.monitor_name) catch unreachable,
                .device_name = allocator.dupe(u8, name.monitor_friendly_name) catch unreachable,
            }) catch unreachable;
        }

        monitor_list = monitors.toOwnedSlice() catch unreachable;
        return monitor_list.?;
    }
}

pub fn getName(self: *Monitor) []const u8 {
    return self.device_name;
}

pub fn getInternalName(self: *Monitor) []const u8 {
    if (self.internal_name) |name| {
        return name;
    } else {
        self.internal_name = std.unicode.utf16leToUtf8Alloc(lib.internal.lasting_allocator, self.win32_name);
        return self.internal_name.?;
    }
}

pub fn getX(self: *Monitor) u32 {
    var dev_mode: win32.DEVMODEW = undefined;
    std.debug.assert(win32.EnumDisplaySettingsExW(self.adapter_win32_name, win32.ENUM_CURRENT_SETTINGS, &dev_mode, 0) != 0);
    return @intCast(dev_mode.Anonymous1.Anonymous2.dmPosition.x);
}

pub fn getY(self: *Monitor) u32 {
    var dev_mode: win32.DEVMODEW = undefined;
    std.debug.assert(win32.EnumDisplaySettingsExW(self.adapter_win32_name, win32.ENUM_CURRENT_SETTINGS, &dev_mode, 0) != 0);
    return @intCast(dev_mode.Anonymous1.Anonymous2.dmPosition.y);
}

pub fn getWidth(self: *Monitor) u32 {
    var dev_mode: win32.DEVMODEW = undefined;
    std.debug.assert(win32.EnumDisplaySettingsW(self.adapter_win32_name, win32.ENUM_CURRENT_SETTINGS, &dev_mode) != 0);
    return @intCast(dev_mode.dmPelsWidth);
}

pub fn getHeight(self: *Monitor) u32 {
    var dev_mode: win32.DEVMODEW = undefined;
    std.debug.assert(win32.EnumDisplaySettingsW(self.adapter_win32_name, win32.ENUM_CURRENT_SETTINGS, &dev_mode) != 0);
    return @intCast(dev_mode.dmPelsHeight);
}

pub fn getRefreshRateMillihertz(self: *Monitor) u32 {
    var dev_mode: win32.DEVMODEW = undefined;
    std.debug.assert(win32.EnumDisplaySettingsW(self.adapter_win32_name, win32.ENUM_CURRENT_SETTINGS, &dev_mode) != 0);
    return @intCast(dev_mode.dmDisplayFrequency * 1000);
}

pub fn getHmonitor(self: *Monitor) win32.HMONITOR {
    var rect = win32.RECT{
        .left = @intCast(self.getX()),
        .top = @intCast(self.getY()),
        .right = @intCast(self.getX() + self.getWidth()),
        .bottom = @intCast(self.getY() + self.getHeight()),
    };
    return win32.MonitorFromRect(&rect, .NULL).?;
}

pub fn getDpi(self: *Monitor) u32 {
    // From https://stackoverflow.com/a/76402250. This method should work on Windows 11
    // TODO: runtime version detection?
    const supports_dpi_per_monitor = @import("builtin").os.isAtLeast(.windows, .win8_1) orelse true;
    if (supports_dpi_per_monitor) {
        var dpiX: u32 = undefined;
        var dpiY: u32 = undefined;
        std.debug.assert(win32.GetDpiForMonitor(self.getHmonitor(), .EFFECTIVE_DPI, &dpiX, &dpiY) == win32.S_OK);
        // dpiX and dpiY should be the same according to Microsoft's documentation. So we can ignore dpiY.
        return dpiX;
    } else {
        std.log.scoped(.win32).warn("cannot get DPI of connected screens!");
        return 96;
    }
}

pub fn getNumberOfVideoModes(self: *Monitor) usize {
    var count: u32 = 0;
    var dev_mode: win32.DEVMODEW = std.mem.zeroInit(win32.DEVMODEW, .{ .dmSize = @sizeOf(win32.DEVMODEW) });
    while (win32.EnumDisplaySettingsW(self.adapter_win32_name, @enumFromInt(count), &dev_mode) != 0) {
        count += 1;
    }
    return count;
}

pub fn getVideoMode(self: *Monitor, index: usize) lib.VideoMode {
    var dev_mode: win32.DEVMODEW = std.mem.zeroInit(win32.DEVMODEW, .{ .dmSize = @sizeOf(win32.DEVMODEW) });
    std.debug.assert(win32.EnumDisplaySettingsW(self.adapter_win32_name, @enumFromInt(index), &dev_mode) != 0);
    return .{
        .width = @intCast(dev_mode.dmPelsWidth),
        .height = @intCast(dev_mode.dmPelsHeight),
        .refresh_rate_millihertz = @intCast(dev_mode.dmDisplayFrequency * 10000),
        .bit_depth = @intCast(dev_mode.dmBitsPerPel),
    };
}

pub fn deinit(self: *Monitor) void {
    if (self.internal_name) |name| {
        lib.internal.lasting_allocator.free(name);
    }
    lib.internal.lasting_allocator.free(self.adapter_win32_name);
    lib.internal.lasting_allocator.free(self.win32_name);
}
