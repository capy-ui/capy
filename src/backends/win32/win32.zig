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

pub const BS_DEFPUSHBUTTON = 1;
pub const BS_FLAT = 0x00008000;

pub const SWP_NOACTIVATE = 0x0010;
pub const SWP_NOOWNERZORDER = 0x0200;
pub const SWP_NOZORDER = 0x0004;

pub const BN_CLICKED = 0;

pub const WNDENUMPROC = fn(hwnd: HWND, lParam: LPARAM) callconv(WINAPI) c_int;

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

// Common Controls
pub extern "comctl32" fn InitCommonControlsEx(picce: [*c]const INITCOMMONCONTROLSEX) callconv(WINAPI) c_int;
pub const INITCOMMONCONTROLSEX = extern struct {
    dwSize: c_uint,
    dwICC: c_uint
};

pub fn GetWindowLongPtr(hWnd: HWND, nIndex: c_int) usize {
    switch (@import("builtin").cpu.arch) {
        .x86_64 => return @bitCast(usize, std.os.windows.user32.GetWindowLongPtrA(hWnd, nIndex)),
        .i386   => return @bitCast(usize, std.os.windows.user32.GetWindowLongA(hWnd, nIndex)),
        else    => @compileError("Unsupported architecture.")
    }
}

pub fn SetWindowLongPtr(hWnd: HWND, nIndex: c_int, dwNewLong: usize) void {
    switch (@import("builtin").cpu.arch) {
        .x86_64 => _ = std.os.windows.user32.SetWindowLongPtrA(hWnd, nIndex, @bitCast(isize, dwNewLong)),
        .i386   => _ = std.os.windows.user32.SetWindowLongA(hWnd, nIndex, @bitCast(isize, dwNewLong)),
        else    => @compileError("Unsupported architecture.")
    }
}

pub const ICC_STANDARD_CLASSES = 0x00004000;