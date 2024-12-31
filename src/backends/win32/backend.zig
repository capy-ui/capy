const std = @import("std");
const lib = @import("../../capy.zig");
const shared = @import("../shared.zig");
const trait = @import("../../trait.zig");
const os = @import("builtin").target.os;
const log = std.log.scoped(.win32);

const EventFunctions = shared.EventFunctions(@This());
const EventType = shared.BackendEventType;

pub const Monitor = @import("Monitor.zig");

const win32Backend = @import("win32.zig");
const zigwin32 = @import("zigwin32");
const win32 = zigwin32.everything;
const gdi = @import("gdip.zig");
const HWND = win32.HWND;
const HMENU = win32.HMENU;
const HINSTANCE = win32.HINSTANCE;
const RECT = win32.RECT;
const MSG = win32.MSG;
const WPARAM = win32.WPARAM;
const LPARAM = win32.LPARAM;
const LRESULT = win32.LRESULT;
const WINAPI = std.os.windows.WINAPI;

// Common Control: Tabs
const TCM_FIRST = 0x1300;
pub const TCM_GETITEMCOUNT = TCM_FIRST + 4;
pub const TCM_GETITEMA = TCM_FIRST + 5;
pub const TCM_GETITEMW = TCM_FIRST + 60;
pub const TCM_SETITEMA = TCM_FIRST + 6;
pub const TCM_SETITEMW = TCM_FIRST + 61;
pub const TCM_INSERTITEMA = TCM_FIRST + 7;
pub const TCM_INSERTITEMW = TCM_FIRST + 62;

const TCN_FIRST = @as(std.os.windows.UINT, 0) -% 550;
pub const TCN_SELCHANGE = TCN_FIRST - 1;
pub const TCN_SELCHANGING = TCN_FIRST - 2;

pub const TCIF_TEXT = 0x0001;
pub const TCIF_IMAGE = 0x0002;
pub const TCIF_RTLLEADING = 0x0004;
pub const TCIF_PARAM = 0x0008;
pub const TCIF_STATE = 0x0010;

const _T = zigwin32.zig._T;
const L = zigwin32.zig.L;

pub const Win32Error = error{ UnknownError, InitializationError };

pub const Capabilities = .{ .useEventLoop = true };

pub const PeerType = HWND;

pub var hInst: HINSTANCE = undefined;
/// By default, win32 controls use DEFAULT_GUI_FONT which is an outdated
/// font from Windows 95 days, by default it doesn't even use ClearType
/// anti-aliasing. So we take the real default caption font from
/// NONFCLIENTEMETRICS and apply it manually to every widget.
pub var captionFont: win32.HFONT = undefined;
pub var monospaceFont: win32.HFONT = undefined;
/// Default arrow cursor used to avoid components keeping the last cursor icon
/// that's been set (which is usually the resize cursor or loading cursor)
pub var defaultCursor: win32.HCURSOR = undefined;

var d2dFactory: *win32.ID2D1Factory = undefined;

var hasInit: bool = false;

fn transWinError(win32_error: win32.WIN32_ERROR) std.os.windows.Win32Error {
    return @as(std.os.windows.Win32Error, @enumFromInt(@intFromEnum(win32_error)));
}

pub fn init() !void {
    if (!hasInit) {
        hasInit = true;
        const hInstance = @as(win32.HINSTANCE, @ptrCast(@alignCast(win32.GetModuleHandleW(null).?)));
        hInst = hInstance;

        if (os.isAtLeast(.windows, .win10_rs2) orelse false) {
            // tell Windows that we support high-dpi
            if (win32.SetProcessDpiAwarenessContext(win32.DPI_AWARENESS_CONTEXT_PER_MONITOR_AWARE_V2) == 0) {
                log.debug("could not set dpi awareness mode; windows might look blurry on high-dpi screens", .{});
            }
        }

        const initEx = win32.INITCOMMONCONTROLSEX{
            .dwSize = @sizeOf(win32.INITCOMMONCONTROLSEX),
            .dwICC = win32.INITCOMMONCONTROLSEX_ICC.initFlags(.{ .STANDARD_CLASSES = 1, .WIN95_CLASSES = 1, .USEREX_CLASSES = 1 }),
        };
        const code = win32.InitCommonControlsEx(&initEx);
        if (code == 0) {
            log.err("Failed to initialize Common Controls", .{});
        }

        // var input = win32Backend.GdiplusStartupInput{};
        // try gdi.gdipWrap(win32Backend.GdiplusStartup(&gdi.token, &input, null));

        var ncMetrics: win32.NONCLIENTMETRICSW = undefined;
        ncMetrics.cbSize = @sizeOf(win32.NONCLIENTMETRICSW);
        _ = win32.SystemParametersInfoW(
            win32.SPI_GETNONCLIENTMETRICS,
            @sizeOf(win32.NONCLIENTMETRICSW),
            &ncMetrics,
            win32.SYSTEM_PARAMETERS_INFO_UPDATE_FLAGS.initFlags(.{}),
        );
        captionFont = win32.CreateFontIndirectW(&ncMetrics.lfCaptionFont).?;
        monospaceFont = @ptrCast(win32.GetStockObject(win32.ANSI_FIXED_FONT));
        monospaceFont = win32.CreateFontW(
            ncMetrics.lfCaptionFont.lfHeight,
            ncMetrics.lfCaptionFont.lfWidth,
            0,
            0,
            win32.FW_REGULAR,
            0,
            0,
            0,
            win32.DEFAULT_CHARSET,
            win32.OUT_DEFAULT_PRECIS,
            win32.CLIP_DEFAULT_PRECIS,
            win32.DEFAULT_QUALITY,
            .MODERN,
            _T("Courier"),
        ).?;

        // Load the default arrow cursor so that components can use it
        // This avoids components keeping the last cursor (resize cursor or loading cursor)
        defaultCursor = zigwin32.ui.windows_and_messaging.LoadCursor(null, win32.IDC_ARROW).?;

        std.debug.assert(win32.D2D1CreateFactory(
            win32.D2D1_FACTORY_TYPE_SINGLE_THREADED,
            zigwin32.graphics.direct2d.IID_ID2D1Factory,
            null,
            @as(**anyopaque, @ptrCast(&d2dFactory)),
        ) == 0);
    }
}

pub const MessageType = enum { Information, Warning, Error };

pub fn showNativeMessageDialog(msgType: MessageType, comptime fmt: []const u8, args: anytype) void {
    const msg = std.fmt.allocPrint(lib.internal.scratch_allocator, fmt, args) catch {
        std.log.err("Could not launch message dialog, original text: " ++ fmt, args);
        return;
    };
    defer lib.internal.scratch_allocator.free(msg);

    const msg_utf16 = std.unicode.utf8ToUtf16LeAllocZ(lib.internal.scratch_allocator, msg) catch {
        std.log.err("Could not launch message dialog, original text: " ++ fmt, args);
        return;
    };
    defer lib.internal.scratch_allocator.free(msg_utf16);

    const icon = switch (msgType) {
        .Information => win32.MB_ICONINFORMATION,
        .Warning => win32.MB_ICONWARNING,
        .Error => win32.MB_ICONERROR,
    };

    _ = win32.MessageBoxW(null, msg_utf16, _T("Dialog"), icon);
}

pub var defaultWHWND: HWND = undefined;

pub const Window = struct {
    hwnd: HWND,
    source_dpi: u32 = 96,
    root_menu: ?HMENU,
    /// List of menu item callbacks, where the index is the menu item ID
    menu_item_callbacks: std.ArrayList(?*const fn () void),
    in_fullscreen: bool = false,
    restore_placement: win32.WINDOWPLACEMENT = undefined,

    const className = _T("capyWClass");
    pub usingnamespace Events(Window);

    fn relayoutChild(hwnd: HWND, lp: LPARAM) callconv(WINAPI) c_int {
        const parent = @as(HWND, @ptrFromInt(@as(usize, @bitCast(lp))));
        if (win32.GetParent(hwnd) != parent) {
            return 1; // ignore recursive childrens
        }

        var rect: RECT = undefined;
        _ = win32.GetClientRect(parent, &rect);
        _ = win32.MoveWindow(hwnd, 0, 0, rect.right - rect.left, rect.bottom - rect.top, 1);
        return 1;
    }

    pub fn onResize(data: *EventUserData, hwnd: HWND) void {
        _ = data;
        _ = win32.EnumChildWindows(hwnd, relayoutChild, @as(isize, @bitCast(@intFromPtr(hwnd))));
    }

    pub fn onDpiChanged(self: *EventUserData, hwnd: HWND) void {
        _ = hwnd;
        _ = self;
        // TODO: update scale factor
    }

    pub fn create() !Window {
        var wc: win32.WNDCLASSEXW = .{
            .cbSize = @sizeOf(win32.WNDCLASSEXW),
            .style = win32.WNDCLASS_STYLES.initFlags(.{ .HREDRAW = 1, .VREDRAW = 1 }),
            .lpfnWndProc = Window.process,
            .cbClsExtra = 0,
            .cbWndExtra = 0,
            .hInstance = hInst,
            .hIcon = null, // TODO: LoadIcon
            .hCursor = defaultCursor,
            .hbrBackground = win32.GetSysColorBrush(@intFromEnum(win32.COLOR_3DFACE)),
            .lpszMenuName = null,
            .lpszClassName = className,
            .hIconSm = null,
        };

        if ((win32.RegisterClassExW(&wc)) == 0) {
            showNativeMessageDialog(.Error, "Could not register window class {s}", .{"capyWClass"});
            return Win32Error.InitializationError;
        }

        // Layered windows sometimes fail on Wine and fresh install of Windows
        // See https://stackoverflow.com/questions/19951379/ws-ex-layered-invisible-window-and-a-fresh-install-of-windows
        const layered = false;

        const hwnd = win32.CreateWindowExW(
        // layered don't work in wine for some reason, but only in wine
        win32.WINDOW_EX_STYLE.initFlags(.{
            .COMPOSITED = 1,
            .LAYERED = @intFromBool(layered),
            .APPWINDOW = 1,
        }), className, // lpClassName
            _T(""), // lpWindowName
            win32.WS_OVERLAPPEDWINDOW, // dwStyle
            win32.CW_USEDEFAULT, // X
            win32.CW_USEDEFAULT, // Y
            win32.CW_USEDEFAULT, // nWidth
            win32.CW_USEDEFAULT, // nHeight
            null, // hWindParent
            null, // hMenu
            hInst, // hInstance
            null // lpParam
        ) orelse return Win32Error.InitializationError;
        try Window.setupEvents(hwnd);

        if (layered) {
            _ = win32.UpdateLayeredWindow(
                hwnd,
                null,
                null,
                null,
                null,
                null,
                0xFFFFFFFF,
                null,
                win32.ULW_OPAQUE,
            );
        }

        defaultWHWND = hwnd;
        return Window{
            .hwnd = hwnd,
            .root_menu = null,
            .menu_item_callbacks = std.ArrayList(?*const fn () void).init(
                lib.internal.lasting_allocator,
            ),
        };
    }

    // TODO: handle the fact that ONLY the root child must forcibly draw a background
    pub fn setChild(self: *Window, hwnd: ?HWND) void {
        // TODO: if null, remove child
        _ = win32.SetParent(hwnd.?, self.hwnd);
        const style = win32Backend.getWindowLongPtr(hwnd.?, win32.GWL_STYLE);
        _ = win32Backend.setWindowLongPtr(hwnd.?, win32.GWL_STYLE, style | @intFromEnum(win32.WS_CHILD));
        _ = win32.ShowWindow(hwnd.?, win32.SW_SHOWDEFAULT);
        _ = win32.UpdateWindow(hwnd.?);
    }

    pub fn resize(self: *Window, width: c_int, height: c_int) void {
        var rect: RECT = undefined;
        _ = win32.GetWindowRect(self.hwnd, &rect);
        _ = win32.MoveWindow(self.hwnd, rect.left, rect.top, @as(c_int, @intCast(width)), @as(c_int, @intCast(height)), 1);
    }

    pub fn setTitle(self: *Window, title: [*:0]const u8) void {
        const utf16 = std.unicode.utf8ToUtf16LeAllocZ(lib.internal.scratch_allocator, std.mem.span(title)) catch return;
        defer lib.internal.scratch_allocator.free(utf16);

        _ = win32.SetWindowTextW(self.hwnd, utf16);
    }

    fn initMenu(self: *Window, menu: HMENU, items: []const lib.MenuItem) !void {
        for (items) |item| {
            if (item.items.len > 0) {
                const submenu = win32.CreateMenu().?;
                _ = win32.AppendMenuA(
                    menu,
                    win32.MENU_ITEM_FLAGS.initFlags(.{ .POPUP = 1 }),
                    @intFromPtr(submenu),
                    item.config.label,
                );
                try initMenu(self, submenu, item.items);
            } else {
                _ = win32.AppendMenuA(
                    menu,
                    win32.MENU_ITEM_FLAGS.initFlags(.{}),
                    self.menu_item_callbacks.items.len,
                    item.config.label,
                );
                try self.menu_item_callbacks.append(item.config.onClick);
            }
        }
    }

    fn clearAndFreeMenus(self: *Window) void {
        _ = win32.DestroyMenu(self.root_menu);
        self.menu_item_callbacks.clearAndFree();
        self.root_menu = null;
    }

    pub fn setMenuBar(self: *Window, bar: lib.MenuBar) void {
        // Detach and free current menu (if exists) from window first.
        _ = win32.SetMenu(self.hwnd, null);
        self.clearAndFreeMenus();

        const root_menu = win32.CreateMenu().?;
        self.initMenu(root_menu, bar.menus) catch {
            // TODO: Handle error in appropriate way
        };
        if (win32.SetMenu(self.hwnd, root_menu) != 0) {
            self.root_menu = root_menu;
        } else {
            self.menu_item_callbacks.clearAndFree();
        }
    }

    pub fn registerTickCallback(self: *Window) void {
        _ = self;
        // TODO
    }

    pub fn setSourceDpi(self: *Window, dpi: u32) void {
        self.source_dpi = dpi;
    }

    pub fn setFullscreen(self: *Window, monitor: ?*Monitor, video_mode: ?lib.VideoMode) void {
        // Capture the current window position and size
        if (!self.in_fullscreen) {
            _ = win32.GetWindowPlacement(self.hwnd, &self.restore_placement);
        }

        // Change video mode
        if (video_mode) |mode| {
            var dev_mode = std.mem.zeroInit(win32.DEVMODEW, .{
                .dmSize = @sizeOf(win32.DEVMODEW),
            });
            std.debug.assert(win32.EnumDisplaySettingsW(monitor.?.adapter_win32_name, win32.ENUM_CURRENT_SETTINGS, &dev_mode) != 0);
            dev_mode.dmPelsWidth = mode.width;
            dev_mode.dmPelsHeight = mode.height;
            dev_mode.dmBitsPerPel = mode.bit_depth;
            dev_mode.dmDisplayFrequency = mode.refresh_rate_millihertz / 1000;
            dev_mode.dmFields = win32.DM_PELSWIDTH | win32.DM_PELSHEIGHT | win32.DM_BITSPERPEL | win32.DM_DISPLAYFREQUENCY;
            _ = win32.ChangeDisplaySettingsW(&dev_mode, win32.CDS_FULLSCREEN);
        }

        // Make the window fullscreen
        if (!self.in_fullscreen) {
            const hmonitor = if (monitor) |mon| mon.getHmonitor() else win32.MonitorFromWindow(self.hwnd, win32.MONITOR_DEFAULTTONEAREST);

            const style = win32Backend.getWindowLongPtr(self.hwnd, win32.GWL_STYLE);
            _ = win32Backend.setWindowLongPtr(self.hwnd, win32.GWL_STYLE, style & ~(@intFromEnum(win32.WS_CAPTION) | @intFromEnum(win32.WS_THICKFRAME)));
            const ex_style = win32Backend.getWindowLongPtr(self.hwnd, win32.GWL_EXSTYLE);
            _ = win32Backend.setWindowLongPtr(self.hwnd, win32.GWL_EXSTYLE, ex_style & ~(@intFromEnum(win32.WS_EX_DLGMODALFRAME) | @intFromEnum(win32.WS_EX_WINDOWEDGE) | @intFromEnum(win32.WS_EX_CLIENTEDGE) | @intFromEnum(win32.WS_EX_STATICEDGE)));

            var monitor_info = std.mem.zeroInit(win32.MONITORINFO, .{ .cbSize = @sizeOf(win32.MONITORINFO) });
            std.debug.assert(win32.GetMonitorInfoW(hmonitor, &monitor_info) != 0);
            const rect = monitor_info.rcMonitor;
            _ = win32.SetWindowPos(
                self.hwnd,
                null,
                rect.left,
                rect.top,
                rect.right - rect.left,
                rect.bottom - rect.top,
                win32.SET_WINDOW_POS_FLAGS.initFlags(.{ .NOZORDER = 1, .NOACTIVATE = 1, .DRAWFRAME = 1 }),
            );
            self.in_fullscreen = true;
        }
    }

    pub fn unfullscreen(self: *Window) void {
        if (self.in_fullscreen) {
            _ = win32.ChangeDisplaySettingsW(null, win32.CDS_RESET);
            const style = win32Backend.getWindowLongPtr(self.hwnd, win32.GWL_STYLE);
            _ = win32Backend.setWindowLongPtr(self.hwnd, win32.GWL_STYLE, style | (@intFromEnum(win32.WS_CAPTION) | @intFromEnum(win32.WS_THICKFRAME)));
            const ex_style = win32Backend.getWindowLongPtr(self.hwnd, win32.GWL_EXSTYLE);
            _ = win32Backend.setWindowLongPtr(self.hwnd, win32.GWL_EXSTYLE, ex_style | (@intFromEnum(win32.WS_EX_DLGMODALFRAME) | @intFromEnum(win32.WS_EX_WINDOWEDGE) | @intFromEnum(win32.WS_EX_CLIENTEDGE) | @intFromEnum(win32.WS_EX_STATICEDGE)));
            _ = win32.SetWindowPlacement(self.hwnd, &self.restore_placement);
            _ = win32.SetWindowPos(self.hwnd, null, 0, 0, 0, 0, win32.SET_WINDOW_POS_FLAGS.initFlags(.{
                .NOMOVE = 1,
                .NOSIZE = 1,
                .NOZORDER = 1,
                .NOOWNERZORDER = 1,
                .DRAWFRAME = 1,
                .NOACTIVATE = 1,
            }));
            self.in_fullscreen = false;
        }
    }

    pub fn show(self: *Window) void {
        _ = win32.ShowWindow(self.hwnd, win32.SW_SHOWDEFAULT);
        _ = win32.UpdateWindow(self.hwnd);
    }

    pub fn close(self: *Window) void {
        _ = win32.ShowWindow(self.hwnd, win32.SW_HIDE);
        _ = win32.UpdateWindow(self.hwnd);
    }
};

const EventUserData = struct {
    user: EventFunctions = .{},
    class: EventFunctions = .{},
    userdata: usize = 0,
    peerPtr: ?*anyopaque = null,
    classUserdata: usize = 0,
    // (very) weak method to detect if a text box's text has actually changed
    last_text_len: std.os.windows.INT = 0,
    extra_height: i32 = 0,
};

pub inline fn getEventUserData(peer: HWND) *EventUserData {
    return @as(*EventUserData, @ptrFromInt(@as(usize, @bitCast(win32Backend.getWindowLongPtr(peer, win32.GWL_USERDATA)))));
}

pub fn Events(comptime T: type) type {
    return struct {
        const Self = @This();

        pub fn process(hwnd: HWND, wm: c_uint, wp: WPARAM, lp: LPARAM) callconv(WINAPI) LRESULT {
            switch (wm) {
                win32.WM_NOTIFY => {
                    const nmhdr = @as(*const win32.NMHDR, @ptrFromInt(@as(usize, @bitCast(lp))));
                    //std.log.info("code = {d} vs {d}", .{ nmhdr.code, win32.TCN_SELCHANGING });
                    switch (nmhdr.code) {
                        TCN_SELCHANGING => {
                            return 0;
                        },
                        else => {},
                    }
                },
                else => {},
            }
            if (win32Backend.getWindowLongPtr(hwnd, win32.GWL_USERDATA) == 0) return win32.DefWindowProcW(hwnd, wm, wp, lp);
            switch (wm) {
                win32.WM_COMMAND => {
                    const code = @as(u16, @intCast(wp >> 16));
                    if (lp != 0) {
                        const data = getEventUserData(@as(HWND, @ptrFromInt(@as(usize, @bitCast(lp)))));
                        switch (code) {
                            win32.BN_CLICKED => {
                                if (data.user.clickHandler) |handler|
                                    handler(data.userdata);
                            },
                            win32.EN_CHANGE => {
                                // Doesn't appear to work.
                                if (data.user.changedTextHandler) |handler|
                                    handler(data.userdata);
                            },
                            win32.CBN_SELCHANGE => {
                                const index: usize = @intCast(win32.SendMessageW(
                                    @ptrFromInt(@as(usize, @bitCast(lp))),
                                    win32.CB_GETCURSEL,
                                    0,
                                    0,
                                ));
                                if (data.user.propertyChangeHandler) |handler|
                                    handler("selected", &index, data.userdata);
                            },
                            else => {},
                        }
                    }
                    // For menubar item events, HIWORD(wp) and lp are set to 0.
                    else if (code == 0) {
                        const data = getEventUserData(hwnd);
                        const window_ptr: ?*Window = @ptrCast(@alignCast(data.peerPtr));
                        const id: u16 = @intCast(wp & 0xFFFF);

                        if (window_ptr) |window| {
                            if (id < window.menu_item_callbacks.items.len) {
                                if (window.menu_item_callbacks.items[id]) |callback| {
                                    callback();
                                }
                            }
                        }
                    }
                },
                win32.WM_CTLCOLOREDIT => {
                    const data = getEventUserData(@as(HWND, @ptrFromInt(@as(usize, @bitCast(lp)))));
                    const len = win32.GetWindowTextLengthW(@as(HWND, @ptrFromInt(@as(usize, @bitCast(lp)))));
                    // The text box may have changed
                    // TODO: send the event only when the text truly changed
                    if (data.last_text_len != len) {
                        if (data.user.changedTextHandler) |handler|
                            handler(data.userdata);
                        data.last_text_len = len;
                    }
                },
                win32.WM_NOTIFY => {
                    const nmhdr = @as(*const win32.NMHDR, @ptrFromInt(@as(usize, @bitCast(lp))));
                    //std.log.info("code = {d} vs {d}", .{ nmhdr.code, win32.TCN_SELCHANGING });
                    switch (nmhdr.code) {
                        TCN_SELCHANGING => {
                            return 0;
                        },
                        TCN_SELCHANGE => {
                            if (@hasDecl(T, "onSelChange")) {
                                const data = getEventUserData(hwnd);
                                const sel = win32Backend.TabCtrl_GetCurSelW(nmhdr.hwndFrom.?);
                                T.onSelChange(data, hwnd, @as(usize, @intCast(sel)));
                            }
                        },
                        else => {},
                    }
                },
                win32.WM_SIZE => {
                    const data = getEventUserData(hwnd);
                    if (@hasDecl(T, "onResize")) {
                        T.onResize(data, hwnd);
                    }
                    var rect: RECT = undefined;
                    _ = win32.GetWindowRect(hwnd, &rect);

                    if (data.class.resizeHandler) |handler|
                        handler(@as(u32, @intCast(rect.right - rect.left)), @as(u32, @intCast(rect.bottom - rect.top)), data.userdata);
                    if (data.user.resizeHandler) |handler|
                        handler(@as(u32, @intCast(rect.right - rect.left)), @as(u32, @intCast(rect.bottom - rect.top)), data.userdata);
                },
                win32.WM_HSCROLL => {
                    const data = getEventUserData(hwnd);
                    var scrollInfo = std.mem.zeroInit(win32.SCROLLINFO, .{
                        .cbSize = @sizeOf(win32.SCROLLINFO),
                        .fMask = win32.SIF_POS,
                    });
                    _ = win32.GetScrollInfo(hwnd, win32.SB_HORZ, &scrollInfo);

                    const currentScroll = @as(u32, @intCast(scrollInfo.nPos));
                    const newPos = switch (@as(u16, @truncate(wp))) {
                        win32.SB_PAGEUP => currentScroll -| 50,
                        win32.SB_PAGEDOWN => currentScroll + 50,
                        win32.SB_LINEUP => currentScroll -| 5,
                        win32.SB_LINEDOWN => currentScroll + 5,
                        win32.SB_THUMBPOSITION, win32.SB_THUMBTRACK => wp >> 16,
                        else => currentScroll,
                    };

                    if (newPos != currentScroll) {
                        var horizontalScrollInfo = std.mem.zeroInit(win32.SCROLLINFO, .{
                            .cbSize = @sizeOf(win32.SCROLLINFO),
                            .fMask = win32.SIF_POS,
                            .nPos = @as(c_int, @intCast(newPos)),
                        });
                        _ = win32.SetScrollInfo(hwnd, win32.SB_HORZ, &horizontalScrollInfo, 1);
                        if (@hasDecl(T, "onHScroll")) {
                            T.onHScroll(data, hwnd, newPos);
                        }
                    }
                },
                win32.WM_VSCROLL => {
                    const data = getEventUserData(hwnd);
                    var scrollInfo = std.mem.zeroInit(win32.SCROLLINFO, .{ .fMask = win32.SIF_POS });
                    _ = win32.GetScrollInfo(hwnd, win32.SB_VERT, &scrollInfo);

                    const currentScroll = @as(u32, @intCast(scrollInfo.nPos));
                    const newPos = switch (@as(u16, @truncate(wp))) {
                        win32.SB_PAGEUP => currentScroll -| 50,
                        win32.SB_PAGEDOWN => currentScroll + 50,
                        win32.SB_LINEUP => currentScroll -| 5,
                        win32.SB_LINEDOWN => currentScroll + 5,
                        win32.SB_THUMBPOSITION, win32.SB_THUMBTRACK => wp >> 16,
                        else => currentScroll,
                    };

                    if (newPos != currentScroll) {
                        var verticalScrollInfo = std.mem.zeroInit(win32.SCROLLINFO, .{
                            .fMask = win32.SIF_POS,
                            .nPos = @as(c_int, @intCast(newPos)),
                        });
                        _ = win32.SetScrollInfo(hwnd, win32.SB_VERT, &verticalScrollInfo, 1);
                        if (@hasDecl(T, "onVScroll")) {
                            T.onVScroll(data, hwnd, newPos);
                        }
                    }
                },
                win32.WM_PAINT => blk: {
                    const data = getEventUserData(hwnd);
                    if (data.class.drawHandler == null and data.user.drawHandler == null) break :blk;

                    var rc: win32.RECT = undefined;
                    _ = win32.GetClientRect(hwnd, &rc);

                    var render_target: ?*win32.ID2D1HwndRenderTarget = null;
                    const hresult = d2dFactory.ID2D1Factory_CreateHwndRenderTarget(
                        &win32.D2D1_RENDER_TARGET_PROPERTIES{
                            .type = win32.D2D1_RENDER_TARGET_TYPE_DEFAULT,
                            .pixelFormat = .{
                                .format = win32.DXGI_FORMAT_UNKNOWN,
                                .alphaMode = win32.D2D1_ALPHA_MODE_UNKNOWN,
                            },
                            .dpiX = 0.0,
                            .dpiY = 0.0,
                            .usage = win32.D2D1_RENDER_TARGET_USAGE_NONE,
                            .minLevel = win32.D2D1_FEATURE_LEVEL_DEFAULT,
                        },
                        &win32.D2D1_HWND_RENDER_TARGET_PROPERTIES{
                            .hwnd = hwnd,
                            .pixelSize = .{
                                .width = @as(u32, @intCast(rc.right - rc.left)),
                                .height = @as(u32, @intCast(rc.bottom - rc.top)),
                            },
                            .presentOptions = win32.D2D1_PRESENT_OPTIONS_NONE,
                        },
                        &render_target,
                    );
                    std.debug.assert(hresult == 0);
                    // defer win32.SafeRelease(render_target);

                    var default_brush: ?*win32.ID2D1SolidColorBrush = null;
                    std.debug.assert(render_target.?.ID2D1RenderTarget_CreateSolidColorBrush(
                        &win32.D2D1_COLOR_F{ .r = 0, .g = 0, .b = 0, .a = 1 },
                        null,
                        &default_brush,
                    ) == 0);

                    const dci = Canvas.DrawContextImpl{
                        .render_target = render_target.?,
                        .brush = default_brush.?,
                        .path = std.ArrayList(Canvas.DrawContextImpl.PathElement)
                            .init(lib.internal.scratch_allocator),
                    };
                    var dc = @import("../../backend.zig").DrawContext{ .impl = dci };
                    defer dc.impl.path.deinit();

                    render_target.?.ID2D1RenderTarget_BeginDraw();
                    render_target.?.ID2D1RenderTarget_Clear(&win32.D2D1_COLOR_F{ .r = 1, .g = 1, .b = 1, .a = 0 });
                    defer _ = render_target.?.ID2D1RenderTarget_EndDraw(null, null);
                    if (data.class.drawHandler) |handler|
                        handler(&dc, data.userdata);
                    if (data.user.drawHandler) |handler|
                        handler(&dc, data.userdata);
                },
                win32.WM_SETFOCUS => {
                    if (@hasDecl(T, "onGotFocus")) {
                        T.onGotFocus(hwnd);
                    }
                },
                win32.WM_DESTROY => win32.PostQuitMessage(0),
                else => {},
            }
            return win32.DefWindowProcW(hwnd, wm, wp, lp);
        }

        pub fn setupEvents(peer: HWND) !void {
            const data = try lib.internal.lasting_allocator.create(EventUserData);
            data.* = EventUserData{}; // ensure that it uses default values
            _ = win32Backend.setWindowLongPtr(peer, win32.GWL_USERDATA, @intFromPtr(data));
        }

        pub inline fn setUserData(self: *T, data: anytype) void {
            comptime {
                if (!trait.isSingleItemPtr(@TypeOf(data))) {
                    @compileError(std.fmt.comptimePrint("Expected single item pointer, got {s}", .{@typeName(@TypeOf(data))}));
                }
            }
            if (@TypeOf(self) == *Window) {
                getEventUserData(self.hwnd).peerPtr = self;
                getEventUserData(self.hwnd).userdata = @intFromPtr(data);
            } else {
                getEventUserData(self.peer).peerPtr = self;
                getEventUserData(self.peer).userdata = @intFromPtr(data);
            }
        }

        pub inline fn setCallback(self: *T, comptime eType: EventType, cb: anytype) !void {
            const data = if (@TypeOf(self) == *Window) &getEventUserData(self.hwnd).user else &getEventUserData(self.peer).user;
            switch (eType) {
                .Click => data.clickHandler = cb,
                .Draw => data.drawHandler = cb,
                // TODO: implement mouse button
                .MouseButton => data.mouseButtonHandler = cb,
                // TODO: implement mouse motion
                .MouseMotion => data.mouseMotionHandler = cb,
                // TODO: implement scroll
                .Scroll => data.scrollHandler = cb,
                .TextChanged => data.changedTextHandler = cb,
                .Resize => data.resizeHandler = cb,
                // TODO: implement key type
                .KeyType => data.keyTypeHandler = cb,
                // TODO: implement key press
                .KeyPress => data.keyPressHandler = cb,
                .PropertyChange => data.propertyChangeHandler = cb,
            }
        }

        /// Requests a redraw
        pub fn requestDraw(self: *T) !void {
            var updateRect: RECT = undefined;
            updateRect = .{ .left = 0, .top = 0, .right = 10000, .bottom = 10000 };
            if (win32.InvalidateRect(self.peer, &updateRect, 0) == 0) {
                return Win32Error.UnknownError;
            }
            if (win32.UpdateWindow(self.peer) == 0) {
                return Win32Error.UnknownError;
            }
        }

        pub fn getWidth(self: *const T) c_int {
            var rect: RECT = undefined;
            _ = win32.GetWindowRect(self.peer, &rect);
            return rect.right - rect.left;
        }

        pub fn getHeight(self: *const T) c_int {
            const data = getEventUserData(self.peer);
            var rect: RECT = undefined;
            _ = win32.GetWindowRect(self.peer, &rect);
            return rect.bottom - rect.top -| data.extra_height;
        }

        pub fn getPreferredSize(self: *const T) lib.Size {
            // TODO
            _ = self;
            return lib.Size.init(100, 50);
        }

        pub fn setOpacity(self: *const T, opacity: f64) void {
            _ = self;
            _ = opacity;
            // TODO
        }

        pub fn deinit(self: *const T) void {
            _ = self;
            // TODO
        }
    };
}

pub const Canvas = struct {
    peer: HWND,
    data: usize = 0,

    pub usingnamespace Events(Canvas);

    pub const DrawContextImpl = struct {
        path: std.ArrayList(PathElement),
        render_target: *win32.ID2D1HwndRenderTarget,
        brush: *win32.ID2D1SolidColorBrush,

        const PathElement = union(enum) {
            Rectangle: struct { left: c_int, top: c_int, right: c_int, bottom: c_int },
        };

        pub const TextLayout = struct {
            font: win32.HFONT,
            /// HDC only used for getting text metrics
            hdc: win32.HDC,
            /// If null, no text wrapping is applied, otherwise the text is wrapping as if this was the maximum width.
            /// TODO: this is not yet implemented in the win32 backend
            wrap: ?f64 = null,

            pub const Font = struct {
                face: [:0]const u8,
                size: f64,
            };

            pub const TextSize = struct { width: u32, height: u32 };

            pub fn init() TextLayout {
                // creates an HDC for the current screen, whatever it means given we can have windows on different screens
                const hdc = win32.CreateCompatibleDC(null);

                const defaultFont = @as(win32.HFONT, @ptrCast(win32.GetStockObject(win32.DEFAULT_GUI_FONT)));
                _ = win32.SelectObject(hdc, @as(win32.HGDIOBJ, @ptrCast(defaultFont)));
                return TextLayout{ .font = defaultFont, .hdc = hdc };
            }

            pub fn setFont(self: *TextLayout, font: Font) void {
                // _ = win32.DeleteObject(@ptrCast(win32.HGDIOBJ, self.font)); // delete old font
                const allocator = lib.internal.scratch_allocator;
                const wideFace = std.unicode.utf8ToUtf16LeAllocZ(allocator, font.face) catch return; // invalid utf8 or not enough memory
                defer allocator.free(wideFace);
                if (win32.CreateFontW(0, // cWidth
                    0, // cHeight
                    0, // cEscapement,
                    0, // cOrientation,
                    win32.FW_NORMAL, // cWeight
                    0, // bItalic
                    0, // bUnderline
                    0, // bStrikeOut
                    0, // iCharSet
                    win32.FONT_OUTPUT_PRECISION.DEFAULT_PRECIS, // iOutPrecision
                    win32.FONT_CLIP_PRECISION.DEFAULT_PRECIS, // iClipPrecision
                    win32.FONT_QUALITY.DEFAULT_QUALITY, // iQuality
                    win32.FONT_PITCH_AND_FAMILY.DONTCARE, // iPitchAndFamily
                    wideFace // pszFaceName
                )) |winFont| {
                    _ = win32.DeleteObject(@as(win32.HGDIOBJ, @ptrCast(self.font)));
                    self.font = winFont;
                }
                _ = win32.SelectObject(self.hdc, @as(win32.HGDIOBJ, @ptrCast(self.font)));
            }

            pub fn getTextSize(self: *TextLayout, str: []const u8) TextSize {
                var size: win32.SIZE = undefined;
                const allocator = lib.internal.scratch_allocator;
                const wide = std.unicode.utf8ToUtf16LeAllocZ(allocator, str) catch return; // invalid utf8 or not enough memory
                defer allocator.free(wide);
                _ = win32.GetTextExtentPoint32W(self.hdc, wide.ptr, @as(c_int, @intCast(str.len)), &size);

                return TextSize{ .width = @as(u32, @intCast(size.cx)), .height = @as(u32, @intCast(size.cy)) };
            }

            pub fn deinit(self: *TextLayout) void {
                _ = win32.DeleteObject(@as(win32.HGDIOBJ, @ptrCast(self.hdc)));
                _ = win32.DeleteObject(@as(win32.HGDIOBJ, @ptrCast(self.font)));
            }
        };

        pub fn setColorRGBA(self: *DrawContextImpl, r: f32, g: f32, b: f32, a: f32) void {
            const color = lib.Color{
                .red = @as(u8, @intFromFloat(std.math.clamp(r, 0, 1) * 255)),
                .green = @as(u8, @intFromFloat(std.math.clamp(g, 0, 1) * 255)),
                .blue = @as(u8, @intFromFloat(std.math.clamp(b, 0, 1) * 255)),
                .alpha = @as(u8, @intFromFloat(std.math.clamp(a, 0, 1) * 255)),
            };
            const colorref = (@as(u32, color.blue) << 16) |
                (@as(u32, color.green) << 8) | color.red;
            _ = colorref;
            _ = self;
            // _ = win32.SetDCBrushColor(self.hdc, colorref);
        }

        pub fn rectangle(self: *DrawContextImpl, x: i32, y: i32, w: u32, h: u32) void {
            _ = h;
            _ = w;
            _ = y;
            _ = x;
            _ = self;
            // _ = win32.Rectangle(self.hdc, @intCast(c_int, x), @intCast(c_int, y), x + @intCast(c_int, w), y + @intCast(c_int, h));
        }

        pub fn ellipse(self: *DrawContextImpl, x: i32, y: i32, w: u32, h: u32) void {
            _ = y;
            _ = x;
            _ = self;
            const cw = @as(c_int, @intCast(w));
            _ = cw;
            const ch = @as(c_int, @intCast(h));
            _ = ch;

            // _ = win32.Ellipse(self.hdc, @intCast(c_int, x), @intCast(c_int, y), @intCast(c_int, x) + cw, @intCast(c_int, y) + ch);
        }

        pub fn text(self: *DrawContextImpl, x: i32, y: i32, layout: TextLayout, str: []const u8) void {
            _ = str;
            _ = layout;
            _ = y;
            _ = x;
            _ = self;
            // select current color
            // const color = win32.GetDCBrushColor(self.hdc);
            // _ = win32.SetTextColor(self.hdc, color);

            // select the font
            // win32.SelectObject(self.hdc, @ptrCast(win32.HGDIOBJ, layout.font));

            // and draw
            // _ = win32.ExtTextOutA(self.hdc, @intCast(c_int, x), @intCast(c_int, y), 0, null, str.ptr, @intCast(std.os.windows.UINT, str.len), null);
        }

        pub fn line(self: *DrawContextImpl, x1: i32, y1: i32, x2: i32, y2: i32) void {
            _ = y2;
            _ = x2;
            _ = y1;
            _ = x1;
            _ = self;
            // _ = win32.MoveToEx(self.hdc, @intCast(c_int, x1), @intCast(c_int, y1), null);
            // _ = win32.LineTo(self.hdc, @intCast(c_int, x2), @intCast(c_int, y2));
        }

        pub fn fill(self: *DrawContextImpl) void {
            self.path.clearRetainingCapacity();
        }

        pub fn stroke(self: *DrawContextImpl) void {
            self.path.clearRetainingCapacity();
        }
    };

    var classRegistered = false;

    pub fn create() !Canvas {
        if (!classRegistered) {
            var wc: win32.WNDCLASSEXW = .{
                .cbSize = @sizeOf(win32.WNDCLASSEXW),
                .style = win32.WNDCLASS_STYLES.initFlags(.{ .VREDRAW = 1, .HREDRAW = 1 }),
                .lpfnWndProc = Canvas.process,
                .cbClsExtra = 0,
                .cbWndExtra = 0,
                .hInstance = hInst,
                .hIcon = null, // TODO: LoadIcon
                .hCursor = defaultCursor,
                .hbrBackground = null,
                .lpszMenuName = null,
                .lpszClassName = L("capyCanvasClass"),
                .hIconSm = null,
            };

            if ((win32.RegisterClassExW(&wc)) == 0) {
                showNativeMessageDialog(.Error, "Could not register window class {s}", .{"capyCanvasClass"});
                return Win32Error.InitializationError;
            }
            classRegistered = true;
        }

        const hwnd = win32.CreateWindowExW(win32.WS_EX_LEFT, // dwExtStyle
            L("capyCanvasClass"), // lpClassName
            L(""), // lpWindowName
            win32.WINDOW_STYLE.initFlags(.{ .TABSTOP = 1, .CHILD = 1 }), // dwStyle
            0, // X
            0, // Y
            100, // nWidth
            100, // nHeight
            defaultWHWND, // hWindParent
            null, // hMenu
            hInst, // hInstance
            null // lpParam
        ) orelse return Win32Error.InitializationError;
        try Canvas.setupEvents(hwnd);

        return Canvas{ .peer = hwnd };
    }
};

pub const TextField = struct {
    peer: HWND,
    /// Cache of the text field's text converted to UTF-8
    text_utf8: std.ArrayList(u8) = std.ArrayList(u8).init(lib.internal.lasting_allocator),

    pub usingnamespace Events(TextField);

    pub fn create() !TextField {
        const hwnd = win32.CreateWindowExW(win32.WS_EX_LEFT, // dwExtStyle
            _T("EDIT"), // lpClassName
            _T(""), // lpWindowName
            @as(win32.WINDOW_STYLE, @enumFromInt(@intFromEnum(win32.WS_TABSTOP) | @intFromEnum(win32.WS_CHILD) | @intFromEnum(win32.WS_BORDER))), // dwStyle
            0, // X
            0, // Y
            100, // nWidth
            100, // nHeight
            defaultWHWND, // hWindParent
            null, // hMenu
            hInst, // hInstance
            null // lpParam
        ) orelse return Win32Error.InitializationError;
        try TextField.setupEvents(hwnd);
        _ = win32.SendMessageW(hwnd, win32.WM_SETFONT, @intFromPtr(captionFont), 1);

        return TextField{ .peer = hwnd };
    }

    pub fn setText(self: *TextField, text: []const u8) void {
        const allocator = lib.internal.scratch_allocator;
        const wide = std.unicode.utf8ToUtf16LeAllocZ(allocator, text) catch return; // invalid utf8 or not enough memory
        defer allocator.free(wide);
        if (win32.SetWindowTextW(self.peer, wide) == 0) {
            std.os.windows.unexpectedError(transWinError(win32.GetLastError())) catch {};
        }

        const len = win32.GetWindowTextLengthW(self.peer);
        getEventUserData(self.peer).last_text_len = len;
    }

    pub fn getText(self: *TextField) [:0]const u8 {
        const len = win32.GetWindowTextLengthW(self.peer);
        var buf = lib.internal.scratch_allocator.allocSentinel(u16, @as(usize, @intCast(len)), 0) catch unreachable; // TODO return error
        defer lib.internal.scratch_allocator.free(buf);
        const realLen = @as(usize, @intCast(win32.GetWindowTextW(self.peer, buf.ptr, len + 1)));
        const utf16Slice = buf[0..realLen];

        self.text_utf8.clearAndFree();
        std.unicode.utf16LeToUtf8ArrayList(&self.text_utf8, utf16Slice) catch @panic("OOM");
        self.text_utf8.append(0) catch @panic("OOM");
        return self.text_utf8.items[0 .. self.text_utf8.items.len - 1 :0];
    }

    pub fn setReadOnly(self: *TextField, readOnly: bool) void {
        _ = win32.SendMessageW(self.peer, win32.EM_SETREADONLY, @intFromBool(readOnly), undefined);
    }
};

pub const TextArea = struct {
    peer: HWND,
    arena: std.heap.ArenaAllocator,

    pub usingnamespace Events(TextArea);

    pub fn create() !TextArea {
        const hwnd = win32.CreateWindowExW(win32.WS_EX_LEFT, // dwExtStyle
            _T("EDIT"), // lpClassName
            _T(""), // lpWindowName
            @as(win32.WINDOW_STYLE, @enumFromInt(@intFromEnum(win32.WS_TABSTOP) | @intFromEnum(win32.WS_CHILD) | @intFromEnum(win32.WS_BORDER) | win32.ES_MULTILINE | win32.ES_AUTOVSCROLL | win32.ES_WANTRETURN)), // dwStyle
            0, // X
            0, // Y
            100, // nWidth
            100, // nHeight
            defaultWHWND, // hWindParent
            null, // hMenu
            hInst, // hInstance
            null // lpParam
        ) orelse return Win32Error.InitializationError;
        try TextArea.setupEvents(hwnd);
        _ = win32.SendMessageW(hwnd, win32.WM_SETFONT, @intFromPtr(captionFont), 1);

        return TextArea{ .peer = hwnd, .arena = std.heap.ArenaAllocator.init(lib.internal.lasting_allocator) };
    }

    pub fn setText(self: *TextArea, text: []const u8) void {
        const allocator = lib.internal.scratch_allocator;
        const wide = std.unicode.utf8ToUtf16LeAllocZ(allocator, text) catch return; // invalid utf8 or not enough memory
        defer allocator.free(wide);
        if (win32.SetWindowTextW(self.peer, wide) == 0) {
            std.os.windows.unexpectedError(transWinError(win32.GetLastError())) catch {};
        }

        const len = win32.GetWindowTextLengthW(self.peer);
        getEventUserData(self.peer).last_text_len = len;
    }

    pub fn getText(self: *TextArea) [:0]const u8 {
        const allocator = self.arena.allocator();
        const len = win32.GetWindowTextLengthW(self.peer);
        var buf = allocator.allocSentinel(u16, @as(usize, @intCast(len)), 0) catch unreachable; // TODO return error
        defer allocator.free(buf);
        const realLen = @as(usize, @intCast(win32.GetWindowTextW(self.peer, buf.ptr, len + 1)));
        const utf16Slice = buf[0..realLen];
        const text = std.unicode.utf16LeToUtf8AllocZ(allocator, utf16Slice) catch unreachable; // TODO return error
        return text;
    }

    pub fn setReadOnly(self: *TextArea, readOnly: bool) void {
        _ = win32.SendMessageW(self.peer, win32.EM_SETREADONLY, @intFromBool(readOnly), undefined);
    }

    pub fn setMonospaced(self: *TextArea, monospaced: bool) void {
        if (monospaced) {
            _ = win32.SendMessageW(self.peer, win32.WM_SETFONT, @intFromPtr(monospaceFont), 1);
        } else {
            _ = win32.SendMessageW(self.peer, win32.WM_SETFONT, @intFromPtr(captionFont), 1);
        }
    }
};

pub const Button = struct {
    peer: HWND,
    arena: std.heap.ArenaAllocator,

    pub usingnamespace Events(Button);

    pub fn create() !Button {
        const hwnd = win32.CreateWindowExW(win32.WS_EX_LEFT, // dwExtStyle
            _T("BUTTON"), // lpClassName
            _T(""), // lpWindowName
            @as(win32.WINDOW_STYLE, @enumFromInt(@intFromEnum(win32.WS_TABSTOP) | @intFromEnum(win32.WS_CHILD) | win32.BS_PUSHBUTTON | win32.BS_FLAT)), // dwStyle
            0, // X
            0, // Y
            100, // nWidth
            100, // nHeight
            defaultWHWND, // hWindParent
            null, // hMenu
            hInst, // hInstance
            null // lpParam
        ) orelse return Win32Error.InitializationError;
        try Button.setupEvents(hwnd);
        _ = win32.SendMessageW(hwnd, win32.WM_SETFONT, @intFromPtr(captionFont), 1);

        return Button{ .peer = hwnd, .arena = std.heap.ArenaAllocator.init(lib.internal.lasting_allocator) };
    }

    pub fn setLabel(self: *Button, label: [:0]const u8) void {
        const allocator = lib.internal.scratch_allocator;
        const wide = std.unicode.utf8ToUtf16LeAllocZ(allocator, label) catch return; // invalid utf8 or not enough memory
        defer allocator.free(wide);
        if (win32.SetWindowTextW(self.peer, wide) == 0) {
            std.os.windows.unexpectedError(transWinError(win32.GetLastError())) catch {};
        }
    }

    pub fn getLabel(self: *Button) [:0]const u8 {
        const allocator = self.arena.allocator();
        const len = win32.GetWindowTextLengthW(self.peer);
        var buf = allocator.allocSentinel(u16, @as(usize, @intCast(len)), 0) catch unreachable; // TODO return error
        defer allocator.free(buf);
        const realLen = @as(usize, @intCast(win32.GetWindowTextW(self.peer, buf.ptr, len + 1)));
        const utf16Slice = buf[0..realLen];
        const text = std.unicode.utf16leToUtf8AllocZ(allocator, utf16Slice) catch unreachable; // TODO return error
        return text;
    }

    pub fn setEnabled(self: *Button, enabled: bool) void {
        _ = win32.EnableWindow(self.peer, @intFromBool(enabled));
    }
};

pub const Dropdown = @import("Dropdown.zig");

pub const CheckBox = struct {
    peer: HWND,
    arena: std.heap.ArenaAllocator,

    pub usingnamespace Events(CheckBox);

    pub fn create() !CheckBox {
        const hwnd = win32.CreateWindowExW(win32.WS_EX_LEFT, // dwExtStyle
            _T("BUTTON"), // lpClassName
            _T(""), // lpWindowName
            @as(win32.WINDOW_STYLE, @enumFromInt(@intFromEnum(win32.WS_TABSTOP) | @intFromEnum(win32.WS_CHILD) | win32.BS_AUTOCHECKBOX)), // dwStyle
            0, // X
            0, // Y
            100, // nWidth
            100, // nHeight
            defaultWHWND, // hWindParent
            null, // hMenu
            hInst, // hInstance
            null // lpParam
        ) orelse return Win32Error.InitializationError;
        try CheckBox.setupEvents(hwnd);
        _ = win32.SendMessageW(hwnd, win32.WM_SETFONT, @intFromPtr(captionFont), 1);

        return CheckBox{ .peer = hwnd, .arena = std.heap.ArenaAllocator.init(lib.internal.lasting_allocator) };
    }

    pub fn setLabel(self: *CheckBox, label: [:0]const u8) void {
        const allocator = lib.internal.scratch_allocator;
        const wide = std.unicode.utf8ToUtf16LeAllocZ(allocator, label) catch return; // invalid utf8 or not enough memory
        defer allocator.free(wide);
        if (win32.SetWindowTextW(self.peer, wide) == 0) {
            std.os.windows.unexpectedError(transWinError(win32.GetLastError())) catch {};
        }
    }

    pub fn setEnabled(self: *CheckBox, enabled: bool) void {
        _ = win32.EnableWindow(self.peer, @intFromBool(enabled));
    }

    pub fn setChecked(self: *CheckBox, checked: bool) void {
        const state: win32.WPARAM = switch (checked) {
            true => @intFromEnum(win32.BST_CHECKED),
            false => @intFromEnum(win32.BST_UNCHECKED),
        };
        _ = win32.SendMessageW(self.peer, win32.BM_SETCHECK, state, 0);
    }

    pub fn isChecked(self: *CheckBox) bool {
        const state: win32.DLG_BUTTON_CHECK_STATE = @enumFromInt(
            win32.SendMessageW(self.peer, win32.BM_GETCHECK, 0, 0),
        );
        return state != win32.BST_UNCHECKED;
    }
};

pub const Slider = struct {
    peer: HWND,
    min: f32 = 0,
    max: f32 = 100,
    stepSize: f32 = 1,

    pub usingnamespace Events(Slider);

    pub fn create() !Slider {
        const hwnd = win32.CreateWindowExW(win32.WS_EX_LEFT, // dwExtStyle
            _T("msctls_trackbar32"), // lpClassName
            _T(""), // lpWindowName
            win32.WINDOW_STYLE.initFlags(.{ .TABSTOP = 0, .CHILD = 1 }), // dwStyle
            0, // X
            0, // Y
            100, // nWidth
            100, // nHeight
            defaultWHWND, // hWindParent
            null, // hMenu
            hInst, // hInstance
            null // lpParam
        ) orelse return Win32Error.InitializationError;
        try Slider.setupEvents(hwnd);
        _ = win32.SendMessageW(hwnd, win32.WM_SETFONT, @intFromPtr(captionFont), 1);

        return Slider{ .peer = hwnd };
    }

    pub fn getValue(self: *const Slider) f32 {
        const valueInt = win32.SendMessageW(self.peer, win32Backend.TBM_GETPOS, 0, 0);
        const value = @as(f32, @floatFromInt(valueInt)) * self.stepSize;
        return value;
    }

    pub fn setValue(self: *Slider, value: f32) void {
        const valueInt = @as(i32, @intFromFloat(value / self.stepSize));
        _ = win32.SendMessageW(self.peer, win32Backend.TBM_SETPOS, 1, valueInt);
    }

    pub fn setMinimum(self: *Slider, minimum: f32) void {
        self.min = minimum;
        self.updateMinMax();
    }

    pub fn setMaximum(self: *Slider, maximum: f32) void {
        self.max = maximum;
        self.updateMinMax();
    }

    pub fn setStepSize(self: *Slider, stepSize: f32) void {
        const value = self.getValue();
        self.stepSize = stepSize;
        self.updateMinMax();
        self.setValue(value);
    }

    fn updateMinMax(self: *const Slider) void {
        const maxInt = @as(i16, @intFromFloat(self.max / self.stepSize));
        const minInt = @as(i16, @intFromFloat(self.min / self.stepSize));
        _ = win32.SendMessageW(self.peer, win32Backend.TBM_SETRANGEMIN, 1, minInt);
        _ = win32.SendMessageW(self.peer, win32Backend.TBM_SETRANGEMAX, 1, maxInt);
    }

    pub fn setEnabled(self: *Slider, enabled: bool) void {
        _ = win32.EnableWindow(self.peer, @intFromBool(enabled));
    }
};

pub const Label = struct {
    peer: HWND,
    arena: std.heap.ArenaAllocator,

    pub usingnamespace Events(Label);

    pub fn create() !Label {
        const hwnd = win32.CreateWindowExW(win32.WS_EX_LEFT, // dwExtStyle
            L("STATIC"), // lpClassName
            L(""), // lpWindowName
            @as(win32.WINDOW_STYLE, @enumFromInt(@intFromEnum(win32.WINDOW_STYLE.initFlags(.{ .TABSTOP = 0, .CHILD = 1 })) | win32.SS_CENTERIMAGE)), // dwStyle
            0, // X
            0, // Y
            100, // nWidth
            100, // nHeight
            defaultWHWND, // hWindParent
            null, // hMenu
            hInst, // hInstance
            null // lpParam
        ) orelse return Win32Error.InitializationError;
        try Label.setupEvents(hwnd);
        _ = win32.SendMessageW(hwnd, win32.WM_SETFONT, @intFromPtr(captionFont), 1);

        return Label{ .peer = hwnd, .arena = std.heap.ArenaAllocator.init(lib.internal.lasting_allocator) };
    }

    pub fn setAlignment(self: *Label, alignment: f32) void {
        _ = self;
        _ = alignment;
    }

    pub fn setFont(self: *Label, font: lib.Font) void {
        _ = self;
        _ = font;
    }

    pub fn setText(self: *Label, text: []const u8) void {
        const allocator = lib.internal.scratch_allocator;
        const wide = std.unicode.utf8ToUtf16LeAllocZ(allocator, text) catch return; // invalid utf8 or not enough memory
        defer allocator.free(wide);
        if (win32.SetWindowTextW(self.peer, wide) == 0) {
            // win32.GetLastError() catch {};
        }
    }

    pub fn destroy(self: *Label) void {
        self.arena.deinit();
    }
};

pub const TabContainer = struct {
    /// Container that contains the tab control because win32 requires that
    peer: HWND,
    /// The actual tab control
    tabControl: HWND,
    arena: std.heap.ArenaAllocator,
    peerList: std.ArrayList(PeerType),
    shownPeer: ?PeerType = null,

    pub usingnamespace Events(TabContainer);

    var classRegistered = false;

    pub fn create() !TabContainer {
        if (!classRegistered) {
            var wc: win32.WNDCLASSEXW = .{
                .cbSize = @sizeOf(win32.WNDCLASSEXW),
                .style = win32.WNDCLASS_STYLES.initFlags(.{}),
                .lpfnWndProc = TabContainer.process,
                .cbClsExtra = 0,
                .cbWndExtra = 0,
                .hInstance = hInst,
                .hIcon = null, // TODO: LoadIcon
                .hCursor = defaultCursor,
                .hbrBackground = null,
                .lpszMenuName = null,
                .lpszClassName = _T("capyTabClass"),
                .hIconSm = null,
            };

            if (win32.RegisterClassExW(&wc) == 0) {
                showNativeMessageDialog(.Error, "Could not register window class capyTabClass", .{});
                return Win32Error.InitializationError;
            }
            classRegistered = true;
        }

        const wrapperHwnd = win32.CreateWindowExW(win32.WS_EX_LEFT, // dwExtStyle
            _T("capyTabClass"), // lpClassName
            _T(""), // lpWindowName
            @as(win32.WINDOW_STYLE, @enumFromInt(@intFromEnum(win32.WS_TABSTOP) | @intFromEnum(win32.WS_CHILD) | @intFromEnum(win32.WS_CLIPCHILDREN))), // dwStyle
            0, // X
            0, // Y
            100, // nWidth
            100, // nHeight
            defaultWHWND, // hWindParent
            null, // hMenu
            hInst, // hInstance
            null // lpParam
        ) orelse return Win32Error.InitializationError;

        const hwnd = win32.CreateWindowExW(win32.WS_EX_LEFT, // dwExtStyle
            _T("SysTabControl32"), // lpClassName
            _T(""), // lpWindowName
            @as(win32.WINDOW_STYLE, @enumFromInt(@intFromEnum(win32.WS_TABSTOP) | @intFromEnum(win32.WS_CHILD) | @intFromEnum(win32.WS_CLIPSIBLINGS))), // dwStyle
            0, // X
            0, // Y
            1000, // nWidth
            50, // nHeight
            defaultWHWND, // hWindParent
            null, // hMenu
            hInst, // hInstance
            null // lpParam
        ) orelse return Win32Error.InitializationError;
        try TabContainer.setupEvents(wrapperHwnd);
        _ = win32.SendMessageW(hwnd, win32.WM_SETFONT, @intFromPtr(captionFont), 0);
        _ = win32.SetParent(hwnd, wrapperHwnd);
        _ = win32.ShowWindow(hwnd, win32.SW_SHOWDEFAULT);
        _ = win32.UpdateWindow(hwnd);

        return TabContainer{
            .peer = wrapperHwnd,
            .tabControl = hwnd,
            .arena = std.heap.ArenaAllocator.init(lib.internal.lasting_allocator),
            .peerList = std.ArrayList(PeerType).init(lib.internal.lasting_allocator),
        };
    }

    fn onSelChange(data: *EventUserData, _: HWND, index: usize) void {
        const self = @as(*TabContainer, @ptrCast(@alignCast(data.peerPtr)));
        if (self.shownPeer) |previousPeer| {
            _ = win32.ShowWindow(previousPeer, win32.SW_HIDE);
        }
        const peer = self.peerList.items[index];
        _ = win32.SetParent(peer, self.peer);
        _ = win32.ShowWindow(peer, win32.SW_SHOWDEFAULT);
        _ = win32.UpdateWindow(peer);
        self.shownPeer = peer;
        TabContainer.reLayout(self.peer);
    }

    pub fn insert(self: *TabContainer, position: usize, peer: PeerType) usize {
        const item = win32Backend.TCITEMA{ .mask = 0 };
        const newIndex = win32Backend.TabCtrl_InsertItemW(self.tabControl, @as(c_int, @intCast(position)), &item);
        self.peerList.append(peer) catch unreachable;

        if (self.shownPeer == null) {
            _ = win32.SetParent(peer, self.peer);
            _ = win32.ShowWindow(peer, win32.SW_SHOWDEFAULT);
            _ = win32.UpdateWindow(peer);
            self.shownPeer = peer;
        }

        return @as(usize, @intCast(newIndex));
    }

    pub fn setLabel(self: *const TabContainer, position: usize, text: [:0]const u8) void {
        const item = win32Backend.TCITEMA{
            .mask = @intFromEnum(win32.TCIF_TEXT), // only change the text attribute
            .pszText = text,
            // cchTextMax doesn't need to be set when using SetItem
        };
        win32Backend.TabCtrl_SetItemW(self.tabControl, @as(c_int, @intCast(position)), &item);
    }

    pub fn getTabsNumber(self: *const TabContainer) usize {
        return @as(usize, @bitCast(win32Backend.TabCtrl_GetItemCountW(self.tabControl)));
    }

    fn reLayout(hwnd: HWND) void {
        var rect: RECT = undefined;
        _ = win32.GetWindowRect(hwnd, &rect);
        const child = win32.GetWindow(hwnd, win32.GW_CHILD);
        _ = win32.MoveWindow(child, 0, 50, rect.right - rect.left, rect.bottom - rect.top, 1);
    }

    fn onResize(_: *EventUserData, hwnd: HWND) void {
        TabContainer.reLayout(hwnd);
    }
};

// TODO: scroll using mouse wheel and using keyboard (arrow keys + page up/down)
pub const ScrollView = struct {
    peer: HWND,
    child: ?HWND = null,
    widget: ?*lib.Widget = null,

    pub usingnamespace Events(ScrollView);

    var classRegistered = false;

    pub fn create() !ScrollView {
        if (!classRegistered) {
            var wc: win32.WNDCLASSEXW = .{
                .cbSize = @sizeOf(win32.WNDCLASSEXW),
                .style = win32.WNDCLASS_STYLES.initFlags(.{}),
                .lpfnWndProc = ScrollView.process,
                .cbClsExtra = 0,
                .cbWndExtra = 0,
                .hInstance = hInst,
                .hIcon = null,
                .hCursor = defaultCursor,
                .hbrBackground = null,
                .lpszMenuName = null,
                .lpszClassName = _T("capyScrollViewClass"),
                .hIconSm = null,
            };

            if (win32.RegisterClassExW(&wc) == 0) {
                showNativeMessageDialog(.Error, "Could not register window class {s}", .{"capyScrollViewClass"});
                return Win32Error.InitializationError;
            }
            classRegistered = true;
        }

        const hwnd = win32.CreateWindowExW(win32.WS_EX_LEFT, // dwExtStyle
            _T("capyScrollViewClass"), // lpClassName
            _T(""), // lpWindowName
            @as(win32.WINDOW_STYLE, @enumFromInt(@intFromEnum(win32.WS_TABSTOP) | @intFromEnum(win32.WS_CHILD) | @intFromEnum(win32.WS_CLIPCHILDREN) | @intFromEnum(win32.WS_HSCROLL) | @intFromEnum(win32.WS_VSCROLL))), // dwStyle
            0, // X
            0, // Y
            100, // nWidth
            100, // nHeight
            defaultWHWND, // hWindParent
            null, // hMenu
            hInst, // hInstance
            null // lpParam
        ) orelse return Win32Error.InitializationError;
        try ScrollView.setupEvents(hwnd);
        return ScrollView{ .peer = hwnd };
    }

    pub fn setChild(self: *ScrollView, peer: PeerType, widget: *lib.Widget) void {
        // TODO: remove old widget if there was one
        self.child = peer;
        self.widget = widget;

        _ = win32.SetParent(peer, self.peer);
        const style = win32Backend.getWindowLongPtr(peer, win32.GWL_STYLE);
        _ = win32Backend.setWindowLongPtr(peer, win32.GWL_STYLE, style | @intFromEnum(win32.WS_CHILD));
        _ = win32.ShowWindow(peer, win32.SW_SHOWDEFAULT);
        _ = win32.UpdateWindow(peer);
    }

    pub fn onHScroll(_: *EventUserData, hwnd: HWND, newPos: usize) void {
        const child = win32.GetWindow(hwnd, win32.GW_CHILD);

        var parent: RECT = undefined;
        _ = win32.GetWindowRect(hwnd, &parent);

        var rect: RECT = undefined;
        _ = win32.GetWindowRect(child, &rect);
        _ = win32.MoveWindow(child, -@as(c_int, @intCast(newPos)), rect.top - parent.top, rect.right - rect.left, rect.bottom - rect.top, 1);
    }

    pub fn onVScroll(_: *EventUserData, hwnd: HWND, newPos: usize) void {
        const child = win32.GetWindow(hwnd, win32.GW_CHILD);

        var parent: RECT = undefined;
        _ = win32.GetWindowRect(hwnd, &parent);

        var rect: RECT = undefined;
        _ = win32.GetWindowRect(child, &rect);
        _ = win32.MoveWindow(child, rect.left - parent.left, -@as(c_int, @intCast(newPos)), rect.right - rect.left, rect.bottom - rect.top, 1);
    }

    pub fn onResize(data: *EventUserData, hwnd: HWND) void {
        const self = @as(*const ScrollView, @ptrCast(@alignCast(data.peerPtr)));

        // Get the child component's bounding box
        var rect: RECT = undefined;
        _ = win32.GetWindowRect(self.child.?, &rect);

        // Get the scroll view's bounding box
        var parent: RECT = undefined;
        _ = win32.GetWindowRect(hwnd, &parent);

        const width = parent.right - parent.left;
        const height = parent.bottom - parent.top;

        // Resize the child component to its preferred size (while keeping its current position)
        const preferred = self.widget.?.getPreferredSize(lib.Size.init(std.math.maxInt(u32), std.math.maxInt(u32)));

        const child = win32.GetWindow(hwnd, win32.GW_CHILD);
        _ = win32.MoveWindow(
            child,
            @max(rect.left - parent.left, @min(0, -(@as(c_int, @intFromFloat(preferred.width)) - width))),
            @max(rect.top - parent.top, @min(0, -(@as(c_int, @intFromFloat(preferred.height)) - height))),
            @as(c_int, @intFromFloat(preferred.width)),
            @as(c_int, @intFromFloat(preferred.height)),
            1,
        );

        // Finally, update the scroll bars
        var horizontalScrollInfo = win32.SCROLLINFO{
            .cbSize = @sizeOf(win32.SCROLLINFO),
            .fMask = @as(win32.SCROLLINFO_MASK, @enumFromInt(@intFromEnum(win32.SIF_RANGE) | @intFromEnum(win32.SIF_PAGE))),
            .nMin = 0,
            .nMax = @as(c_int, @intFromFloat(preferred.width)),
            .nPage = @as(c_uint, @intCast(width)),
            .nPos = 0,
            .nTrackPos = 0,
        };
        _ = win32.SetScrollInfo(self.peer, win32.SB_HORZ, &horizontalScrollInfo, 1);

        var verticalScrollInfo = win32.SCROLLINFO{
            .cbSize = @sizeOf(win32.SCROLLINFO),
            .fMask = @as(win32.SCROLLINFO_MASK, @enumFromInt(@intFromEnum(win32.SIF_RANGE) | @intFromEnum(win32.SIF_PAGE))),
            .nMin = 0,
            .nMax = @as(c_int, @intFromFloat(preferred.height)),
            .nPage = @as(c_uint, @intCast(height)),
            .nPos = 0,
            .nTrackPos = 0,
        };
        _ = win32.SetScrollInfo(self.peer, win32.SB_VERT, &verticalScrollInfo, 1);
    }
};

const ContainerStruct = struct { hwnd: HWND, count: usize, index: usize };

pub const Container = struct {
    peer: HWND,

    pub usingnamespace Events(Container);

    var classRegistered = false;

    pub fn create() !Container {
        if (!classRegistered) {
            var wc: win32.WNDCLASSEXW = .{
                .cbSize = @sizeOf(win32.WNDCLASSEXW),
                .style = win32.WNDCLASS_STYLES.initFlags(.{}),
                .lpfnWndProc = Container.process,
                .cbClsExtra = 0,
                .cbWndExtra = 0,
                .hInstance = hInst,
                .hIcon = null, // TODO: LoadIcon
                .hCursor = defaultCursor,
                .hbrBackground = null,
                .lpszMenuName = null,
                .lpszClassName = L("capyContainerClass"),
                .hIconSm = null,
            };

            if ((win32.RegisterClassExW(&wc)) == 0) {
                showNativeMessageDialog(.Error, "Could not register window class {s}", .{"capyContainerClass"});
                return Win32Error.InitializationError;
            }
            classRegistered = true;
        }

        const hwnd = win32.CreateWindowExW(win32.WINDOW_EX_STYLE.initFlags(.{ .CONTROLPARENT = 1 }), // dwExtStyle
            L("capyContainerClass"), // lpClassName
            L(""), // lpWindowName
            win32.WINDOW_STYLE.initFlags(.{ .TABSTOP = 0, .CHILD = 1, .CLIPCHILDREN = 1 }), // dwStyle
            0, // X
            0, // Y
            100, // nWidth
            100, // nHeight
            defaultWHWND, // hWindParent
            null, // hMenu
            hInst, // hInstance
            null // lpParam
        ) orelse return Win32Error.InitializationError;
        try Container.setupEvents(hwnd);

        return Container{ .peer = hwnd };
    }

    fn onGotFocus(hwnd: HWND) void {
        // TODO: check whether Shift+Tab was used, in which case go to the last child instead of the first
        if (win32.GetWindow(hwnd, win32.GW_CHILD)) |child| {
            _ = child;
            // _ = win32.SetFocus(child);
        }
    }

    pub fn add(self: *Container, peer: PeerType) void {
        _ = win32.SetParent(peer, self.peer);
        const style = win32Backend.getWindowLongPtr(peer, win32.GWL_STYLE);
        _ = win32Backend.setWindowLongPtr(peer, win32.GWL_STYLE, style | @intFromEnum(win32.WS_CHILD));
        _ = win32.ShowWindow(peer, win32.SW_SHOWDEFAULT);
        _ = win32.UpdateWindow(peer);
    }

    pub fn remove(self: *const Container, peer: PeerType) void {
        _ = self;
        _ = win32.ShowWindow(peer, win32.SW_HIDE);
    }

    pub fn move(self: *const Container, peer: PeerType, x: u32, y: u32) void {
        _ = self;
        var rect: RECT = undefined;
        _ = win32.GetWindowRect(peer, &rect);
        _ = win32.MoveWindow(peer, @as(c_int, @intCast(x)), @as(c_int, @intCast(y)), rect.right - rect.left, rect.bottom - rect.top, 1);
    }

    pub fn resize(self: *const Container, peer: PeerType, width: u32, height: u32) void {
        const data = getEventUserData(peer);

        var rect: RECT = undefined;
        _ = win32.GetWindowRect(peer, &rect);
        if (rect.right - rect.left == width and rect.bottom - rect.top == height) {
            return;
        }

        var parent: RECT = undefined;
        _ = win32.GetWindowRect(self.peer, &parent);
        _ = win32.MoveWindow(
            peer,
            rect.left - parent.left,
            rect.top - parent.top,
            @as(c_int, @intCast(width)),
            @as(c_int, @intCast(height)) + data.extra_height,
            1,
        );
    }

    /// In order to work, 'peers' should contain all peers and be sorted in tab order
    pub fn setTabOrder(self: *const Container, peers: []const PeerType) void {
        _ = self;
        for (0..peers.len) |i| {
            const peer = peers[i];
            const previous_peer: ?PeerType = if (i > 0) peers[i - 1] else null;
            _ = win32.SetWindowPos(
                peer,
                previous_peer,
                0,
                0,
                0,
                0,
                win32.SET_WINDOW_POS_FLAGS.initFlags(.{ .NOMOVE = 1, .NOSIZE = 1 }),
            );
        }
    }
};

pub const AudioGenerator = struct {
    pub fn create(sampleRate: f32) !AudioGenerator {
        _ = sampleRate;
        return AudioGenerator{};
    }

    pub fn getBuffer(self: AudioGenerator, channel: u16) []f32 {
        _ = channel;
        _ = self;
        return &([0]f32{});
    }

    pub fn copyBuffer(self: AudioGenerator, channel: u16) void {
        _ = channel;
        _ = self;
    }

    pub fn doneWrite(self: AudioGenerator) void {
        _ = self;
    }

    pub fn deinit(self: AudioGenerator) void {
        _ = self;
    }
};

pub fn runStep(step: shared.EventLoopStep) bool {
    var msg: MSG = undefined;
    switch (step) {
        .Blocking => {
            if (win32.GetMessageW(&msg, null, 0, 0) <= 0) {
                return false; // error or WM_QUIT message
            }
        },
        .Asynchronous => {
            if (win32.PeekMessageW(&msg, null, 0, 0, .REMOVE) == 0) {
                return true; // no message available
            }
        },
    }

    if ((msg.message & 0xFF) == 0x012) { // WM_QUIT
        return false;
    }

    const process_event = win32.IsDialogMessageW(defaultWHWND, &msg) == 0;
    if (process_event) {
        _ = win32.TranslateMessage(&msg);
        _ = win32.DispatchMessageW(&msg);
    } else {
        // std.log.info("dialog message", .{});
    }
    return true;
}
