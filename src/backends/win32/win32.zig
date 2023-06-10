const std = @import("std");

pub usingnamespace std.os.windows.user32;
pub usingnamespace std.os.windows.kernel32;

pub const HINSTANCE = std.os.windows.HINSTANCE;
pub const HWND = @import("zigwin32").everything.HWND;
pub const WPARAM = std.os.windows.WPARAM;
pub const LPARAM = std.os.windows.LPARAM;
pub const LRESULT = std.os.windows.LRESULT;
pub const RECT = std.os.windows.RECT;
pub const LPRECT = *RECT;
pub const WINAPI = std.os.windows.WINAPI;
pub const HDC = std.os.windows.HDC;
pub const HBRUSH = std.os.windows.HBRUSH;
pub const HMENU = std.os.windows.HMENU;
pub const HFONT = *opaque {};
pub const HRGN = *opaque {};
pub const HCURSOR = std.os.windows.HCURSOR;
pub const COLORREF = std.os.windows.DWORD;
pub const BOOL = std.os.windows.BOOL;
pub const BYTE = std.os.windows.BYTE;
pub const LONG = std.os.windows.LONG;
pub const ULONG = std.os.windows.ULONG;
pub const UINT = std.os.windows.UINT;
pub const INT = std.os.windows.INT;
pub const DWORD = std.os.windows.DWORD;
pub const CHAR = std.os.windows.CHAR;
pub const HGDIOBJ = *opaque {};

pub const BS_PUSHBUTTON = 0;
pub const BS_DEFPUSHBUTTON = 1;
pub const BS_CHECKBOX = 2;
pub const BS_AUTOCHECKBOX = 3;
pub const BS_AUTORADIOBUTTON = 9;
pub const BS_FLAT = 0x00008000;

pub const BST_CHECKED = 1;
pub const BST_INDETERMINATE = 2;
pub const BST_UNCHECKED = 0;

// TRACKBAR control
pub const TBM_SETPOS = 0x0405;

// STATIC controls
/// Centers text horizontally.
pub const SS_CENTER = 0x00000001;
/// Centers text vertically.
pub const SS_CENTERIMAGE = 0x00000200;

pub const SWP_NOACTIVATE = 0x0010;
pub const SWP_NOOWNERZORDER = 0x0200;
pub const SWP_NOZORDER = 0x0004;

pub const WS_EX_COMPOSITED = 0x02000000;

pub const BN_CLICKED = 0;
pub const EN_CHANGE = 0x0300;

pub const SPI_GETNONCLIENTMETRICS = 0x0029;

/// Standard arrow cursor.
pub const IDC_ARROW = @intToPtr([*:0]const u8, 32512);

pub const WNDENUMPROC = *const fn (hwnd: HWND, lParam: LPARAM) callconv(WINAPI) c_int;

pub extern "user32" fn SendMessageA(hWnd: HWND, Msg: UINT, wParam: WPARAM, lParam: LPARAM) callconv(WINAPI) LRESULT;
pub extern "user32" fn SetParent(child: HWND, newParent: ?HWND) callconv(WINAPI) ?HWND;
pub extern "user32" fn SetWindowTextW(hWnd: HWND, lpString: [*:0]const u16) callconv(WINAPI) c_int;
pub extern "user32" fn GetWindowTextW(hWnd: HWND, lpString: [*:0]const u16, nMaxCount: c_int) callconv(WINAPI) c_int;
pub extern "user32" fn GetWindowTextLengthW(hWnd: HWND) callconv(WINAPI) c_int;
pub extern "user32" fn EnumChildWindows(hWndParent: HWND, lpEnumFunc: WNDENUMPROC, lParam: LPARAM) callconv(WINAPI) c_int;
pub extern "user32" fn GetParent(hWnd: HWND) callconv(WINAPI) HWND;
pub extern "user32" fn GetWindow(hWnd: HWND, uCmd: UINT) callconv(WINAPI) HWND;
pub extern "user32" fn GetWindowRect(hWnd: HWND, lpRect: LPRECT) callconv(WINAPI) c_int;
pub extern "user32" fn GetClientRect(hWnd: HWND, lpRect: LPRECT) callconv(WINAPI) c_int;
pub extern "user32" fn SetWindowPos(hWnd: HWND, hWndInsertAfter: HWND, X: c_int, Y: c_int, cx: c_int, cy: c_int, uFlags: c_uint) callconv(WINAPI) c_int;
pub extern "user32" fn MoveWindow(hWnd: HWND, X: c_int, Y: c_int, nWidth: c_int, nHeight: c_int, repaint: c_int) callconv(WINAPI) c_int;
pub extern "user32" fn BeginPaint(hWnd: HWND, lpPaint: *PAINTSTRUCT) callconv(WINAPI) HDC;
pub extern "user32" fn EndPaint(hWnd: HWND, lpPaint: *const PAINTSTRUCT) callconv(WINAPI) BOOL;
pub extern "gdi32" fn CreateSolidBrush(color: COLORREF) callconv(WINAPI) ?HBRUSH;
pub extern "gdi32" fn DeleteObject(ho: HGDIOBJ) callconv(WINAPI) BOOL;
pub extern "gdi32" fn SelectObject(hdc: HDC, h: HGDIOBJ) callconv(WINAPI) void;
pub extern "gdi32" fn Rectangle(hdc: HDC, left: c_int, top: c_int, right: c_int, bottom: c_int) callconv(WINAPI) BOOL;
pub extern "gdi32" fn Ellipse(hdc: HDC, left: c_int, top: c_int, right: c_int, bottom: c_int) callconv(WINAPI) BOOL;
pub extern "gdi32" fn ExtTextOutA(hdc: HDC, x: c_int, y: c_int, options: UINT, lprect: ?*const RECT, lpString: [*]const u8, c: UINT, lpDx: ?*const INT) callconv(WINAPI) BOOL;
pub extern "gdi32" fn GetTextExtentPoint32A(hdc: HDC, lpString: [*]const u8, c: c_int, psizl: *SIZE) callconv(WINAPI) BOOL;
pub extern "gdi32" fn CreateFontA(cHeight: c_int, cWidth: c_int, cEscapement: c_int, cOrientation: c_int, cWeight: c_int, bItalic: DWORD, bUnderline: DWORD, bStrikeOut: DWORD, iCharSet: DWORD, iOutPrecision: DWORD, iClipPrecision: DWORD, iQuality: DWORD, iPitchAndFamily: DWORD, pszFaceName: std.os.windows.LPCSTR) callconv(WINAPI) ?HFONT;
pub extern "gdi32" fn CreateFontIndirectA(lplf: *const LOGFONTA) callconv(WINAPI) ?HFONT;
pub extern "gdi32" fn GetStockObject(i: c_int) callconv(WINAPI) HGDIOBJ;
pub extern "gdi32" fn CreateCompatibleDC(hdc: ?HDC) callconv(WINAPI) ?HDC;
pub extern "gdi32" fn SetDCBrushColor(hdc: HDC, color: COLORREF) callconv(WINAPI) COLORREF;
pub extern "gdi32" fn GetDCBrushColor(hdc: HDC) callconv(WINAPI) COLORREF;
pub extern "gdi32" fn SetTextColor(hdc: HDC, color: COLORREF) callconv(WINAPI) COLORREF;
pub extern "gdi32" fn GetSysColorBrush(nIndex: c_int) callconv(WINAPI) ?HBRUSH;
pub extern "gdi32" fn MoveToEx(hdc: HDC, x: c_int, y: c_int, lppt: ?*POINT) callconv(WINAPI) BOOL;
pub extern "gdi32" fn LineTo(hdc: HDC, x: c_int, y: c_int) callconv(WINAPI) BOOL;
pub extern "user32" fn GetWindowRgnBox(hWnd: HWND, lprc: LPRECT) callconv(WINAPI) c_int;
pub extern "user32" fn InvalidateRect(hWnd: HWND, lpRect: *const RECT, bErase: BOOL) callconv(WINAPI) BOOL;
pub extern "user32" fn GetWindowExtEx(hdc: HDC, lpsize: *SIZE) callconv(WINAPI) BOOL;
pub extern "user32" fn EnableWindow(hWnd: HWND, enable: BOOL) callconv(WINAPI) BOOL;
pub extern "user32" fn SystemParametersInfoA(uiAction: UINT, uiParam: UINT, pvParam: ?*anyopaque, fWinIni: UINT) callconv(WINAPI) BOOL;
pub extern "user32" fn LoadCursorA(hInst: ?HINSTANCE, lpCursorName: std.os.windows.LPCSTR) callconv(WINAPI) HCURSOR;

// stock objects constants
pub const WHITE_BRUSH = 0;
pub const LTGRAY_BRUSH = 1;
pub const GRAY_BRUSH = 2;
pub const DKGRAY_BRUSH = 3;
pub const BLACK_BRUSH = 4;
pub const NULL_BRUSH = 5;
pub const WHITE_PEN = 6;
pub const BLACK_PEN = 7;
pub const NULL_PEN = 8;
pub const OEM_FIXED_FONT = 10;
pub const ANSI_FIXED_FONT = 11;
pub const ANSI_VAR_FONT = 12;
pub const SYSTEM_FONT = 13;
pub const DEVICE_DEFAULT_FONT = 14;
pub const DEFAULT_PALETTE = 15;
pub const SYSTEM_FIXED_FONT = 16;
pub const DEFAULT_GUI_FONT = 17;
pub const DC_BRUSH = 18;
pub const DC_PEN = 19;

// font weights
pub const FW_DONTCARE = 0;
pub const FW_THIN = 100;
pub const FW_LIGHT = 300;
pub const FW_NORMAL = 400;
pub const FW_BOLD = 700;

// system colors constants (only those that are also supported on Windows 10 are present)
pub const COLOR_WINDOW = 5;
pub const COLOR_WINDOWTEXT = 6;
pub const COLOR_HIGHLIGHT = 13;
pub const COLOR_HIGHLIGHTTEXT = 14;
pub const COLOR_3DFACE = 15;
pub const COLOR_GRAYTEXT = 17;
pub const COLOR_BTNTEXT = 18;
pub const COLOR_HOTLIGHT = 26;

// properties for GetWindow
pub const GW_HWNDFIRST = 0;
pub const GW_HWNDLAST = 1;
pub const GW_HWNDNEXT = 2;
pub const GW_HWNDPREV = 3;
pub const GW_OWNER = 4;
pub const GW_CHILD = 5;
pub const GW_ENABLEDPOPUP = 6;

// High DPI support
pub const DPI_AWARENESS_CONTEXT = INT;
pub const DPI_AWARENESS_CONTEXT_UNAWARE = -1;
pub const DPI_AWARENESS_CONTEXT_SYSTEM_AWARE = -2;
pub const DPI_AWARENESS_CONTEXT_PER_MONITOR_AWARE = -3;
pub const DPI_AWARENESS_CONTEXT_PER_MONITOR_AWARE_V2 = -4;
pub const DPI_AWARENESS_CONTEXT_UNAWARE_GDISCALED = -5;

pub const WM_DPICHANGED = 0x02E0;

pub extern "user32" fn SetProcessDpiAwarenessContext(value: DPI_AWARENESS_CONTEXT) callconv(WINAPI) BOOL;

// Common Controls
pub extern "comctl32" fn InitCommonControlsEx(picce: [*c]const INITCOMMONCONTROLSEX) callconv(WINAPI) c_int;
pub const INITCOMMONCONTROLSEX = extern struct { dwSize: c_uint, dwICC: c_uint };

pub const PAINTSTRUCT = extern struct {
    hdc: HDC,
    fErase: BOOL,
    rcPaint: RECT,
    fRestore: BOOL,
    fIncUpdate: BOOL,
    rgbReserved: [32]BYTE,
};

pub const POINT = extern struct { x: LONG, y: LONG };

pub const SIZE = extern struct { cx: std.os.windows.LONG, cy: std.os.windows.LONG };

pub const NMHDR = extern struct {
    hwndFrom: HWND,
    idFrom: UINT,
    code: UINT,
};

pub const LOGFONTA = extern struct {
    lfHeight: LONG,
    lfWidth: LONG,
    lfEscapement: LONG,
    lfOrientation: LONG,
    lfWeight: LONG,
    lfItalic: BYTE,
    lfUnderline: BYTE,
    lfStrikeOut: BYTE,
    lfCharSet: BYTE,
    lfOutPrecision: BYTE,
    lfClipPrecision: BYTE,
    lfQuality: BYTE,
    lfPitchAndFamily: BYTE,
    lfFaceName: [32]CHAR,
};

pub const NONCLIENTMETRICSA = extern struct {
    cbSize: UINT = @sizeOf(NONCLIENTMETRICSA),
    iBorderWidth: c_int,
    iScrollWidth: c_int,
    iScrollHeight: c_int,
    iCaptionWidth: c_int,
    iCaptionHeight: c_int,
    lfCaptionFont: LOGFONTA,
    iSmCaptionWidth: c_int,
    iSmCaptionHeight: c_int,
    lfSmCaptionFont: LOGFONTA,
    iMenuWidth: c_int,
    iMenuHeight: c_int,
    lfMenuFont: LOGFONTA,
    lfStatusFont: LOGFONTA,
    lfMessageFont: LOGFONTA,
    iPaddedBorderWidth: c_int,
};

pub fn GetWindowLongPtr(hWnd: HWND, nIndex: c_int) usize {
    switch (comptime @import("builtin").cpu.arch.ptrBitWidth()) {
        64 => return @bitCast(usize, std.os.windows.user32.GetWindowLongPtrA(hWnd, nIndex)),
        32 => return @bitCast(usize, std.os.windows.user32.GetWindowLongA(hWnd, nIndex)),
        else => @compileError("Unsupported architecture."),
    }
}

pub fn SetWindowLongPtr(hWnd: HWND, nIndex: c_int, dwNewLong: usize) void {
    switch (comptime @import("builtin").cpu.arch.ptrBitWidth()) {
        64 => _ = std.os.windows.user32.SetWindowLongPtrA(hWnd, nIndex, @bitCast(isize, dwNewLong)),
        32 => _ = std.os.windows.user32.SetWindowLongA(hWnd, nIndex, @bitCast(isize, dwNewLong)),
        else => @compileError("Unsupported architecture."),
    }
}

pub const ICC_STANDARD_CLASSES = 0x00004000;
pub const ICC_WIN95_CLASSES = 0x000000FF;

// Common Control: Tabs
const TCM_FIRST = 0x1300;
pub const TCM_GETITEMCOUNT = TCM_FIRST + 4;
pub const TCM_GETITEMA = TCM_FIRST + 5;
pub const TCM_GETITEMW = TCM_FIRST + 60;
pub const TCM_SETITEMA = TCM_FIRST + 6;
pub const TCM_SETITEMW = TCM_FIRST + 61;
pub const TCM_INSERTITEMA = TCM_FIRST + 7;
pub const TCM_INSERTITEMW = TCM_FIRST + 62;

const TCN_FIRST = @as(UINT, 0) -% 550;
pub const TCN_SELCHANGE = TCN_FIRST - 1;
pub const TCN_SELCHANGING = TCN_FIRST - 2;

pub const TCIF_TEXT = 0x0001;
pub const TCIF_IMAGE = 0x0002;
pub const TCIF_RTLLEADING = 0x0004;
pub const TCIF_PARAM = 0x0008;
pub const TCIF_STATE = 0x0010;

pub const TCITEMA = extern struct {
    mask: UINT,
    dwState: DWORD = undefined,
    dwStateMask: DWORD = undefined,
    pszText: ?[*:0]const u8 = undefined,
    /// Size in TCHAR of the pszText string
    cchTextMax: c_int = undefined,
    iImage: c_int = -1,
    /// Userdata
    lParam: LPARAM = undefined,
};

pub fn TabCtrl_InsertItemA(hWnd: HWND, index: c_int, tabItem: *const TCITEMA) LRESULT {
    const newIndex = SendMessageA(hWnd, TCM_INSERTITEMA, @intCast(c_uint, index), @bitCast(isize, @ptrToInt(tabItem)));
    if (newIndex == -1) {
        @panic("Failed to insert tab");
    }
    return newIndex;
}

pub fn TabCtrl_GetItemA(hWnd: HWND, index: c_int, out: *TCITEMA) void {
    if (SendMessageA(hWnd, TCM_GETITEMA, @intCast(c_uint, index), @bitCast(isize, @ptrToInt(out))) == 0) {
        @panic("Failed to get tab");
    }
}

pub fn TabCtrl_SetItemA(hWnd: HWND, index: c_int, tabItem: *const TCITEMA) void {
    if (SendMessageA(hWnd, TCM_SETITEMA, @intCast(c_uint, index), @bitCast(isize, @ptrToInt(tabItem))) == 0) {
        @panic("Failed to set tab");
    }
}

pub fn TabCtrl_GetItemCount(hWnd: HWND) LRESULT {
    return SendMessageA(hWnd, TCM_GETITEMCOUNT, 0, 0);
}

// Common Control: Scroll Bar
pub const SIF_RANGE = 0x0001;
pub const SIF_PAGE = 0x0002;
pub const SIF_POS = 0x0004;
pub const SIF_DISABLENOSCROLL = 0x0008;
pub const SIF_TRACKPOS = 0x0010;
pub const SIF_ALL = SIF_RANGE | SIF_PAGE | SIF_POS | SIF_DISABLENOSCROLL | SIF_TRACKPOS;

pub const SB_LINEUP = 0;
pub const SB_LINELEFT = 0;
pub const SB_LINEDOWN = 1;
pub const SB_LINERIGHT = 1;
pub const SB_PAGEUP = 2;
pub const SB_PAGELEFT = 2;
pub const SB_PAGEDOWN = 3;
pub const SB_PAGERIGHT = 3;
pub const SB_THUMBPOSITION = 4;
pub const SB_THUMBTRACK = 5;
pub const SB_TOP = 6;
pub const SB_LEFT = 6;
pub const SB_BOTTOM = 7;
pub const SB_RIGHT = 7;
pub const SB_ENDSCROLL = 8;

pub const SCROLLINFO = extern struct {
    cbSize: UINT = @sizeOf(SCROLLINFO),
    fMask: UINT,
    nMin: c_int = undefined,
    nMax: c_int = undefined,
    nPage: UINT = undefined,
    nPos: c_int = undefined,
    nTrackPos: c_int = undefined,
};

pub const SB_HORZ = 0;
pub const SB_VERT = 1;
pub const SB_CTL = 2;
pub const SB_BOTH = 3;

pub const SW_INVALIDATE = 0x0002;

pub extern "comctl32" fn GetScrollInfo(hWnd: HWND, nBar: c_int, lpsi: *SCROLLINFO) callconv(WINAPI) BOOL;
pub extern "comctl32" fn SetScrollInfo(hWnd: HWND, nBar: c_int, lpsi: *const SCROLLINFO, redraw: BOOL) callconv(WINAPI) c_int;
pub extern "comctl32" fn EnableScrollBar(hWnd: HWND, wSBflags: UINT, wArrows: UINT) callconv(WINAPI) BOOL;
pub extern "comctl32" fn ScrollWindowEx(hWnd: HWND, dx: c_int, dy: c_int, prcScroll: ?*const RECT, prcClip: ?*const RECT, hrgnUpdate: ?HRGN, prcUpdate: ?LPRECT, flags: UINT) callconv(WINAPI) c_int;

// GDI+ part, based on https://docs.microsoft.com/en-us/windows/win32/gdiplus/-gdiplus-flatapi-flat
pub const GpGraphics = *opaque {};
pub const GpStatus = enum(c_int) { Ok, GenericError, InvalidParameter, OutOfMemory, ObjectBusy, InsufficientBuffer, NotImplemented, Win32Error, WrongState, Aborted, FileNotFound, ValueOverflow, AccessDenied, UnknownImageFormat, FontFamilyNotFound, FontStyleNotFound, NotTrueTypeFont, UnsupportedGdiplusVersion, GdiplusNotInitialized, PropertyNotFound, PropertyNotSupported, ProfileNotFound };

pub const DebugEventLevel = enum(c_int) { DebugEventLevelFatal, DebugEventLevelWarning };

pub const DebugEventProc = *const fn (level: DebugEventLevel, message: [*]const u8) callconv(.C) void;
pub const GdiplusStartupInput = extern struct {
    GdiplusVersion: u32 = 1,
    DebugEventCallback: ?DebugEventProc = null,
    SuppressBackgroundThread: BOOL = 0,
    SuppressExternalCodecs: BOOL = 0,
    GdiplusStartupInput: ?*const fn (debugEventCallback: DebugEventProc, suppressBackgroundThread: BOOL, supressExternalCodecs: BOOL) callconv(.C) void = null,
};

pub const GdiplusStartupOutput = extern struct {
    NotificationHookProc: *const fn () callconv(.C) void, // TODO
    NotificationUnhookProc: *const fn () callconv(.C) void, // TODO
};

pub extern "gdiplus" fn GdipCreateFromHDC(hdc: HDC, graphics: *GpGraphics) callconv(WINAPI) GpStatus;
pub extern "gdiplus" fn GdiplusStartup(token: *ULONG, input: ?*GdiplusStartupInput, output: ?*GdiplusStartupOutput) callconv(WINAPI) GpStatus;
pub extern "gdiplus" fn GdiplusShutdown(token: *ULONG) callconv(WINAPI) void;
