const win32 = @import("win32.zig");

pub var token: win32.ULONG = undefined;

pub const GpError = error{ Ok, GenericError, InvalidParameter, OutOfMemory, ObjectBusy, InsufficientBuffer, NotImplemented, Win32Error, WrongState, Aborted, FileNotFound, ValueOverflow, AccessDenied, UnknownImageFormat, FontFamilyNotFound, FontStyleNotFound, NotTrueTypeFont, UnsupportedGdiplusVersion, GdiplusNotInitialized, PropertyNotFound, PropertyNotSupported, ProfileNotFound };

pub fn gdipWrap(status: win32.GpStatus) GpError!void {
    if (status != .Ok) {
        // TODO: return error type
        @panic("TODO: correctly handle GDI+ errors");
    }
}

pub const Graphics = struct {
    peer: win32.GpGraphics,

    pub fn createFromHdc(hdc: win32.HDC) GpError!Graphics {
        var peer: win32.GpGraphics = undefined;
        try gdipWrap(win32.GdipCreateFromHDC(hdc, &peer));
        return Graphics{ .peer = peer };
    }
};
