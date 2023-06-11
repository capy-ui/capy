const std = @import("std");
const lib = @import("../../main.zig");
const shared = @import("../shared.zig");
const os = @import("builtin").target.os;
const log = std.log.scoped(.win32);

const EventFunctions = shared.EventFunctions(@This());
const EventType = shared.BackendEventType;

const win32Backend = @import("win32.zig");
const zigwin32 = @import("zigwin32");
const win32 = zigwin32.everything;
const gdi = @import("gdip.zig");
const HWND = win32.HWND;
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

const Win32Error = error{ UnknownError, InitializationError };

pub const Capabilities = .{ .useEventLoop = true };

pub const PeerType = HWND;

var hInst: HINSTANCE = undefined;
/// By default, win32 controls use DEFAULT_GUI_FONT which is an outdated
/// font from Windows 95 days, by default it doesn't even use ClearType
/// anti-aliasing. So we take the real default caption font from
/// NONFCLIENTEMETRICS and apply it manually to every widget.
var captionFont: win32.HFONT = undefined;
/// Default arrow cursor used to avoid components keeping the last cursor icon
/// that's been set (which is usually the resize cursor or loading cursor)
var defaultCursor: win32.HCURSOR = undefined;

var hasInit: bool = false;

fn transWinError(win32_error: win32.WIN32_ERROR) std.os.windows.Win32Error {
    return @intToEnum(std.os.windows.Win32Error, @enumToInt(win32_error));
}

pub fn init() !void {
    if (!hasInit) {
        hasInit = true;
        const hInstance = @ptrCast(win32.HINSTANCE, @alignCast(@alignOf(win32.HINSTANCE), win32.GetModuleHandleW(null).?));
        hInst = hInstance;

        if (os.isAtLeast(.windows, .win10_rs2) orelse false) {
            // tell Windows that we support high-dpi
            if (win32.SetProcessDpiAwarenessContext(win32.DPI_AWARENESS_CONTEXT_PER_MONITOR_AWARE_V2) == 0) {
                log.warn("could not set dpi awareness mode; expect the windows to look blurry on high-dpi screens", .{});
            }
        }

        const initEx = win32.INITCOMMONCONTROLSEX{
            .dwSize = @sizeOf(win32.INITCOMMONCONTROLSEX),
            .dwICC = win32.INITCOMMONCONTROLSEX_ICC.initFlags(.{ .STANDARD_CLASSES = 1, .WIN95_CLASSES = 1 }),
        };
        const code = win32.InitCommonControlsEx(&initEx);
        if (code == 0) {
            std.debug.print("Failed to initialize Common Controls.", .{});
        }

        var input = win32Backend.GdiplusStartupInput{};
        try gdi.gdipWrap(win32Backend.GdiplusStartup(&gdi.token, &input, null));

        var ncMetrics: win32.NONCLIENTMETRICSW = undefined;
        ncMetrics.cbSize = @sizeOf(win32.NONCLIENTMETRICSW);
        _ = win32.SystemParametersInfoW(
            win32.SPI_GETNONCLIENTMETRICS,
            @sizeOf(win32.NONCLIENTMETRICSW),
            &ncMetrics,
            win32.SYSTEM_PARAMETERS_INFO_UPDATE_FLAGS.initFlags(.{}),
        );
        captionFont = win32.CreateFontIndirectW(&ncMetrics.lfCaptionFont).?;

        // Load the default arrow cursor so that components can use it
        // This avoids components keeping the last cursor (resize cursor or loading cursor)
        defaultCursor = zigwin32.ui.windows_and_messaging.LoadCursor(null, win32.IDC_ARROW).?;
    }
}

pub const MessageType = enum { Information, Warning, Error };

pub fn showNativeMessageDialog(msgType: MessageType, comptime fmt: []const u8, args: anytype) void {
    const msg = std.fmt.allocPrint(lib.internal.scratch_allocator, fmt, args) catch {
        std.log.err("Could not launch message dialog, original text: " ++ fmt, args);
        return;
    };
    defer lib.internal.scratch_allocator.free(msg);

    const msg_utf16 = std.unicode.utf8ToUtf16LeWithNull(lib.internal.scratch_allocator, msg) catch {
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

var defaultWHWND: HWND = undefined;

pub const Window = struct {
    hwnd: HWND,
    source_dpi: u32 = 96,

    const className = _T("capyWClass");
    pub usingnamespace Events(Window);

    fn relayoutChild(hwnd: HWND, lp: LPARAM) callconv(WINAPI) c_int {
        const parent = @intToPtr(HWND, @bitCast(usize, lp));
        if (win32.GetParent(hwnd) != parent) {
            return 1; // ignore recursive childrens
        }

        var rect: RECT = undefined;
        _ = win32.GetClientRect(parent, &rect);
        _ = win32.MoveWindow(hwnd, 0, 0, rect.right - rect.left, rect.bottom - rect.top, 1);
        return 1;
    }

    fn process(hwnd: HWND, wm: c_uint, wp: WPARAM, lp: LPARAM) callconv(WINAPI) LRESULT {
        switch (wm) {
            win32.WM_SIZE => {
                _ = win32.EnumChildWindows(hwnd, relayoutChild, @bitCast(isize, @ptrToInt(hwnd)));
            },
            win32.WM_DPICHANGED => {
                // TODO: update scale factor
            },
            else => {},
        }
        return win32.DefWindowProcW(hwnd, wm, wp, lp);
    }

    pub fn create() !Window {
        var wc: win32.WNDCLASSEXW = .{
            .cbSize = @sizeOf(win32.WNDCLASSEXW),
            .style = win32.WNDCLASS_STYLES.initFlags(.{ .HREDRAW = 1, .VREDRAW = 1 }),
            .lpfnWndProc = process,
            .cbClsExtra = 0,
            .cbWndExtra = 0,
            .hInstance = hInst,
            .hIcon = null, // TODO: LoadIcon
            .hCursor = defaultCursor,
            .hbrBackground = win32.GetSysColorBrush(@enumToInt(win32.COLOR_3DFACE)),
            .lpszMenuName = null,
            .lpszClassName = className,
            .hIconSm = null,
        };

        if ((win32.RegisterClassExW(&wc)) == 0) {
            showNativeMessageDialog(.Error, "Could not register window class {s}", .{"capyWClass"});
            return Win32Error.InitializationError;
        }

        const hwnd = win32.CreateWindowExW(
        // composited and layered don't work in wine for some reason, but only in wine
        win32.WS_EX_LEFT, // | win32.WS_EX_COMPOSITED | win32.WS_EX_LAYERED | win32.WS_EX_APPWINDOW, // dwExtStyle
            className, // lpClassName
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

        defaultWHWND = hwnd;
        return Window{ .hwnd = hwnd };
    }

    // TODO: handle the fact that ONLY the root child must forcibly draw a background
    pub fn setChild(self: *Window, hwnd: ?HWND) void {
        // TODO: if null, remove child
        _ = win32.SetParent(hwnd.?, self.hwnd);
        const style = win32.GetWindowLongPtrW(hwnd.?, win32.GWL_STYLE);
        _ = win32.SetWindowLongPtrW(hwnd.?, win32.GWL_STYLE, style | @enumToInt(win32.WS_CHILD));
        _ = win32.ShowWindow(hwnd.?, win32.SW_SHOWDEFAULT);
        _ = win32.UpdateWindow(hwnd.?);
    }

    pub fn resize(self: *Window, width: c_int, height: c_int) void {
        var rect: RECT = undefined;
        _ = win32.GetWindowRect(self.hwnd, &rect);
        _ = win32.MoveWindow(self.hwnd, rect.left, rect.top, @intCast(c_int, width), @intCast(c_int, height), 1);
    }

    pub fn setTitle(self: *Window, title: [*:0]const u8) void {
        const utf16 = std.unicode.utf8ToUtf16LeWithNull(lib.internal.scratch_allocator, std.mem.span(title)) catch return;
        defer lib.internal.scratch_allocator.free(utf16);

        _ = win32.SetWindowTextW(self.hwnd, utf16);
    }

    pub fn setSourceDpi(self: *Window, dpi: u32) void {
        self.source_dpi = dpi;
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
};

inline fn getEventUserData(peer: HWND) *EventUserData {
    return @intToPtr(*EventUserData, @bitCast(usize, win32.GetWindowLongPtrW(peer, win32.GWL_USERDATA)));
}

pub fn Events(comptime T: type) type {
    return struct {
        const Self = @This();

        pub fn process(hwnd: HWND, wm: c_uint, wp: WPARAM, lp: LPARAM) callconv(WINAPI) LRESULT {
            switch (wm) {
                win32.WM_NOTIFY => {
                    const nmhdr = @intToPtr(*const win32.NMHDR, @bitCast(usize, lp));
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
            if (win32.GetWindowLongPtrW(hwnd, win32.GWL_USERDATA) == 0) return win32.DefWindowProcW(hwnd, wm, wp, lp);
            switch (wm) {
                win32.WM_COMMAND => {
                    const code = @intCast(u16, wp >> 16);
                    const data = getEventUserData(@intToPtr(HWND, @bitCast(usize, lp)));
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
                        else => {},
                    }
                },
                win32.WM_CTLCOLOREDIT => {
                    const data = getEventUserData(@intToPtr(HWND, @bitCast(usize, lp)));
                    const len = win32.GetWindowTextLengthW(@intToPtr(HWND, @bitCast(usize, lp)));
                    // The text box may have changed
                    // TODO: send the event only when the text truly changed
                    if (data.last_text_len != len) {
                        if (data.user.changedTextHandler) |handler|
                            handler(data.userdata);
                        data.last_text_len = len;
                    }
                },
                win32.WM_NOTIFY => {
                    const nmhdr = @intToPtr(*const win32.NMHDR, @bitCast(usize, lp));
                    //std.log.info("code = {d} vs {d}", .{ nmhdr.code, win32.TCN_SELCHANGING });
                    switch (nmhdr.code) {
                        TCN_SELCHANGING => {
                            return 0;
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
                        handler(@intCast(u32, rect.right - rect.left), @intCast(u32, rect.bottom - rect.top), data.userdata);
                    if (data.user.resizeHandler) |handler|
                        handler(@intCast(u32, rect.right - rect.left), @intCast(u32, rect.bottom - rect.top), data.userdata);
                },
                win32.WM_HSCROLL => {
                    const data = getEventUserData(hwnd);
                    var scrollInfo = std.mem.zeroInit(win32.SCROLLINFO, .{
                        .cbSize = @sizeOf(win32.SCROLLINFO),
                        .fMask = win32.SIF_POS,
                    });
                    _ = win32.GetScrollInfo(hwnd, win32.SB_HORZ, &scrollInfo);

                    const currentScroll = @intCast(u32, scrollInfo.nPos);
                    const newPos = switch (@truncate(u16, wp)) {
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
                            .nPos = @intCast(c_int, newPos),
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

                    const currentScroll = @intCast(u32, scrollInfo.nPos);
                    const newPos = switch (@truncate(u16, wp)) {
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
                            .nPos = @intCast(c_int, newPos),
                        });
                        _ = win32.SetScrollInfo(hwnd, win32.SB_VERT, &verticalScrollInfo, 1);
                        if (@hasDecl(T, "onVScroll")) {
                            T.onVScroll(data, hwnd, newPos);
                        }
                    }
                },
                win32.WM_PAINT => {
                    const data = getEventUserData(hwnd);
                    var ps: win32.PAINTSTRUCT = undefined;
                    var hdc: win32.HDC = win32.BeginPaint(hwnd, &ps).?;
                    defer _ = win32.EndPaint(hwnd, &ps);
                    var graphics = gdi.Graphics.createFromHdc(hdc) catch unreachable;

                    const brush = @ptrCast(win32.HBRUSH, win32.GetStockObject(win32.DC_BRUSH));
                    _ = win32.SelectObject(hdc, @ptrCast(win32.HGDIOBJ, brush));

                    var dc = Canvas.DrawContext{ .hdc = hdc, .graphics = graphics, .hbr = brush, .path = std.ArrayList(Canvas.DrawContext.PathElement)
                        .init(lib.internal.scratch_allocator) };
                    defer dc.path.deinit();

                    if (data.class.drawHandler) |handler|
                        handler(&dc, data.userdata);
                    if (data.user.drawHandler) |handler|
                        handler(&dc, data.userdata);
                },
                win32.WM_DESTROY => win32.PostQuitMessage(0),
                else => {},
            }
            return win32.DefWindowProcW(hwnd, wm, wp, lp);
        }

        pub fn setupEvents(peer: HWND) !void {
            var data = try lib.internal.lasting_allocator.create(EventUserData);
            data.* = EventUserData{}; // ensure that it uses default values
            _ = win32.SetWindowLongPtrW(peer, win32.GWL_USERDATA, @bitCast(isize, @ptrToInt(data)));
        }

        pub inline fn setUserData(self: *T, data: anytype) void {
            comptime {
                if (!std.meta.trait.isSingleItemPtr(@TypeOf(data))) {
                    @compileError(std.fmt.comptimePrint("Expected single item pointer, got {s}", .{@typeName(@TypeOf(data))}));
                }
            }
            if (@TypeOf(self) == *Window) {
                getEventUserData(self.hwnd).peerPtr = self;
                getEventUserData(self.hwnd).userdata = @ptrToInt(data);
            } else {
                getEventUserData(self.peer).peerPtr = self;
                getEventUserData(self.peer).userdata = @ptrToInt(data);
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
            var rect: RECT = undefined;
            _ = win32.GetWindowRect(self.peer, &rect);
            return rect.bottom - rect.top;
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

pub const MouseButton = enum { Left, Middle, Right };

pub const Canvas = struct {
    peer: HWND,
    data: usize = 0,

    pub usingnamespace Events(Canvas);

    pub const DrawContext = struct {
        hdc: win32.HDC,
        graphics: gdi.Graphics,
        hbr: win32.HBRUSH,
        path: std.ArrayList(PathElement),

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

                const defaultFont = @ptrCast(win32.HFONT, win32.GetStockObject(win32.DEFAULT_GUI_FONT));
                _ = win32.SelectObject(hdc, @ptrCast(win32.HGDIOBJ, defaultFont));
                return TextLayout{ .font = defaultFont, .hdc = hdc };
            }

            pub fn setFont(self: *TextLayout, font: Font) void {
                // _ = win32.DeleteObject(@ptrCast(win32.HGDIOBJ, self.font)); // delete old font
                const allocator = lib.internal.scratch_allocator;
                const wideFace = std.unicode.utf8ToUtf16LeWithNull(allocator, font.face) catch return; // invalid utf8 or not enough memory
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
                    _ = win32.DeleteObject(@ptrCast(win32.HGDIOBJ, self.font));
                    self.font = winFont;
                }
                _ = win32.SelectObject(self.hdc, @ptrCast(win32.HGDIOBJ, self.font));
            }

            pub fn getTextSize(self: *TextLayout, str: []const u8) TextSize {
                var size: win32.SIZE = undefined;
                const allocator = lib.internal.scratch_allocator;
                const wide = std.unicode.utf8ToUtf16LeWithNull(allocator, str) catch return; // invalid utf8 or not enough memory
                defer allocator.free(wide);
                _ = win32.GetTextExtentPoint32W(self.hdc, wide.ptr, @intCast(c_int, str.len), &size);

                return TextSize{ .width = @intCast(u32, size.cx), .height = @intCast(u32, size.cy) };
            }

            pub fn deinit(self: *TextLayout) void {
                _ = win32.DeleteObject(@ptrCast(win32.HGDIOBJ, self.hdc));
                _ = win32.DeleteObject(@ptrCast(win32.HGDIOBJ, self.font));
            }
        };

        // TODO: transparency support using https://docs.microsoft.com/en-us/windows/win32/api/wingdi/nf-wingdi-alphablend
        // or use GDI+ and https://docs.microsoft.com/en-us/windows/win32/gdiplus/-gdiplus-drawing-with-opaque-and-semitransparent-brushes-use
        pub fn setColorByte(self: *DrawContext, color: lib.Color) void {
            const colorref = (@as(u32, color.blue) << 16) |
                (@as(u32, color.green) << 8) | color.red;
            _ = win32.SetDCBrushColor(self.hdc, colorref);
        }

        pub fn setColor(self: *DrawContext, r: f32, g: f32, b: f32) void {
            self.setColorRGBA(r, g, b, 1);
        }

        pub fn setColorRGBA(self: *DrawContext, r: f32, g: f32, b: f32, a: f32) void {
            const color = lib.Color{
                .red = @floatToInt(u8, std.math.clamp(r, 0, 1) * 255),
                .green = @floatToInt(u8, std.math.clamp(g, 0, 1) * 255),
                .blue = @floatToInt(u8, std.math.clamp(b, 0, 1) * 255),
                .alpha = @floatToInt(u8, std.math.clamp(a, 0, 1) * 255),
            };
            self.setColorByte(color);
        }

        pub fn rectangle(self: *DrawContext, x: i32, y: i32, w: u32, h: u32) void {
            _ = win32.Rectangle(self.hdc, @intCast(c_int, x), @intCast(c_int, y), x + @intCast(c_int, w), y + @intCast(c_int, h));
        }

        pub fn ellipse(self: *DrawContext, x: i32, y: i32, w: u32, h: u32) void {
            const cw = @intCast(c_int, w);
            const ch = @intCast(c_int, h);

            _ = win32.Ellipse(self.hdc, @intCast(c_int, x), @intCast(c_int, y), @intCast(c_int, x) + cw, @intCast(c_int, y) + ch);
        }

        pub fn text(self: *DrawContext, x: i32, y: i32, layout: TextLayout, str: []const u8) void {
            // select current color
            const color = win32.GetDCBrushColor(self.hdc);
            _ = win32.SetTextColor(self.hdc, color);

            // select the font
            _ = win32.SelectObject(self.hdc, @ptrCast(win32.HGDIOBJ, layout.font));

            // and draw
            const allocator = lib.internal.scratch_allocator;
            const wide = std.unicode.utf8ToUtf16LeWithNull(allocator, str) catch return; // invalid utf8 or not enough memory
            defer allocator.free(wide);
            _ = win32.ExtTextOutW(self.hdc, @intCast(c_int, x), @intCast(c_int, y), win32.ETO_OPTIONS.initFlags(.{}), null, wide, @intCast(std.os.windows.UINT, wide.len), null);
        }

        pub fn line(self: *DrawContext, x1: i32, y1: i32, x2: i32, y2: i32) void {
            _ = win32.MoveToEx(self.hdc, @intCast(c_int, x1), @intCast(c_int, y1), null);
            _ = win32.LineTo(self.hdc, @intCast(c_int, x2), @intCast(c_int, y2));
        }

        pub fn fill(self: *DrawContext) void {
            self.path.clearRetainingCapacity();
        }

        pub fn stroke(self: *DrawContext) void {
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
    arena: std.heap.ArenaAllocator,

    pub usingnamespace Events(TextField);

    pub fn create() !TextField {
        const hwnd = win32.CreateWindowExW(win32.WS_EX_LEFT, // dwExtStyle
            _T("EDIT"), // lpClassName
            _T(""), // lpWindowName
            @intToEnum(win32.WINDOW_STYLE, @enumToInt(win32.WS_TABSTOP) | @enumToInt(win32.WS_CHILD) | @enumToInt(win32.WS_BORDER)), // dwStyle
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
        _ = win32.SendMessageW(hwnd, win32.WM_SETFONT, @ptrToInt(captionFont), 1);

        return TextField{ .peer = hwnd, .arena = std.heap.ArenaAllocator.init(lib.internal.lasting_allocator) };
    }

    pub fn setText(self: *TextField, text: []const u8) void {
        const allocator = lib.internal.scratch_allocator;
        const wide = std.unicode.utf8ToUtf16LeWithNull(allocator, text) catch return; // invalid utf8 or not enough memory
        defer allocator.free(wide);
        if (win32.SetWindowTextW(self.peer, wide) == 0) {
            std.os.windows.unexpectedError(transWinError(win32.GetLastError())) catch {};
        }

        const len = win32.GetWindowTextLengthW(self.peer);
        getEventUserData(self.peer).last_text_len = len;
    }

    pub fn getText(self: *TextField) [:0]const u8 {
        const allocator = self.arena.allocator();
        const len = win32.GetWindowTextLengthW(self.peer);
        var buf = allocator.allocSentinel(u16, @intCast(usize, len), 0) catch unreachable; // TODO return error
        defer allocator.free(buf);
        const realLen = @intCast(usize, win32.GetWindowTextW(self.peer, buf.ptr, len + 1));
        const utf16Slice = buf[0..realLen];
        const text = std.unicode.utf16leToUtf8AllocZ(allocator, utf16Slice) catch unreachable; // TODO return error
        return text;
    }

    pub fn setReadOnly(self: *TextField, readOnly: bool) void {
        _ = win32.SendMessageW(self.peer, win32.EM_SETREADONLY, @boolToInt(readOnly), undefined);
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
            @intToEnum(win32.WINDOW_STYLE, @enumToInt(win32.WS_TABSTOP) | @enumToInt(win32.WS_CHILD) | win32.BS_PUSHBUTTON | win32.BS_FLAT), // dwStyle
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
        _ = win32.SendMessageW(hwnd, win32.WM_SETFONT, @ptrToInt(captionFont), 1);

        return Button{ .peer = hwnd, .arena = std.heap.ArenaAllocator.init(lib.internal.lasting_allocator) };
    }

    pub fn setLabel(self: *Button, label: [:0]const u8) void {
        const allocator = lib.internal.scratch_allocator;
        const wide = std.unicode.utf8ToUtf16LeWithNull(allocator, label) catch return; // invalid utf8 or not enough memory
        defer allocator.free(wide);
        if (win32.SetWindowTextW(self.peer, wide) == 0) {
            std.os.windows.unexpectedError(transWinError(win32.GetLastError())) catch {};
        }
    }

    pub fn getLabel(self: *Button) [:0]const u8 {
        const allocator = self.arena.allocator();
        const len = win32.GetWindowTextLengthW(self.peer);
        var buf = allocator.allocSentinel(u16, @intCast(usize, len), 0) catch unreachable; // TODO return error
        defer allocator.free(buf);
        const realLen = @intCast(usize, win32.GetWindowTextW(self.peer, buf.ptr, len + 1));
        const utf16Slice = buf[0..realLen];
        const text = std.unicode.utf16leToUtf8AllocZ(allocator, utf16Slice) catch unreachable; // TODO return error
        return text;
    }

    pub fn setEnabled(self: *Button, enabled: bool) void {
        _ = win32.EnableWindow(self.peer, @boolToInt(enabled));
    }
};

pub const CheckBox = struct {
    peer: HWND,
    arena: std.heap.ArenaAllocator,

    pub usingnamespace Events(CheckBox);

    pub fn create() !CheckBox {
        const hwnd = win32.CreateWindowEx(win32.WS_EX_LEFT, // dwExtStyle
            "BUTTON", // lpClassName
            "", // lpWindowName
            win32.WS_TABSTOP | win32.WS_CHILD | win32.BS_AUTOCHECKBOX, // dwStyle
            0, // X
            0, // Y
            100, // nWidth
            100, // nHeight
            defaultWHWND, // hWindParent
            null, // hMenu
            hInst, // hInstance
            null // lpParam
        );
        try CheckBox.setupEvents(hwnd);
        _ = win32.SendMessageW(hwnd, win32.WM_SETFONT, @ptrToInt(captionFont), 1);

        return CheckBox{ .peer = hwnd, .arena = std.heap.ArenaAllocator.init(lib.internal.lasting_allocator) };
    }

    pub fn setLabel(self: *CheckBox, label: [:0]const u8) void {
        const allocator = lib.internal.scratch_allocator;
        const wide = std.unicode.utf8ToUtf16LeWithNull(allocator, label) catch return; // invalid utf8 or not enough memory
        defer allocator.free(wide);
        if (win32.SetWindowTextW(self.peer, wide) == 0) {
            std.os.windows.unexpectedError(transWinError(win32.GetLastError())) catch {};
        }
    }

    pub fn setEnabled(self: *CheckBox, enabled: bool) void {
        _ = win32.EnableWindow(self.peer, @boolToInt(enabled));
    }

    pub fn setChecked(self: *CheckBox, checked: bool) void {
        const state: win32.WPARAM = switch (checked) {
            true => win32.BST_CHECKED,
            false => win32.BST_UNCHECKED,
        };
        _ = win32.SendMessageW(self.peer, win32.BM_SETCHECK, state, 0);
    }

    pub fn isChecked(self: *CheckBox) bool {
        return win32.SendMessageW(self.peer, win32.BM_GETCHECK, 0, 0) != win32.BST_UNCHECKED;
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
            win32.WS_TABSTOP | win32.WS_CHILD, // dwStyle
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
        _ = win32.SendMessageW(hwnd, win32.WM_SETFONT, @ptrToInt(captionFont), 1);

        return Slider{ .peer = hwnd };
    }

    pub fn getValue(self: *const Slider) f32 {
        const valueInt = win32.SendMessageW(self.peer, win32.TBM_GETPOS, 0, 0);
        const value = @intToFloat(f32, valueInt) * self.stepSize;
        return value;
    }

    pub fn setValue(self: *Slider, value: f32) void {
        const valueInt = @floatToInt(i32, value / self.stepSize);
        _ = win32.SendMessageW(self.peer, win32.TBM_GETPOS, 1, valueInt);
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
        const maxInt = @floatToInt(i16, self.max / self.stepSize);
        const minInt = @floatToInt(i16, self.min / self.stepSize);
        _ = win32.SendMessageW(self.peer, win32.TBM_SETRANGEMIN, 1, minInt);
        _ = win32.SendMessageW(self.peer, win32.TBM_SETRANGEMAX, 1, maxInt);
    }

    pub fn setEnabled(self: *Slider, enabled: bool) void {
        _ = win32.EnableWindow(self.peer, @boolToInt(enabled));
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
            @intToEnum(win32.WINDOW_STYLE, @enumToInt(win32.WINDOW_STYLE.initFlags(.{ .TABSTOP = 1, .CHILD = 1 })) | win32.SS_CENTERIMAGE), // dwStyle
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
        _ = win32.SendMessageW(hwnd, win32.WM_SETFONT, @ptrToInt(captionFont), 1);

        return Label{ .peer = hwnd, .arena = std.heap.ArenaAllocator.init(lib.internal.lasting_allocator) };
    }

    pub fn setAlignment(self: *Label, alignment: f32) void {
        _ = self;
        _ = alignment;
    }

    pub fn setText(self: *Label, text: []const u8) void {
        const allocator = lib.internal.scratch_allocator;
        const wide = std.unicode.utf8ToUtf16LeWithNull(allocator, text) catch return; // invalid utf8 or not enough memory
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
            @intToEnum(win32.WINDOW_STYLE, @enumToInt(win32.WS_TABSTOP) | @enumToInt(win32.WS_CHILD) | @enumToInt(win32.WS_CLIPCHILDREN)), // dwStyle
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
            @intToEnum(win32.WINDOW_STYLE, @enumToInt(win32.WS_TABSTOP) | @enumToInt(win32.WS_CHILD) | @enumToInt(win32.WS_CLIPSIBLINGS)), // dwStyle
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
        _ = win32.SendMessageW(hwnd, win32.WM_SETFONT, @ptrToInt(captionFont), 0);
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

    pub fn insert(self: *TabContainer, position: usize, peer: PeerType) usize {
        const item = win32Backend.TCITEMA{ .mask = 0 };
        const newIndex = win32Backend.TabCtrl_InsertItemW(self.tabControl, @intCast(c_int, position), &item);
        self.peerList.append(peer) catch unreachable;

        if (self.shownPeer) |previousPeer| {
            _ = win32.ShowWindow(previousPeer, win32.SW_HIDE);
        }
        _ = win32.SetParent(peer, self.peer);
        _ = win32.ShowWindow(peer, win32.SW_SHOWDEFAULT);
        _ = win32.UpdateWindow(peer);
        self.shownPeer = peer;

        return @intCast(usize, newIndex);
    }

    pub fn setLabel(self: *const TabContainer, position: usize, text: [:0]const u8) void {
        const item = win32Backend.TCITEMA{
            .mask = @enumToInt(win32.TCIF_TEXT), // only change the text attribute
            .pszText = text,
            // cchTextMax doesn't need to be set when using SetItem
        };
        win32Backend.TabCtrl_SetItemW(self.tabControl, @intCast(c_int, position), &item);
    }

    pub fn getTabsNumber(self: *const TabContainer) usize {
        return @bitCast(usize, win32Backend.TabCtrl_GetItemCountW(self.tabControl));
    }

    fn onResize(_: *EventUserData, hwnd: HWND) void {
        var rect: RECT = undefined;
        _ = win32.GetWindowRect(hwnd, &rect);
        const child = win32.GetWindow(hwnd, win32.GW_CHILD);
        _ = win32.MoveWindow(child, 0, 50, rect.right - rect.left, rect.bottom - rect.top, 1);
    }
};

// TODO: scroll using mouse wheel and using keyboard (arrow keys + page up/down)
pub const ScrollView = struct {
    peer: HWND,
    child: ?HWND = null,
    widget: ?*const lib.Widget = null,

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
            @intToEnum(win32.WINDOW_STYLE, @enumToInt(win32.WS_TABSTOP) | @enumToInt(win32.WS_CHILD) | @enumToInt(win32.WS_CLIPCHILDREN) | @enumToInt(win32.WS_HSCROLL) | @enumToInt(win32.WS_VSCROLL)), // dwStyle
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

    pub fn setChild(self: *ScrollView, peer: PeerType, widget: *const lib.Widget) void {
        // TODO: remove old widget if there was one
        self.child = peer;
        self.widget = widget;

        _ = win32.SetParent(peer, self.peer);
        const style = win32.GetWindowLongPtrW(peer, win32.GWL_STYLE);
        _ = win32.SetWindowLongPtrW(peer, win32.GWL_STYLE, style | @enumToInt(win32.WS_CHILD));
        _ = win32.ShowWindow(peer, win32.SW_SHOWDEFAULT);
        _ = win32.UpdateWindow(peer);
    }

    pub fn onHScroll(_: *EventUserData, hwnd: HWND, newPos: usize) void {
        const child = win32.GetWindow(hwnd, win32.GW_CHILD);

        var parent: RECT = undefined;
        _ = win32.GetWindowRect(hwnd, &parent);

        var rect: RECT = undefined;
        _ = win32.GetWindowRect(child, &rect);
        _ = win32.MoveWindow(child, -@intCast(c_int, newPos), rect.top - parent.top, rect.right - rect.left, rect.bottom - rect.top, 1);
    }

    pub fn onVScroll(_: *EventUserData, hwnd: HWND, newPos: usize) void {
        const child = win32.GetWindow(hwnd, win32.GW_CHILD);

        var parent: RECT = undefined;
        _ = win32.GetWindowRect(hwnd, &parent);

        var rect: RECT = undefined;
        _ = win32.GetWindowRect(child, &rect);
        _ = win32.MoveWindow(child, rect.left - parent.left, -@intCast(c_int, newPos), rect.right - rect.left, rect.bottom - rect.top, 1);
    }

    pub fn onResize(data: *EventUserData, hwnd: HWND) void {
        const self = @ptrCast(*const ScrollView, @alignCast(@alignOf(ScrollView), data.peerPtr));

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
            std.math.max(rect.left - parent.left, std.math.min(0, -(@intCast(c_int, preferred.width) - width))),
            std.math.max(rect.top - parent.top, std.math.min(0, -(@intCast(c_int, preferred.height) - height))),
            @intCast(c_int, preferred.width),
            @intCast(c_int, preferred.height),
            1,
        );

        // Finally, update the scroll bars
        var horizontalScrollInfo = win32.SCROLLINFO{
            .cbSize = @sizeOf(win32.SCROLLINFO),
            .fMask = @intToEnum(win32.SCROLLINFO_MASK, @enumToInt(win32.SIF_RANGE) | @enumToInt(win32.SIF_PAGE)),
            .nMin = 0,
            .nMax = @intCast(c_int, preferred.width),
            .nPage = @intCast(c_uint, width),
            .nPos = 0,
            .nTrackPos = 0,
        };
        _ = win32.SetScrollInfo(self.peer, win32.SB_HORZ, &horizontalScrollInfo, 1);

        var verticalScrollInfo = win32.SCROLLINFO{
            .cbSize = @sizeOf(win32.SCROLLINFO),
            .fMask = @intToEnum(win32.SCROLLINFO_MASK, @enumToInt(win32.SIF_RANGE) | @enumToInt(win32.SIF_PAGE)),
            .nMin = 0,
            .nMax = @intCast(c_int, preferred.height),
            .nPage = @intCast(c_uint, height),
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

        const hwnd = win32.CreateWindowExW(win32.WS_EX_LEFT, // dwExtStyle
            L("capyContainerClass"), // lpClassName
            L(""), // lpWindowName
            win32.WINDOW_STYLE.initFlags(.{ .TABSTOP = 1, .CHILD = 1, .CLIPCHILDREN = 1 }), // dwStyle
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

    pub fn add(self: *Container, peer: PeerType) void {
        _ = win32.SetParent(peer, self.peer);
        const style = win32.GetWindowLongPtrW(peer, win32.GWL_STYLE);
        _ = win32.SetWindowLongPtrW(peer, win32.GWL_STYLE, style | @enumToInt(win32.WS_CHILD));
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
        _ = win32.MoveWindow(peer, @intCast(c_int, x), @intCast(c_int, y), rect.right - rect.left, rect.bottom - rect.top, 1);
    }

    pub fn resize(self: *const Container, peer: PeerType, width: u32, height: u32) void {
        var rect: RECT = undefined;
        _ = win32.GetWindowRect(peer, &rect);
        if (rect.right - rect.left == width and rect.bottom - rect.top == height) {
            return;
        }

        var parent: RECT = undefined;
        _ = win32.GetWindowRect(self.peer, &parent);
        _ = win32.MoveWindow(peer, rect.left - parent.left, rect.top - parent.top, @intCast(c_int, width), @intCast(c_int, height), 1);
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
    _ = win32.TranslateMessage(&msg);
    _ = win32.DispatchMessageW(&msg);
    return true;
}
