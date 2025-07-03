const std = @import("std");
const lib = @import("../../capy.zig");

const win32Backend = @import("win32.zig");
const zigwin32 = @import("zigwin32");
const win32 = zigwin32.everything;
const Events = @import("backend.zig").Events;
const getEventUserData = @import("backend.zig").getEventUserData;
const _T = zigwin32.zig._T;
const L = zigwin32.zig.L;

const Dropdown = @This();

peer: win32.HWND,
arena: std.heap.ArenaAllocator,
owned_strings: ?[:null]const ?[*:0]const u16 = null,

pub usingnamespace Events(Dropdown);

pub fn create() !Dropdown {
    const hwnd = win32.CreateWindowExW(win32.WS_EX_LEFT, // dwExtStyle
        _T("COMBOBOX"), // lpClassName
        _T(""), // lpWindowName
        @as(win32.WINDOW_STYLE, @enumFromInt(@intFromEnum(win32.WS_TABSTOP) | @intFromEnum(win32.WS_CHILD) | @intFromEnum(win32.WS_BORDER) | win32.CBS_DROPDOWNLIST | win32.CBS_HASSTRINGS)), // dwStyle
        0, // X
        0, // Y
        100, // nWidth
        400, // nHeight
        @import("backend.zig").defaultWHWND, // hWindParent
        null, // hMenu
        @import("backend.zig").hInst, // hInstance
        null // lpParam
    ) orelse return @import("backend.zig").Win32Error.InitializationError;
    try Dropdown.setupEvents(hwnd);
    _ = win32.SendMessageW(hwnd, win32.WM_SETFONT, @intFromPtr(@import("backend.zig").captionFont), 1);

    getEventUserData(hwnd).extra_height = 500;

    return Dropdown{ .peer = hwnd, .arena = std.heap.ArenaAllocator.init(lib.internal.allocator) };
}

pub fn getSelectedIndex(self: *const Dropdown) usize {
    const result = win32.SendMessageW(self.peer, win32.CB_GETCURSEL, 0, 0);
    return if (result != win32.CB_ERR) @intCast(result) else 0;
}

pub fn setSelectedIndex(self: *const Dropdown, index: usize) void {
    _ = win32.SendMessageW(self.peer, win32.CB_SETCURSEL, index, 0);
}

pub fn setValues(self: *Dropdown, values: []const []const u8) void {
    // Remove previous values
    const old_index = self.getSelectedIndex();
    _ = win32.SendMessageW(self.peer, win32.CB_RESETCONTENT, 0, 0);

    const allocator = lib.internal.allocator;
    if (self.owned_strings) |strings| {
        for (strings) |string| {
            allocator.free(std.mem.span(string.?));
        }
        allocator.free(strings);
    }

    const duplicated = allocator.allocSentinel(?[*:0]const u16, values.len, null) catch return;
    errdefer allocator.free(duplicated);
    for (values, 0..) |value, i| {
        const utf16 = std.unicode.utf8ToUtf16LeWithNull(allocator, value) catch return;
        duplicated[i] = utf16.ptr;
        std.debug.assert(win32.SendMessageW(self.peer, win32.CB_ADDSTRING, 0, @bitCast(@intFromPtr(utf16.ptr))) != win32.CB_ERR);
    }
    self.owned_strings = duplicated;
    self.setSelectedIndex(old_index);
}

pub fn setEnabled(self: *Dropdown, enabled: bool) void {
    _ = win32.EnableWindow(self.peer, @intFromBool(enabled));
}
