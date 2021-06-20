const std = @import("std");

usingnamespace @import("win32.zig");

const Win32Error = error {
    UnknownError,
    InitializationError
};

pub const Capabilities = .{
    .useEventLoop = true
};

pub const PeerType = HWND;

var hInst: HINSTANCE = undefined;

pub const public = struct {

    pub fn main() !void {
        try init();
        try @import("root").run();
    }

};

pub fn init() !void {
    const hInstance = @ptrCast(HINSTANCE, @alignCast(@alignOf(HINSTANCE),
        GetModuleHandleW(null).?));
    const lpCmdLine = GetCommandLineW();

    const initEx = INITCOMMONCONTROLSEX {
        .dwSize = @sizeOf(INITCOMMONCONTROLSEX),
        .dwICC = ICC_STANDARD_CLASSES
    };
    const code = InitCommonControlsEx(&initEx);
    if (code == 0) {
        std.log.scoped(.win32).warn("Failed to initialize Common Controls.", .{});
    } else {
        std.log.scoped(.win32).debug("Success with {} !", .{code});
    }
}

pub const MessageType = enum {
    Information,
    Warning,
    Error
};

pub fn showNativeMessageDialog(msgType: MessageType, comptime fmt: []const u8, args: anytype) void {
    const msg = std.fmt.allocPrintZ(std.heap.page_allocator, fmt, args) catch {
        std.log.err("Could not launch message dialog, original text: " ++ fmt, args);
        return;
    };
    defer std.heap.page_allocator.free(msg);

    const icon: u32 = switch (msgType) {
        .Information => MB_ICONINFORMATION,
        .Warning => MB_ICONWARNING,
        .Error => MB_ICONERROR,
    };

    _ = messageBoxA(null, msg, "Dialog", icon) catch {
        std.log.err("Could not launch message dialog, original text: " ++ fmt, args);
        return;
    };
}

const className = "zgtWClass";
var defaultWHWND: HWND = undefined;

pub const Window = struct {
    hwnd: HWND,

    fn relayoutChild(hwnd: HWND, lp: LPARAM) callconv(WINAPI) c_int {
        const parent = @intToPtr(HWND, @bitCast(usize, lp));
        if (GetParent(hwnd) != parent) {
            return 1; // ignore recursive childrens
        }

        var rect: RECT = undefined;
        _ = GetClientRect(parent, &rect);

        const style = @intCast(u32, GetWindowLongPtr(hwnd, GWL_STYLE));
        const exStyle = @intCast(u32, GetWindowLongPtr(hwnd, GWL_EXSTYLE));
        _ = MoveWindow(hwnd, 0, 0, rect.right - rect.left, rect.bottom - rect.top, 1);
        return 1;
    }

    fn process(hwnd: HWND, wm: c_uint, wp: WPARAM, lp: LPARAM) callconv(WINAPI) LRESULT {
        switch (wm) {
            WM_SIZE => {
                _ = EnumChildWindows(hwnd, relayoutChild, @bitCast(isize, @ptrToInt(hwnd)));
            },
            else => {}
        }
        return DefWindowProcA(hwnd, wm, wp, lp);
    }

    pub fn create() !Window {
        var wc: WNDCLASSEXA = .{
            .style = 0,
            .lpfnWndProc = process,
            .cbClsExtra = 0,
            .cbWndExtra = 0,
            .hInstance = hInst,
            .hIcon = null, // TODO: LoadIcon
            .hCursor = null, // TODO: LoadCursor
            .hbrBackground = null,
            .lpszMenuName = null,
            .lpszClassName = className,
            .hIconSm = null
        };

        if ((try registerClassExA(&wc)) == 0) {
            showNativeMessageDialog(.Error, "Could not register window class {s}", .{className});
            return Win32Error.InitializationError;
        }

        const hwnd = try createWindowExA(
            WS_EX_LEFT,          // dwExtStyle
            className,           // lpClassName
            "",                  // lpWindowName
            WS_OVERLAPPEDWINDOW, // dwStyle
            CW_USEDEFAULT,       // X
            CW_USEDEFAULT,       // Y
            CW_USEDEFAULT,       // nWidth
            CW_USEDEFAULT,       // nHeight
            null,                // hWindParent
            null,                // hMenu
            hInst,               // hInstance
            null                 // lpParam
        );

        defaultWHWND = hwnd;
        return Window {
            .hwnd = hwnd
        };
    }

    pub fn setChild(self: *Window, hwnd: anytype) void {
        _ = SetParent(hwnd, self.hwnd);
        const style = GetWindowLongPtr(hwnd, GWL_STYLE);
        SetWindowLongPtr(hwnd, GWL_STYLE, style | WS_CHILD);
        _ = showWindow(hwnd, SW_SHOWDEFAULT);
        _ = UpdateWindow(hwnd);
    }

    pub fn resize(self: *Window, width: c_int, height: c_int) void {
        var rect: RECT = undefined;
        _ = GetWindowRect(self.hwnd, &rect);
        _ = MoveWindow(self.hwnd, rect.left, rect.top, @intCast(c_int, width), @intCast(c_int, height), 1);
    }

    pub fn show(self: *Window) void {
        _ = showWindow(self.hwnd, SW_SHOWDEFAULT);
        _ = UpdateWindow(self.hwnd);
    }

    pub fn close(self: *Window) void {
        _ = showWindow(self.hwnd, SW_HIDE);
        _ = UpdateWindow(self.hwnd);
    }

};

pub const EventType = enum {
    Click,
    Draw,
    MouseButton,
    Scroll,
    TextChanged,
    Resize
};

const EventUserData = struct {
    /// Only works for buttons
    clickHandler: ?fn(data: usize) void = null,
    mouseButtonHandler: ?fn(button: MouseButton, pressed: bool, x: f64, y: f64, data: usize) void = null,
    scrollHandler: ?fn(dx: f64, dy: f64, data: usize) void = null,
    resizeHandler: ?fn(width: u32, height: u32, data: usize) void = null,
    /// Only works for canvas (althought technically it isn't required to)
    drawHandler: ?fn(ctx: Canvas.DrawContext, data: usize) void = null,
    changedTextHandler: ?fn(data: usize) void = null,
    userdata: usize = 0
};

fn getEventUserData(peer: HWND) callconv(.Inline) *EventUserData {
    return @intToPtr(*EventUserData, GetWindowLongPtr(peer, GWL_USERDATA));
}

pub fn Events(comptime T: type) type {
    return struct {
        const Self = @This();

        pub fn process(hwnd: HWND, wm: c_uint, wp: WPARAM, lp: LPARAM) callconv(WINAPI) LRESULT {
            if (GetWindowLongPtr(hwnd, GWL_USERDATA) == 0) return DefWindowProcA(hwnd, wm, wp, lp);
            switch (wm) {
                WM_COMMAND => {
                    const code = @intCast(u16, wp << 16);
                    const data = getEventUserData(@intToPtr(HWND, @bitCast(usize, lp)));
                    switch (code) {
                        BN_CLICKED => {
                            if (data.clickHandler) |handler| {
                                handler(data.userdata);
                            }
                        },
                        else => {}
                    }
                },
                WM_SIZE => {
                    const data = getEventUserData(hwnd);
                    if (data.resizeHandler) |handler| {
                        var rect: RECT = undefined;
                        _ = GetWindowRect(hwnd, &rect);
                        handler(
                            @intCast(u32, rect.right - rect.left),
                            @intCast(u32, rect.bottom - rect.top),
                            data.userdata
                        );
                    }
                },
                else => {}
            }
            return DefWindowProcA(hwnd, wm, wp, lp);
        }

        pub fn setupEvents(peer: HWND) !void {
            const allocator = std.heap.page_allocator; // TODO: global allocator
            var data = try allocator.create(EventUserData);
            data.* = EventUserData {}; // ensure that it uses default values
            SetWindowLongPtr(peer, GWL_USERDATA, @ptrToInt(data));
        }

        pub fn setUserData(self: *T, data: anytype) callconv(.Inline) void {
            comptime {
                if (!std.meta.trait.isSingleItemPtr(@TypeOf(data))) {
                    @compileError(std.fmt.comptimePrint("Expected single item pointer, got {s}", .{@typeName(@TypeOf(data))}));
                }
            }
            getEventUserData(self.peer).userdata = @ptrToInt(data);
        }

        pub fn setCallback(self: *T, comptime eType: EventType, cb: anytype) callconv(.Inline) !void {
            const data = getEventUserData(self.peer);
            switch (eType) {
                .Click       => data.clickHandler       = cb,
                .Draw        => data.drawHandler        = cb,
                .MouseButton => data.mouseButtonHandler = cb,
                .Scroll      => data.scrollHandler      = cb,
                .TextChanged => data.changedTextHandler = cb,
                .Resize      => data.resizeHandler      = cb
            }
        }

        /// Requests a redraw
        pub fn requestDraw(self: *T) !void {
            if (c.UpdateWindow(self.peer) == 0) {
                return Win32Error.UnknownError;
            }
        }

        pub fn getWidth(self: *const T) c_int {
            var rect: RECT = undefined;
            _ = GetWindowRect(self.peer, &rect);
            return rect.right - rect.left;
        }

        pub fn getHeight(self: *const T) c_int {
            var rect: RECT = undefined;
            _ = GetWindowRect(self.peer, &rect);
            return rect.bottom - rect.top;
        }

    };
}

pub const MouseButton = enum {
    Left,
    Middle,
    Right
};

pub const Canvas = struct {
    peer: HWND,
    data: usize = 0,

    pub const DrawContext = struct {};
};

pub const Button = struct {
    peer: HWND,
    data: usize = 0,
    clickHandler: ?fn(data: usize) void = null,
    oldWndProc: ?WNDPROC = null,
    arena: std.heap.ArenaAllocator,

    pub usingnamespace Events(Button);

    var classRegistered = false;

    pub fn create() !Button {
        const hwnd = try createWindowExA(
            WS_EX_LEFT,                               // dwExtStyle
            "BUTTON",                                 // lpClassName
            "",                                       // lpWindowName
            WS_TABSTOP | WS_CHILD | BS_DEFPUSHBUTTON, // dwStyle
            10,                                       // X
            10,                                       // Y
            100,                                      // nWidth
            100,                                      // nHeight
            defaultWHWND,                             // hWindParent
            null,                                     // hMenu
            hInst,                                    // hInstance
            null                                      // lpParam
        );
        try setupEvents(hwnd);

        return Button {
            .peer = hwnd,
            .arena = std.heap.ArenaAllocator.init(std.heap.page_allocator)
        };
    }

    pub fn setLabel(self: *Button, label: [:0]const u8) void {
        const allocator = std.heap.page_allocator;
        const wide = std.unicode.utf8ToUtf16LeWithNull(allocator, label) catch return; // invalid utf8 or not enough memory
        defer allocator.free(wide);
        if (SetWindowTextW(self.peer, wide) == 0) {
            std.os.windows.unexpectedError(GetLastError()) catch {};
        }
    }

    pub fn getLabel(self: *Button) [:0]const u8 {
        const allocator = &self.arena.allocator;
        const len = GetWindowTextLengthW(self.peer);
        var buf = allocator.allocSentinel(u16, @intCast(usize, len), 0) catch unreachable; // TODO return error
        defer allocator.free(buf);
        const realLen = @intCast(usize, GetWindowTextW(self.peer, buf.ptr, len + 1));
        const utf16Slice = buf[0..realLen];
        const text = std.unicode.utf16leToUtf8AllocZ(allocator, utf16Slice) catch unreachable; // TODO return error
        return text;
    }

};

pub const Label = struct {
    peer: HWND,
    data: usize = 0,
    clickHandler: ?fn(data: usize) void = null,
    arena: std.heap.ArenaAllocator,

    pub fn create() !Label {
        const hwnd = try createWindowExA(
            WS_EX_LEFT,                               // dwExtStyle
            "STATIC",                                   // lpClassName
            "",                                       // lpWindowName
            WS_TABSTOP | WS_CHILD, // dwStyle
            10,                                       // X
            10,                                       // Y
            100,                                      // nWidth
            100,                                      // nHeight
            defaultWHWND,                             // hWindParent
            null,                                     // hMenu
            hInst,                                    // hInstance
            null                                      // lpParam
        );

        return Label {
            .peer = hwnd,
            .arena = std.heap.ArenaAllocator.init(std.heap.page_allocator)
        };
    }

    pub fn setCallback(self: *Label, eType: EventType, cb: fn(data: usize) void) !void {

    }

    pub fn setAlignment(self: *Label, alignment: f32) void {

    }

    pub fn setText(self: *Label, text: [:0]const u8) void {
        const allocator = std.heap.page_allocator;
        const wide = std.unicode.utf8ToUtf16LeWithNull(allocator, text) catch return; // invalid utf8 or not enough memory
        defer allocator.free(wide);
        if (SetWindowTextW(self.peer, wide) == 0) {
            std.os.windows.unexpectedError(GetLastError()) catch {};
        }
    }

    pub fn getText(self: *Label) [:0]const u8 {
        const allocator = &self.arena.allocator;
        const len = GetWindowTextLengthW(self.peer);
        var buf = allocator.allocSentinel(u16, @intCast(usize, len), 0) catch unreachable; // TODO return error
        defer allocator.free(buf);
        const utf16Slice = buf[0..@intCast(usize, GetWindowTextW(self.peer, buf.ptr, len + 1))];
        return std.unicode.utf16leToUtf8AllocZ(allocator, utf16Slice) catch unreachable; // TODO return error
    }

    pub fn destroy(self: *Label) void {
        self.arena.deinit();
    }

};

const ContainerStruct = struct {
    hwnd: HWND,
    count: usize,
    index: usize
};

pub const Container = struct {
    peer: HWND,

    pub usingnamespace Events(Container);

    var classRegistered = false;

    pub fn create() !Container {
        if (!classRegistered) {
            var wc: WNDCLASSEXA = .{
                .style = 0,
                .lpfnWndProc = process,
                .cbClsExtra = 0,
                .cbWndExtra = 0,
                .hInstance = hInst,
                .hIcon = null, // TODO: LoadIcon
                .hCursor = null, // TODO: LoadCursor
                .hbrBackground = null,
                .lpszMenuName = null,
                .lpszClassName = "zgtContainerClass",
                .hIconSm = null
            };

            if ((try registerClassExA(&wc)) == 0) {
                showNativeMessageDialog(.Error, "Could not register window class {s}", .{"zgtContainerClass"});
                return Win32Error.InitializationError;
            }
            classRegistered = true;
        }

        const hwnd = try createWindowExA(
            WS_EX_LEFT,                               // dwExtStyle
            "zgtContainerClass",                      // lpClassName
            "",                                       // lpWindowName
            WS_TABSTOP | WS_CHILD, // dwStyle
            10,                                       // X
            10,                                       // Y
            100,                                      // nWidth
            100,                                      // nHeight
            defaultWHWND,                             // hWindParent
            null,                                     // hMenu
            hInst,                                    // hInstance
            null                                      // lpParam
        );
        try setupEvents(hwnd);

        return Container {
            .peer = hwnd
        };
    }

    pub fn add(self: *Container, peer: PeerType) void {
        _ = SetParent(peer, self.peer);
        _ = showWindow(peer, SW_SHOWDEFAULT);
        _ = UpdateWindow(peer);
    }

    pub fn move(self: *const Container, peer: PeerType, x: u32, y: u32) void {
        var rect: RECT = undefined;
        _ = GetWindowRect(peer, &rect);
        _ = MoveWindow(peer, @intCast(c_int, x), @intCast(c_int, y), rect.right - rect.left, rect.bottom - rect.top, 1);
    }

    pub fn resize(self: *const Container, peer: PeerType, width: u32, height: u32) void {
        var rect: RECT = undefined;
        _ = GetWindowRect(peer, &rect);
        var parent: RECT = undefined;
        _ = GetWindowRect(self.peer, &parent);

        _ = MoveWindow(peer, rect.left - parent.left, rect.top - parent.top, @intCast(c_int, width), @intCast(c_int, height), 1);
    }
};

pub fn run() void {
    var msg: MSG = undefined;

    while (GetMessageA(&msg, null, 0, 0) > 0) {
        _ = TranslateMessage(&msg);
        _ = DispatchMessageA(&msg);
    }
}
