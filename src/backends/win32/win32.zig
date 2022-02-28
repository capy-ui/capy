const std = @import("std");

pub usingnamespace std.os.windows.user32;
pub usingnamespace std.os.windows.kernel32;

pub const HINSTANCE = std.os.windows.HINSTANCE;
pub const HWND = std.os.windows.HWND;
pub const WPARAM = std.os.windows.WPARAM;
pub const LPARAM = std.os.windows.LPARAM;
pub const LRESULT = std.os.windows.LRESULT;
pub const RECT = std.os.windows.RECT;
pub const LPRECT = *RECT;
pub const WINAPI = std.os.windows.WINAPI;
pub const HDC = std.os.windows.HDC;
pub const HBRUSH = std.os.windows.HBRUSH;
pub const HFONT = *opaque {};
pub const COLORREF = std.os.windows.DWORD;
pub const BOOL = std.os.windows.BOOL;
pub const BYTE = std.os.windows.BYTE;
pub const LONG = std.os.windows.LONG;
pub const ULONG = std.os.windows.ULONG;
pub const UINT = std.os.windows.UINT;
pub const INT = std.os.windows.INT;
pub const DWORD = std.os.windows.DWORD;
pub const HGDIOBJ = *opaque {};

pub const BS_DEFPUSHBUTTON = 1;
pub const BS_FLAT = 0x00008000;

pub const SWP_NOACTIVATE = 0x0010;
pub const SWP_NOOWNERZORDER = 0x0200;
pub const SWP_NOZORDER = 0x0004;

pub const BN_CLICKED = 0;

pub const WNDENUMPROC = fn (hwnd: HWND, lParam: LPARAM) callconv(WINAPI) c_int;

pub extern "user32" fn SetParent(child: HWND, newParent: HWND) callconv(WINAPI) HWND;
pub extern "user32" fn SetWindowTextW(hWnd: HWND, lpString: [*:0]const u16) callconv(WINAPI) c_int;
pub extern "user32" fn GetWindowTextW(hWnd: HWND, lpString: [*:0]const u16, nMaxCount: c_int) callconv(WINAPI) c_int;
pub extern "user32" fn GetWindowTextLengthW(hWnd: HWND) callconv(WINAPI) c_int;
pub extern "user32" fn EnumChildWindows(hWndParent: HWND, lpEnumFunc: WNDENUMPROC, lParam: LPARAM) callconv(WINAPI) c_int;
pub extern "user32" fn GetParent(hWnd: HWND) callconv(WINAPI) HWND;
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

// Common Controls
pub extern "comctl32" fn InitCommonControlsEx(picce: [*c]const INITCOMMONCONTROLSEX) callconv(WINAPI) c_int;
pub const INITCOMMONCONTROLSEX = extern struct { dwSize: c_uint, dwICC: c_uint };

// zig fmt: off
pub const PAINTSTRUCT = extern struct {
    hdc: HDC,
    fErase: BOOL,
    rcPaint: RECT,
    fRestore: BOOL,
    fIncUpdate: BOOL,
    rgbReserved: [32]BYTE
};
// zig fmt: on

pub const POINT = extern struct { x: LONG, y: LONG };

pub const SIZE = extern struct { cx: std.os.windows.LONG, cy: std.os.windows.LONG };

pub fn GetWindowLongPtr(hWnd: HWND, nIndex: c_int) usize {
    switch (@import("builtin").cpu.arch) {
        .x86_64 => return @bitCast(usize, std.os.windows.user32.GetWindowLongPtrA(hWnd, nIndex)),
        .i386 => return @bitCast(usize, std.os.windows.user32.GetWindowLongA(hWnd, nIndex)),
        else => @compileError("Unsupported architecture."),
    }
}

pub fn SetWindowLongPtr(hWnd: HWND, nIndex: c_int, dwNewLong: usize) void {
    switch (@import("builtin").cpu.arch) {
        .x86_64 => _ = std.os.windows.user32.SetWindowLongPtrA(hWnd, nIndex, @bitCast(isize, dwNewLong)),
        .i386 => _ = std.os.windows.user32.SetWindowLongA(hWnd, nIndex, @bitCast(isize, dwNewLong)),
        else => @compileError("Unsupported architecture."),
    }
}

pub const ICC_STANDARD_CLASSES = 0x00004000;

// GDI+ part, based on https://docs.microsoft.com/en-us/windows/win32/gdiplus/-gdiplus-flatapi-flat
pub const GpGraphics = *opaque {};
pub const GpStatus = enum(c_int) { Ok, GenericError, InvalidParameter, OutOfMemory, ObjectBusy, InsufficientBuffer, NotImplemented, Win32Error, WrongState, Aborted, FileNotFound, ValueOverflow, AccessDenied, UnknownImageFormat, FontFamilyNotFound, FontStyleNotFound, NotTrueTypeFont, UnsupportedGdiplusVersion, GdiplusNotInitialized, PropertyNotFound, PropertyNotSupported, ProfileNotFound };

pub const DebugEventLevel = enum(c_int) { DebugEventLevelFatal, DebugEventLevelWarning };

pub const DebugEventProc = fn (level: DebugEventLevel, message: [*]const u8) callconv(.C) void;
pub const GdiplusStartupInput = extern struct { GdiplusVersion: u32 = 1, DebugEventCallback: ?DebugEventProc = null, SuppressBackgroundThread: BOOL = 0, SuppressExternalCodecs: BOOL = 0, GdiplusStartupInput: ?fn (debugEventCallback: DebugEventProc, suppressBackgroundThread: BOOL, supressExternalCodecs: BOOL) callconv(.C) void = null };

pub const GdiplusStartupOutput = extern struct {
    NotificationHookProc: fn () callconv(.C) void, // TODO
    NotificationUnhookProc: fn () callconv(.C) void, // TODO
};

pub extern "gdiplus" fn GdipCreateFromHDC(hdc: HDC, graphics: *GpGraphics) GpStatus;
pub extern "gdiplus" fn GdiplusStartup(token: *ULONG, input: ?*GdiplusStartupInput, output: ?*GdiplusStartupOutput) GpStatus;
pub extern "gdiplus" fn GdiplusShutdown(token: *ULONG) void;
