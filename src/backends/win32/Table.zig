const std = @import("std");
const lib = @import("../../capy.zig");
const ColumnDef = @import("../../components/Table.zig").ColumnDef;

const win32Backend = @import("win32.zig");
const zigwin32 = @import("zigwin32");
const win32 = zigwin32.everything;
const Events = @import("backend.zig").Events;
const getEventUserData = @import("backend.zig").getEventUserData;
const L = zigwin32.zig.L;

const Table = @This();

peer: win32.HWND,
cell_provider: ?*const fn (row: usize, col: usize, buf: []u8) []const u8 = null,
row_count: usize = 0,
column_count: usize = 0,

const _events = Events(@This());
pub const process = _events.process;
pub const setupEvents = _events.setupEvents;
pub const setUserData = _events.setUserData;
pub const setCallback = _events.setCallback;
pub const requestDraw = _events.requestDraw;
pub const getWidth = _events.getWidth;
pub const getHeight = _events.getHeight;
pub const getPreferredSize = _events.getPreferredSize;

pub fn getPreferredSize_impl(self: *const Table) lib.Size {
    _ = self;
    return lib.Size.init(400, 300);
}
pub const setOpacity = _events.setOpacity;
pub const deinit = _events.deinit;

pub fn create() !Table {
    const hwnd = win32.CreateWindowExW(
        win32.WINDOW_EX_STYLE{}, // dwExtStyle
        @ptrCast(L("SysListView32")), // lpClassName
        L(""), // lpWindowName
        @as(win32.WINDOW_STYLE, @bitCast(@as(u32, @bitCast(win32.WINDOW_STYLE{
            .TABSTOP = 1,
            .CHILD = 1,
            .BORDER = 1,
            .VISIBLE = 1,
        })) | win32Backend.LVS_REPORT |
            win32Backend.LVS_SINGLESEL |
            win32Backend.LVS_SHOWSELALWAYS |
            win32Backend.LVS_OWNERDATA)), // dwStyle
        0, // X
        0, // Y
        400, // nWidth
        300, // nHeight
        @import("backend.zig").defaultWHWND, // hWindParent
        null, // hMenu
        @import("backend.zig").hInst, // hInstance
        null, // lpParam
    ) orelse return @import("backend.zig").Win32Error.InitializationError;

    try Table.setupEvents(hwnd);
    _ = win32.SendMessageW(hwnd, win32.WM_SETFONT, @intFromPtr(@import("backend.zig").captionFont), 1);

    // Set extended styles for better appearance
    _ = win32.SendMessageW(hwnd, win32Backend.LVM_SETEXTENDEDLISTVIEWSTYLE, 0, @bitCast(@as(
        isize,
        @intCast(win32Backend.LVS_EX_FULLROWSELECT | win32Backend.LVS_EX_GRIDLINES | win32Backend.LVS_EX_DOUBLEBUFFER),
    )));

    return Table{ .peer = hwnd };
}

pub fn setColumns(self: *Table, columns: []const ColumnDef) void {
    // Remove existing columns (in reverse order)
    const existing: usize = @intCast(win32.SendMessageW(
        self.peer,
        win32Backend.LVM_GETCOLUMNCOUNT,
        0,
        0,
    ));
    var i = existing;
    while (i > 0) {
        i -= 1;
        _ = win32.SendMessageW(self.peer, win32Backend.LVM_DELETECOLUMN, i, 0);
    }

    // Add new columns
    const allocator = lib.internal.allocator;
    for (columns, 0..) |col_def, col_idx| {
        const utf16 = std.unicode.utf8ToUtf16LeAllocZ(allocator, col_def.header) catch continue;
        defer allocator.free(utf16);

        var lvc = win32Backend.LVCOLUMNW{
            .mask = win32Backend.LVCF_FMT | win32Backend.LVCF_WIDTH | win32Backend.LVCF_TEXT | win32Backend.LVCF_SUBITEM,
            .fmt = win32Backend.LVCFMT_LEFT,
            .cx = @intFromFloat(col_def.width),
            .pszText = utf16.ptr,
            .iSubItem = @intCast(col_idx),
        };

        _ = win32.SendMessageW(
            self.peer,
            win32Backend.LVM_INSERTCOLUMNW,
            col_idx,
            @bitCast(@intFromPtr(&lvc)),
        );
    }

    self.column_count = columns.len;
}

pub fn setCellProvider(self: *Table, provider: *const fn (row: usize, col: usize, buf: []u8) []const u8) void {
    self.cell_provider = provider;
}

pub fn setRowCount(self: *Table, count: usize) void {
    self.row_count = count;
    // In virtual mode (LVS_OWNERDATA), set the item count
    _ = win32.SendMessageW(self.peer, win32Backend.LVM_SETITEMCOUNT, count, 0);
}

pub fn setSelectedRow(self: *Table, row: ?usize) void {
    // Deselect all first
    var lvi = win32Backend.LVITEMW{
        .stateMask = win32Backend.LVIS_SELECTED | win32Backend.LVIS_FOCUSED,
        .state = 0,
    };
    _ = win32.SendMessageW(self.peer, win32Backend.LVM_SETITEMSTATE, @bitCast(@as(isize, -1)), @bitCast(@intFromPtr(&lvi)));

    if (row) |r| {
        // Select the specified row
        lvi.state = win32Backend.LVIS_SELECTED | win32Backend.LVIS_FOCUSED;
        _ = win32.SendMessageW(self.peer, win32Backend.LVM_SETITEMSTATE, r, @bitCast(@intFromPtr(&lvi)));
    }
}

pub fn getSelectedRow(self: *Table) ?usize {
    const result = win32.SendMessageW(
        self.peer,
        win32Backend.LVM_GETNEXTITEM,
        @bitCast(@as(isize, -1)),
        win32Backend.LVNI_SELECTED,
    );
    if (result < 0) return null;
    return @intCast(result);
}

pub fn reloadData(self: *Table) void {
    // Redraw all items
    _ = win32.SendMessageW(self.peer, win32Backend.LVM_REDRAWITEMS, 0, @bitCast(@as(isize, @intCast(self.row_count))));
    _ = win32.InvalidateRect(self.peer, null, 1);
}

/// Handle LVN_GETDISPINFO notification for virtual list view.
/// Called from the parent window's WM_NOTIFY handler.
pub fn handleDispInfo(self: *Table, nmhdr: *win32Backend.NMHDR) void {
    if (nmhdr.code != win32Backend.LVN_GETDISPINFOW) return;
    const di: *win32Backend.NMLVDISPINFOW = @ptrCast(@alignCast(nmhdr));

    if (di.item.mask & win32Backend.LVIF_TEXT != 0) {
        const provider = self.cell_provider orelse return;
        const row: usize = @intCast(di.item.iItem);
        const col: usize = @intCast(di.item.iSubItem);

        var buf: [256]u8 = undefined;
        const text = provider(row, col, &buf);

        // Convert UTF-8 to UTF-16 into the provided buffer
        if (di.item.pszText) |out_buf| {
            const max_chars: usize = @intCast(di.item.cchTextMax);
            if (max_chars > 0) {
                const utf16 = std.unicode.utf8ToUtf16LeAllocZ(lib.internal.allocator, text) catch return;
                defer lib.internal.allocator.free(utf16);
                const copy_len = @min(utf16.len, max_chars - 1);
                for (0..copy_len) |j| {
                    out_buf[j] = utf16[j];
                }
                out_buf[copy_len] = 0;
            }
        }
    }
}
