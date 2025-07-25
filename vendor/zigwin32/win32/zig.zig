//! This module is maintained by hand and is copied to the generated code directory
const std = @import("std");
const builtin = @import("builtin");
const testing = std.testing;

const mod_root = @import("../win32.zig");
const win32 = struct {
    const BOOL = mod_root.foundation.BOOL;
    const WIN32_ERROR = mod_root.foundation.WIN32_ERROR;
    const HRESULT = mod_root.foundation.HRESULT;
    const HWND = mod_root.foundation.HWND;
    const HANDLE = mod_root.foundation.HANDLE;
    const LPARAM = mod_root.foundation.LPARAM;
    const POINT = mod_root.foundation.POINT;
    const SIZE = mod_root.foundation.SIZE;
    const RECT = mod_root.foundation.RECT;

    const HDC = mod_root.graphics.gdi.HDC;
    const HGDIOBJ = mod_root.graphics.gdi.HGDIOBJ;
    const HBRUSH = mod_root.graphics.gdi.HBRUSH;
    const PAINTSTRUCT = mod_root.graphics.gdi.PAINTSTRUCT;

    const GetLastError = mod_root.foundation.GetLastError;
    const CloseHandle = mod_root.foundation.CloseHandle;
    const FormatMessageA = mod_root.system.diagnostics.debug.FormatMessageA;
    const DeleteObject = mod_root.graphics.gdi.DeleteObject;
    const DeleteDC = mod_root.graphics.gdi.DeleteDC;
    const InvalidateRect = mod_root.graphics.gdi.InvalidateRect;
    const BeginPaint = mod_root.graphics.gdi.BeginPaint;
    const EndPaint = mod_root.graphics.gdi.EndPaint;
    const CreateSolidBrush = mod_root.graphics.gdi.CreateSolidBrush;
    const FillRect = mod_root.graphics.gdi.FillRect;
    const TextOutA = mod_root.graphics.gdi.TextOutA;
    const TextOutW = mod_root.graphics.gdi.TextOutW;
    const GetTextExtentPoint32A = mod_root.graphics.gdi.GetTextExtentPoint32A;
    const GetTextExtentPoint32W = mod_root.graphics.gdi.GetTextExtentPoint32W;
    const MESSAGEBOX_STYLE = mod_root.ui.windows_and_messaging.MESSAGEBOX_STYLE;
    const MessageBoxA = mod_root.ui.windows_and_messaging.MessageBoxA;
    const GetWindowLongPtrA = mod_root.ui.windows_and_messaging.GetWindowLongPtrA;
    const GetWindowLongPtrW = mod_root.ui.windows_and_messaging.GetWindowLongPtrW;
    const SetWindowLongPtrA = mod_root.ui.windows_and_messaging.SetWindowLongPtrA;
    const SetWindowLongPtrW = mod_root.ui.windows_and_messaging.SetWindowLongPtrW;
    const GetClientRect = mod_root.ui.windows_and_messaging.GetClientRect;
    const GetDpiForWindow = mod_root.ui.hi_dpi.GetDpiForWindow;
};

const root = @import("root");
pub const UnicodeMode = enum { ansi, wide, unspecified };
pub const unicode_mode: UnicodeMode = if (@hasDecl(root, "UNICODE")) (if (root.UNICODE) .wide else .ansi) else .unspecified;

const is_zig_0_11 = std.mem.eql(u8, builtin.zig_version_string, "0.11.0");
const zig_version_0_13 = std.SemanticVersion{ .major = 0, .minor = 13, .patch = 0 };

pub const L = std.unicode.utf8ToUtf16LeStringLiteral;

pub const TCHAR = switch (unicode_mode) {
    .ansi => u8,
    .wide => u16,
    .unspecified => if (builtin.is_test) void else @compileError("'TCHAR' requires that UNICODE be set to true or false in the root module"),
};
pub const _T = switch (unicode_mode) {
    .ansi => (struct {
        pub fn _T(comptime str: []const u8) *const [str.len:0]u8 {
            return str;
        }
    })._T,
    .wide => L,
    .unspecified => if (builtin.is_test) void else @compileError("'_T' requires that UNICODE be set to true or false in the root module"),
};

pub const Arch = enum { X86, X64, Arm64 };
pub const arch: Arch = switch (builtin.target.cpu.arch) {
    .x86 => .X86,
    .x86_64 => .X64,
    .arm, .armeb, .aarch64 => .Arm64,
    else => @compileError("unhandled arch " ++ @tagName(builtin.target.cpu.arch)),
};

// TODO: this should probably be in the standard lib somewhere?
pub const Guid = extern union {
    Ints: extern struct {
        a: u32,
        b: u16,
        c: u16,
        d: [8]u8,
    },
    Bytes: [16]u8,

    const big_endian_hex_offsets = [16]u6{ 0, 2, 4, 6, 9, 11, 14, 16, 19, 21, 24, 26, 28, 30, 32, 34 };
    const little_endian_hex_offsets = [16]u6{ 6, 4, 2, 0, 11, 9, 16, 14, 19, 21, 24, 26, 28, 30, 32, 34 };

    const hex_offsets = if (is_zig_0_11) switch (builtin.target.cpu.arch.endian()) {
        .Big => big_endian_hex_offsets,
        .Little => little_endian_hex_offsets,
    } else switch (builtin.target.cpu.arch.endian()) {
        .big => big_endian_hex_offsets,
        .little => little_endian_hex_offsets,
    };

    pub fn initString(s: []const u8) Guid {
        var guid = Guid{ .Bytes = undefined };
        for (hex_offsets, 0..) |hex_offset, i| {
            //guid.Bytes[i] = decodeHexByte(s[offset..offset+2]);
            guid.Bytes[i] = decodeHexByte([2]u8{ s[hex_offset], s[hex_offset + 1] });
        }
        return guid;
    }
};
comptime {
    std.debug.assert(@sizeOf(Guid) == 16);
}

// TODO: is this in the standard lib somewhere?
fn hexVal(c: u8) u4 {
    if (c <= '9') return @as(u4, @intCast(c - '0'));
    if (c >= 'a') return @as(u4, @intCast(c + 10 - 'a'));
    return @as(u4, @intCast(c + 10 - 'A'));
}

// TODO: is this in the standard lib somewhere?
fn decodeHexByte(hex: [2]u8) u8 {
    return @as(u8, @intCast(hexVal(hex[0]))) << 4 | hexVal(hex[1]);
}

test "Guid" {
    if (is_zig_0_11) {
        try testing.expect(std.mem.eql(u8, switch (builtin.target.cpu.arch.endian()) {
            .Big => "\x01\x23\x45\x67\x89\xAB\xEF\x10\x32\x54\x76\x98\xba\xdc\xfe\x91",
            .Little => "\x67\x45\x23\x01\xAB\x89\x10\xEF\x32\x54\x76\x98\xba\xdc\xfe\x91",
        }, &Guid.initString("01234567-89AB-EF10-3254-7698badcfe91").Bytes));
    } else {
        try testing.expect(std.mem.eql(u8, switch (builtin.target.cpu.arch.endian()) {
            .big => "\x01\x23\x45\x67\x89\xAB\xEF\x10\x32\x54\x76\x98\xba\xdc\xfe\x91",
            .little => "\x67\x45\x23\x01\xAB\x89\x10\xEF\x32\x54\x76\x98\xba\xdc\xfe\x91",
        }, &Guid.initString("01234567-89AB-EF10-3254-7698badcfe91").Bytes));
    }
}

pub const PropertyKey = extern struct {
    fmtid: Guid,
    pid: u32,
    pub fn init(fmtid: []const u8, pid: u32) PropertyKey {
        return .{
            .fmtid = Guid.initString(fmtid),
            .pid = pid,
        };
    }
};

pub fn FAILED(hr: win32.HRESULT) bool {
    return hr < 0;
}
pub fn SUCCEEDED(hr: win32.HRESULT) bool {
    return hr >= 0;
}

// These constants were removed from the metadata to allow each projection
// to define them however they like (see https://github.com/microsoft/win32metadata/issues/530)
pub const FALSE: win32.BOOL = 0;
pub const TRUE: win32.BOOL = 1;

/// Returns a formatter that will print the given error in the following format:
///
///   <error-code> (<message-string>[...])
///
/// For example:
///
///   2 (The system cannot find the file specified.)
///   5 (Access is denied.)
///
/// The error is formatted using FormatMessage into a stack allocated buffer
/// of 300 bytes. If the message exceeds 300 bytes (Messages can be arbitrarily
/// long) then "..." is appended to the message.  The message may contain newlines
/// and carriage returns but any trailing ones are trimmed.
///
/// Provide the 's' fmt specifier to omit the error code.
pub fn fmtError(error_code: u32) FormatError(300) {
    return .{ .error_code = error_code };
}
pub fn FormatError(comptime max_len: usize) type {
    return struct {
        error_code: u32,
        pub fn format(
            self: @This(),
            comptime fmt: []const u8,
            options: std.fmt.FormatOptions,
            writer: anytype,
        ) @TypeOf(writer).Error!void {
            _ = options;

            const with_code = comptime blk: {
                if (std.mem.eql(u8, fmt, "")) break :blk true;
                if (std.mem.eql(u8, fmt, "s")) break :blk false;
                @compileError("expected '{}' or '{s}' but got '{" ++ fmt ++ "}'");
            };
            if (with_code) try writer.print("{} (", .{self.error_code});
            var buf: [max_len]u8 = undefined;
            const len = win32.FormatMessageA(
                .{ .FROM_SYSTEM = 1, .IGNORE_INSERTS = 1 },
                null,
                self.error_code,
                0,
                @ptrCast(&buf),
                buf.len,
                null,
            );
            if (len == 0) {
                try writer.writeAll("unknown error");
            }
            const msg = std.mem.trimRight(u8, buf[0..len], "\r\n");
            try writer.writeAll(msg);
            if (len + 1 >= buf.len) {
                try writer.writeAll("...");
            }
            if (with_code) try writer.writeAll(")");
        }
    };
}

threadlocal var thread_is_panicing = false;

pub const PanicType = switch (builtin.zig_version.order(zig_version_0_13)) {
    .lt, .eq => fn ([]const u8, ?*std.builtin.StackTrace, ?usize) noreturn,
    .gt => type,
};

/// Returns a panic handler that can be set in your root module that will show the panic
/// message to the user in a message box, then call the default builtin panic handler.
/// It also handles re-entrancy by skipping the message box if the current thread
/// is already panicing.
pub fn messageBoxThenPanic(
    opt: struct {
        title: [:0]const u8,
        style: win32.MESSAGEBOX_STYLE = .{ .ICONASTERISK = 1 },
        // TODO: add option/logic to include the stacktrace in the messagebox
    },
) PanicType {
    switch (comptime builtin.zig_version.order(zig_version_0_13)) {
        .lt, .eq => return struct {
            pub fn panic(
                msg: []const u8,
                error_return_trace: ?*std.builtin.StackTrace,
                ret_addr: ?usize,
            ) noreturn {
                if (!thread_is_panicing) {
                    thread_is_panicing = true;
                    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
                    const msg_z: [:0]const u8 = if (std.fmt.allocPrintZ(
                        arena.allocator(),
                        "{s}",
                        .{msg},
                    )) |msg_z| msg_z else |_| "failed allocate error message";
                    _ = win32.MessageBoxA(null, msg_z, opt.title, opt.style);
                }
                std.builtin.default_panic(msg, error_return_trace, ret_addr);
            }
        }.panic,
        .gt => {},
    }
    return std.debug.FullPanic(struct {
        pub fn panic(
            msg: []const u8,
            ret_addr: ?usize,
        ) noreturn {
            if (!thread_is_panicing) {
                thread_is_panicing = true;
                var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
                const msg_z: [:0]const u8 = if (std.fmt.allocPrintZ(
                    arena.allocator(),
                    "{s}",
                    .{msg},
                )) |msg_z| msg_z else |_| "failed allocate error message";
                _ = win32.MessageBoxA(null, msg_z, opt.title, opt.style);
            }
            std.debug.defaultPanic(msg, ret_addr);
        }
    }.panic);
}

/// Calls std.debug.panic with a message that indicates what failed and the
/// associated win32 error code.
pub fn panicWin32(what: []const u8, err: win32.WIN32_ERROR) noreturn {
    std.debug.panic("{s} failed, error={}", .{ what, err });
}

/// Calls std.debug.panic with a message that indicates what failed and the
/// associated hresult error code.
pub fn panicHresult(what: []const u8, hresult: win32.HRESULT) noreturn {
    std.debug.panic("{s} failed, hresult=0x{x}", .{ what, @as(u32, @bitCast(hresult)) });
}

/// calls CloseHandle, panics on failure
pub fn closeHandle(handle: win32.HANDLE) void {
    if (0 == win32.CloseHandle(handle)) panicWin32(
        "CloseHandle",
        win32.GetLastError(),
    );
}

pub fn xFromLparam(lparam: win32.LPARAM) i16 {
    return @bitCast(loword(lparam));
}
pub fn yFromLparam(lparam: win32.LPARAM) i16 {
    return @bitCast(hiword(lparam));
}
pub fn pointFromLparam(lparam: win32.LPARAM) win32.POINT {
    return win32.POINT{ .x = xFromLparam(lparam), .y = yFromLparam(lparam) };
}

pub fn loword(value: anytype) u16 {
    switch (comptime builtin.zig_version.order(zig_version_0_13)) {
        .gt => switch (@typeInfo(@TypeOf(value))) {
            .int => |int| switch (int.signedness) {
                .signed => return loword(@as(@Type(.{ .int = .{ .signedness = .unsigned, .bits = int.bits } }), @bitCast(value))),
                .unsigned => return if (int.bits <= 16) value else @intCast(0xffff & value),
            },
            else => {},
        },
        .lt, .eq => switch (@typeInfo(@TypeOf(value))) {
            .Int => |int| switch (int.signedness) {
                .signed => return loword(@as(@Type(.{ .Int = .{ .signedness = .unsigned, .bits = int.bits } }), @bitCast(value))),
                .unsigned => return if (int.bits <= 16) value else @intCast(0xffff & value),
            },
            else => {},
        },
    }
    @compileError("unsupported type " ++ @typeName(@TypeOf(value)));
}
pub fn hiword(value: anytype) u16 {
    switch (comptime builtin.zig_version.order(zig_version_0_13)) {
        .gt => switch (@typeInfo(@TypeOf(value))) {
            .int => |int| switch (int.signedness) {
                .signed => return hiword(@as(@Type(.{ .int = .{ .signedness = .unsigned, .bits = int.bits } }), @bitCast(value))),
                .unsigned => return @intCast(0xffff & (value >> 16)),
            },
            else => {},
        },
        .lt, .eq => switch (@typeInfo(@TypeOf(value))) {
            .Int => |int| switch (int.signedness) {
                .signed => return hiword(@as(@Type(.{ .Int = .{ .signedness = .unsigned, .bits = int.bits } }), @bitCast(value))),
                .unsigned => return @intCast(0xffff & (value >> 16)),
            },
            else => {},
        },
    }
    @compileError("unsupported type " ++ @typeName(@TypeOf(value)));
}

pub const has_window_longptr = switch (arch) {
    .X86 => false,
    .X64, .Arm64 => true,
};

pub const getWindowLongPtr = switch (unicode_mode) {
    .ansi => getWindowLongPtrA,
    .wide => getWindowLongPtrW,
    .unspecified => if (builtin.is_test) struct {} else @compileError(
        "getWindowLongPtr requires that UNICODE be set to true or false in the root module",
    ),
};

pub const setWindowLongPtr = switch (unicode_mode) {
    .ansi => setWindowLongPtrA,
    .wide => setWindowLongPtrW,
    .unspecified => if (builtin.is_test) struct {} else @compileError(
        "setWindowLongPtr requires that UNICODE be set to true or false in the root module",
    ),
};

pub fn getWindowLongPtrA(hwnd: win32.HWND, index: i32) usize {
    if (!has_window_longptr) @compileError("this arch does not have GetWindowLongPtr");
    return @bitCast(win32.GetWindowLongPtrA(hwnd, @enumFromInt(index)));
}
pub fn getWindowLongPtrW(hwnd: win32.HWND, index: i32) usize {
    if (!has_window_longptr) @compileError("this arch does not have GetWindowLongPtr");
    return @bitCast(win32.GetWindowLongPtrW(hwnd, @enumFromInt(index)));
}
pub fn setWindowLongPtrA(hwnd: win32.HWND, index: i32, value: usize) usize {
    if (!has_window_longptr) @compileError("this arch does not have SetWindowLongPtr");
    return @bitCast(win32.SetWindowLongPtrA(hwnd, @enumFromInt(index), @bitCast(value)));
}
pub fn setWindowLongPtrW(hwnd: win32.HWND, index: i32, value: usize) usize {
    if (!has_window_longptr) @compileError("this arch does not have SetWindowLongPtr");
    return @bitCast(win32.SetWindowLongPtrW(hwnd, @enumFromInt(index), @bitCast(value)));
}

/// calls DpiForWindow, panics on failure
pub fn dpiFromHwnd(hwnd: win32.HWND) u32 {
    const value = win32.GetDpiForWindow(hwnd);
    if (value == 0) panicWin32("GetDpiForWindow", win32.GetLastError());
    return value;
}

/// Converts the given DPI to a floating point scale where 96 returns 1.0, 120 return 1.25 and so on.
pub fn scaleFromDpi(comptime Float: type, dpi: u32) Float {
    return @as(Float, @floatFromInt(dpi)) / @as(Float, 96.0);
}

pub fn scaleDpi(comptime T: type, value: T, dpi: u32) T {
    std.debug.assert(dpi >= 96);
    return switch (comptime builtin.zig_version.order(zig_version_0_13)) {
        .gt => switch (@typeInfo(T)) {
            .float => value * scaleFromDpi(T, dpi),
            .int => @intFromFloat(@round(@as(f32, @floatFromInt(value)) * scaleFromDpi(f32, dpi))),
            else => @compileError("scale_dpi does not support type " ++ @typeName(@TypeOf(value))),
        },
        .lt, .eq => switch (@typeInfo(T)) {
            .Float => value * scaleFromDpi(T, dpi),
            .Int => @intFromFloat(@round(@as(f32, @floatFromInt(value)) * scaleFromDpi(f32, dpi))),
            else => @compileError("scale_dpi does not support type " ++ @typeName(@TypeOf(value))),
        },
    };
}

/// wrapper for GetClientRect, panics on failure
pub fn getClientSize(hwnd: win32.HWND) win32.SIZE {
    var rect: win32.RECT = undefined;
    if (0 == win32.GetClientRect(hwnd, &rect))
        panicWin32("GetClientRect", win32.GetLastError());
    std.debug.assert(rect.left == 0);
    std.debug.assert(rect.top == 0);
    return .{ .cx = rect.right, .cy = rect.bottom };
}

/// Converts comptime values to the given type.
/// Note that this function is called at compile time rather than converting constant values earlier at code generation time.
/// The reason for doing it a compile time is because genzig.zig generates all constants as they are encountered which can
/// be before it knows the constant's type definition, so we delay the convession to compile-time where the compiler knows
/// all type definition.
pub fn typedConst(comptime T: type, comptime value: anytype) T {
    return switch (comptime builtin.zig_version.order(zig_version_0_13)) {
        .gt => typedConst2(T, T, value),
        .lt, .eq => typedConst2_0_13(T, T, value),
    };
}

fn typedConst2(comptime ReturnType: type, comptime SwitchType: type, comptime value: anytype) ReturnType {
    const target_type_error = @as([]const u8, "typedConst cannot convert to " ++ @typeName(ReturnType));
    const value_type_error = @as([]const u8, "typedConst cannot convert " ++ @typeName(@TypeOf(value)) ++ " to " ++ @typeName(ReturnType));

    switch (@typeInfo(SwitchType)) {
        .int => |target_type_info| {
            if (value >= std.math.maxInt(SwitchType)) {
                if (target_type_info.signedness == .signed) {
                    const UnsignedT = @Type(std.builtin.Type{ .int = .{ .signedness = .unsigned, .bits = target_type_info.bits } });
                    return @as(SwitchType, @bitCast(@as(UnsignedT, value)));
                }
            }
            return value;
        },
        .pointer => |target_type_info| switch (target_type_info.size) {
            .one, .many, .c => {
                switch (@typeInfo(@TypeOf(value))) {
                    .comptime_int, .int => {
                        const usize_value = if (value >= 0) value else @as(usize, @bitCast(@as(isize, value)));
                        return @as(ReturnType, @ptrFromInt(usize_value));
                    },
                    else => @compileError(value_type_error),
                }
            },
            else => target_type_error,
        },
        .optional => |target_type_info| switch (@typeInfo(target_type_info.child)) {
            .pointer => return typedConst2(ReturnType, target_type_info.child, value),
            else => target_type_error,
        },
        .@"enum" => |_| switch (@typeInfo(@TypeOf(value))) {
            .Int => return @as(ReturnType, @enumFromInt(value)),
            else => target_type_error,
        },
        else => @compileError(target_type_error),
    }
}
fn typedConst2_0_13(comptime ReturnType: type, comptime SwitchType: type, comptime value: anytype) ReturnType {
    const target_type_error = @as([]const u8, "typedConst cannot convert to " ++ @typeName(ReturnType));
    const value_type_error = @as([]const u8, "typedConst cannot convert " ++ @typeName(@TypeOf(value)) ++ " to " ++ @typeName(ReturnType));

    switch (@typeInfo(SwitchType)) {
        .Int => |target_type_info| {
            if (value >= std.math.maxInt(SwitchType)) {
                if (target_type_info.signedness == .signed) {
                    const UnsignedT = @Type(std.builtin.Type{ .Int = .{ .signedness = .unsigned, .bits = target_type_info.bits } });
                    return @as(SwitchType, @bitCast(@as(UnsignedT, value)));
                }
            }
            return value;
        },
        .Pointer => |target_type_info| switch (target_type_info.size) {
            .One, .Many, .C => {
                switch (@typeInfo(@TypeOf(value))) {
                    .ComptimeInt, .Int => {
                        const usize_value = if (value >= 0) value else @as(usize, @bitCast(@as(isize, value)));
                        return @as(ReturnType, @ptrFromInt(usize_value));
                    },
                    else => @compileError(value_type_error),
                }
            },
            else => target_type_error,
        },
        .Optional => |target_type_info| switch (@typeInfo(target_type_info.child)) {
            .Pointer => return typedConst2_0_13(ReturnType, target_type_info.child, value),
            else => target_type_error,
        },
        .Enum => |_| switch (@typeInfo(@TypeOf(value))) {
            .Int => return @as(ReturnType, @enumFromInt(value)),
            else => target_type_error,
        },
        else => @compileError(target_type_error),
    }
}
test "typedConst" {
    try testing.expectEqual(@as(usize, @bitCast(@as(isize, -1))), @intFromPtr(typedConst(?*opaque {}, -1)));
    try testing.expectEqual(@as(usize, @bitCast(@as(isize, -12))), @intFromPtr(typedConst(?*opaque {}, -12)));
    try testing.expectEqual(@as(u32, 0xffffffff), typedConst(u32, 0xffffffff));
    try testing.expectEqual(@as(i32, @bitCast(@as(u32, 0x80000000))), typedConst(i32, 0x80000000));
}

// =============================================================================
// GDI function wrappers
// =============================================================================

/// calls DeleteObject, panics on failure
pub fn deleteObject(obj: win32.HGDIOBJ) void {
    if (0 == win32.DeleteObject(obj)) panicWin32("DeleteObject", win32.GetLastError());
}

/// calls DeleteDC, panics on failure
pub fn deleteDc(hdc: win32.HDC) void {
    if (0 == win32.DeleteDC(hdc)) panicWin32("DeleteDC", win32.GetLastError());
}

/// calls InvalidateRect, panics on failure
pub fn invalidateHwnd(hwnd: win32.HWND) void {
    if (0 == win32.InvalidateRect(hwnd, null, 0)) panicWin32("InvalidateRect", win32.GetLastError());
}

/// calls BeginPaint, panics on failure
pub fn beginPaint(hwnd: win32.HWND) struct { win32.HDC, win32.PAINTSTRUCT } {
    var paintstruct: win32.PAINTSTRUCT = undefined;
    const hdc = win32.BeginPaint(hwnd, &paintstruct) orelse panicWin32(
        "BeginPaint",
        win32.GetLastError(),
    );
    return .{ hdc, paintstruct };
}
/// calls EndPaint, panics on failure
pub fn endPaint(hwnd: win32.HWND, paintstruct: *const win32.PAINTSTRUCT) void {
    if (0 == win32.EndPaint(hwnd, paintstruct)) panicWin32(
        "EndPaint",
        win32.GetLastError(),
    );
}

/// calls CreateSolidBrush, panics on failure
pub fn createSolidBrush(color: u32) win32.HBRUSH {
    return win32.CreateSolidBrush(color) orelse panicWin32(
        "CreateSolidBrush",
        win32.GetLastError(),
    );
}

/// calls FillRect, panics on failure
pub fn fillRect(hdc: win32.HDC, rect: win32.RECT, brush: win32.HBRUSH) void {
    if (0 == win32.FillRect(hdc, &rect, brush)) panicWin32(
        "FillRect",
        win32.GetLastError(),
    );
}

/// calls TextOutA, panics on failure
pub fn textOutA(hdc: win32.HDC, x: i32, y: i32, msg: []const u8) void {
    if (0 == win32.TextOutA(hdc, x, y, @ptrCast(msg.ptr), @intCast(msg.len))) panicWin32(
        "TextOut",
        win32.GetLastError(),
    );
}

/// calls TextOutW, panics on failure
pub fn textOutW(hdc: win32.HDC, x: i32, y: i32, msg: []const u16) void {
    if (0 == win32.TextOutW(hdc, x, y, @ptrCast(msg.ptr), @intCast(msg.len))) panicWin32(
        "TextOut",
        win32.GetLastError(),
    );
}

/// calls GetTextExtentPoint32A, panics on failure
pub fn getTextExtentA(hdc: win32.HDC, str: []const u8) win32.SIZE {
    var size: win32.SIZE = undefined;
    if (0 == win32.GetTextExtentPoint32A(hdc, @ptrCast(str.ptr), @intCast(str.len), &size)) panicWin32(
        "GetTextExtentPoint32A",
        win32.GetLastError(),
    );
    return size;
}

/// calls GetTextExtentPoint32W, panics on failure
pub fn getTextExtentW(hdc: win32.HDC, str: []const u16) win32.SIZE {
    var size: win32.SIZE = undefined;
    if (0 == win32.GetTextExtentPoint32W(hdc, @ptrCast(str.ptr), @intCast(str.len), &size)) panicWin32(
        "GetTextExtentPoint32W",
        win32.GetLastError(),
    );
    return size;
}
