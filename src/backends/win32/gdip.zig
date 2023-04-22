const std = @import("std");
const win32 = @import("zigwin32").everything;
const c = @import("win32.zig");

pub var token: std.os.windows.ULONG = undefined;

pub const GpError = error{
    Ok,
    GenericError,
    InvalidParameter,
    OutOfMemory,
    ObjectBusy,
    InsufficientBuffer,
    NotImplemented,
    Win32Error,
    WrongState,
    Aborted,
    FileNotFound,
    ValueOverflow,
    AccessDenied,
    UnknownImageFormat,
    FontFamilyNotFound,
    FontStyleNotFound,
    NotTrueTypeFont,
    UnsupportedGdiplusVersion,
    GdiplusNotInitialized,
    PropertyNotFound,
    PropertyNotSupported,
    ProfileNotFound,
};

pub fn gdipWrap(status: c.GpStatus) GpError!void {
    if (status != .Ok) {
        // TODO: return error type
        @panic("TODO: correctly handle GDI+ errors");
    }
}

pub const Graphics = struct {
    peer: c.GpGraphics,

    pub fn createFromHdc(hdc: win32.HDC) GpError!Graphics {
        var peer: c.GpGraphics = undefined;
        try gdipWrap(c.GdipCreateFromHDC(@ptrCast(std.os.windows.HDC, hdc), &peer));
        return Graphics{ .peer = peer };
    }
};
