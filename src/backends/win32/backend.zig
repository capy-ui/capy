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
        const hInstance = @ptrCast(HINSTANCE, @alignCast(@alignOf(HINSTANCE),
            GetModuleHandleW(null).?));
        const lpCmdLine = GetCommandLineW();

        try @import("root").run();
    }

};

pub fn run() void {
    var msg: MSG = undefined;

    while (GetMessageA(&msg, null, 0, 0) > 0) {
        _ = TranslateMessage(&msg);
        _ = DispatchMessageA(&msg);
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
        _ = GetWindowRect(parent, &rect);

        const style = @intCast(u32, GetWindowLongPtrA(hwnd, GWL_STYLE));
        const exStyle = @intCast(u32, GetWindowLongPtrA(hwnd, GWL_EXSTYLE));
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
        const style = GetWindowLongPtrA(hwnd, GWL_STYLE);
        _ = SetWindowLongPtrA(hwnd, GWL_STYLE, style | WS_CHILD);
        _ = showWindow(hwnd, SW_SHOWDEFAULT);
        _ = UpdateWindow(hwnd);
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
    Click
};

pub const Button = struct {
    peer: HWND,
    data: usize = 0,
    clickHandler: ?fn(data: usize) void = null,
    oldWndProc: ?WNDPROC = null,
    arena: std.heap.ArenaAllocator,

    var classRegistered = false;

    fn process(hwnd: HWND, wm: c_uint, wp: WPARAM, lp: LPARAM) callconv(WINAPI) LRESULT {
        const userdata = GetWindowLongPtrA(hwnd, GWL_USERDATA);
        const btn = @intToPtr(*Button, @bitCast(usize, userdata));
        if (wm == WM_LBUTTONUP) {
            if (btn.clickHandler) |func| {
                func(btn.data);
            }
        }
        return btn.oldWndProc.?(hwnd, wm, wp, lp);
    }

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

        return Button {
            .peer = hwnd,
            .arena = std.heap.ArenaAllocator.init(std.heap.page_allocator)
        };
    }

    pub fn setCallback(self: *Button, eType: EventType, cb: fn(data: usize) void) !void {
        switch (eType) {
            .Click => {
                _ = try setWindowLongPtrA(self.peer, GWL_USERDATA, @bitCast(isize, @ptrToInt(self)));
                if (self.oldWndProc == null) {
                    self.oldWndProc = @intToPtr(WNDPROC, @bitCast(usize,
                        try setWindowLongPtrA(self.peer, GWL_WNDPROC, @bitCast(isize, @ptrToInt(process)))));
                }
                self.clickHandler = cb;
            }
        }
    }

    pub fn setLabel(self: *Button, label: []const u8) void {
        const allocator = std.heap.page_allocator;
        const wide = std.unicode.utf8ToUtf16LeWithNull(allocator, label) catch return; // invalid utf8 or not enough memory
        defer allocator.free(wide);
        if (SetWindowTextW(self.peer, wide) == 0) {
            std.os.windows.unexpectedError(GetLastError()) catch {};
        }
    }

    pub fn getLabel(self: *Button) []const u8 {
        const allocator = &self.arena.allocator;
        const len = GetWindowTextLengthW(self.peer);
        var buf = allocator.allocSentinel(u16, @intCast(usize, len), 0) catch unreachable; // TODO return error
        defer allocator.free(buf);
        const realLen = @intCast(usize, GetWindowTextW(self.peer, buf.ptr, len + 1));
        const utf16Slice = buf[0..realLen];
        const text = std.unicode.utf16leToUtf8Alloc(allocator, utf16Slice) catch unreachable; // TODO return error
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
        switch (eType) {
            .Click => {

            }
        }
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

pub const Row = struct {
    peer: HWND,

    var classRegistered = false;

    fn relayoutChild(hwnd: HWND, lp: LPARAM) callconv(WINAPI) c_int {
        const str = @intToPtr(*ContainerStruct, @bitCast(usize, lp));
        const count = @intCast(i32, str.count);
        const parent = str.hwnd;
        if (GetParent(hwnd) != parent) {
            return 1; // ignore recursive childrens
        }

        var rect: RECT = undefined;
        _ = GetWindowRect(parent, &rect);

        const style = @intCast(u32, GetWindowLongPtrA(hwnd, GWL_STYLE));
        const exStyle = @intCast(u32, GetWindowLongPtrA(hwnd, GWL_EXSTYLE));
        const width = rect.right - rect.left;
        const height = rect.bottom - rect.top;
        const incr = @divTrunc(width, count);

        str.index -= 1;
        _ = MoveWindow(hwnd, incr * @intCast(i32, str.index), 0, incr, height, 1);
        return 1;
    }

    fn countChild(hwnd: HWND, lp: LPARAM) callconv(WINAPI) c_int {
        const str = @intToPtr(*ContainerStruct, @bitCast(usize, lp));
        const parent = str.hwnd;
        if (GetParent(hwnd) != parent) {
            return 1; // ignore recursive childrens
        }
        str.count += 1;
        return 1;
    }

    fn process(hwnd: HWND, wm: c_uint, wp: WPARAM, lp: LPARAM) callconv(WINAPI) LRESULT {
        switch (wm) {
            WM_SIZE => {
                var str = ContainerStruct {
                    .hwnd = hwnd,
                    .count = 0,
                    .index = 0
                };
                _ = EnumChildWindows(hwnd, countChild, @bitCast(isize, @ptrToInt(&str)));
                str.index = str.count;
                _ = EnumChildWindows(hwnd, relayoutChild, @bitCast(isize, @ptrToInt(&str)));
            },
            else => {}
        }
        return DefWindowProcA(hwnd, wm, wp, lp);
    }

    pub fn create() !Row {
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
                .lpszClassName = "zgtRowClass",
                .hIconSm = null
            };

            if ((try registerClassExA(&wc)) == 0) {
                showNativeMessageDialog(.Error, "Could not register window class {s}", .{"zgtRowClass"});
                return Win32Error.InitializationError;
            }
            classRegistered = true;
        }

        const hwnd = try createWindowExA(
            WS_EX_LEFT,                               // dwExtStyle
            "zgtRowClass",                                       // lpClassName
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

        return Row {
            .peer = hwnd
        };
    }

    pub fn add(self: *Row, peer: PeerType) void {
        _ = SetParent(peer, self.peer);
        _ = showWindow(peer, SW_SHOWDEFAULT);
        _ = UpdateWindow(peer);
        // TODO: trigger relayout
    }
};

const ContainerStruct = struct {
    hwnd: HWND,
    count: usize,
    index: usize
};

pub const Column = struct {
    peer: HWND,

    var classRegistered = false;

    fn relayoutChild(hwnd: HWND, lp: LPARAM) callconv(WINAPI) c_int {
        const str = @intToPtr(*ContainerStruct, @bitCast(usize, lp));
        const count = @intCast(i32, str.count);
        const parent = str.hwnd;
        if (GetParent(hwnd) != parent) {
            return 1; // ignore recursive childrens
        }

        var rect: RECT = undefined;
        _ = GetWindowRect(parent, &rect);

        const style = @intCast(u32, GetWindowLongPtrA(hwnd, GWL_STYLE));
        const exStyle = @intCast(u32, GetWindowLongPtrA(hwnd, GWL_EXSTYLE));
        const width = rect.right - rect.left;
        const height = rect.bottom - rect.top;
        const incr = @divTrunc(height, count);

        str.index -= 1;
        _ = MoveWindow(hwnd, 0, incr * @intCast(i32, str.index), width, incr, 1);
        return 1;
    }

    fn countChild(hwnd: HWND, lp: LPARAM) callconv(WINAPI) c_int {
        const str = @intToPtr(*ContainerStruct, @bitCast(usize, lp));
        const parent = str.hwnd;
        if (GetParent(hwnd) != parent) {
            return 1; // ignore recursive childrens
        }
        str.count += 1;
        return 1;
    }

    fn process(hwnd: HWND, wm: c_uint, wp: WPARAM, lp: LPARAM) callconv(WINAPI) LRESULT {
        switch (wm) {
            WM_SIZE => {
                var str = ContainerStruct {
                    .hwnd = hwnd,
                    .count = 0,
                    .index = 0
                };
                _ = EnumChildWindows(hwnd, countChild, @bitCast(isize, @ptrToInt(&str)));
                str.index = str.count;
                _ = EnumChildWindows(hwnd, relayoutChild, @bitCast(isize, @ptrToInt(&str)));
            },
            else => {}
        }
        return DefWindowProcA(hwnd, wm, wp, lp);
    }

    pub fn create() !Column {
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
                .lpszClassName = "zgtColumnClass",
                .hIconSm = null
            };

            if ((try registerClassExA(&wc)) == 0) {
                showNativeMessageDialog(.Error, "Could not register window class {s}", .{"zgtColumnClass"});
                return Win32Error.InitializationError;
            }
            classRegistered = true;
        }

        const hwnd = try createWindowExA(
            WS_EX_LEFT,                               // dwExtStyle
            "zgtColumnClass",                                       // lpClassName
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

        return Column {
            .peer = hwnd
        };
    }

    pub fn add(self: *Column, peer: PeerType) void {
        _ = SetParent(peer, self.peer);
        _ = showWindow(peer, SW_SHOWDEFAULT);
        _ = UpdateWindow(peer);
        // TODO: trigger relayout
    }
};