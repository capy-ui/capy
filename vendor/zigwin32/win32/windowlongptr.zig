//! The SetWindowLongPtr and GetWindowLongPtr variants are missing because they are 64-bit only
//! See: https://github.com/microsoft/win32metadata/issues/142 (SetWindowLongPtr/GetWindowLongPtr are missing)
const win32 = @import("../win32.zig");

pub usingnamespace if (@sizeOf(usize) == 8) struct {
    pub const SetWindowLongPtrA = win32.ui.windows_and_messaging.SetWindowLongPtrA;
    pub const SetWindowLongPtrW = win32.ui.windows_and_messaging.SetWindowLongPtrW;
    pub const GetWindowLongPtrA = win32.ui.windows_and_messaging.GetWindowLongPtrA;
    pub const GetWindowLongPtrW = win32.ui.windows_and_messaging.GetWindowLongPtrW;
} else struct {
    pub const SetWindowLongPtrA = win32.ui.windows_and_messaging.SetWindowLongA;
    pub const SetWindowLongPtrW = win32.ui.windows_and_messaging.SetWindowLongW;
    pub const GetWindowLongPtrA = win32.ui.windows_and_messaging.GetWindowLongA;
    pub const GetWindowLongPtrW = win32.ui.windows_and_messaging.GetWindowLongW;
};

const thismodule = @This();
pub usingnamespace switch (@import("zig.zig").unicode_mode) {
    .ansi => struct {
        pub const SetWindowLongPtr = thismodule.SetWindowLongPtrA;
        pub const GetWindowLongPtr = thismodule.GetWindowLongPtrA;
    },
    .wide => struct {
        pub const SetWindowLongPtr = thismodule.SetWindowLongPtrW;
        pub const GetWindowLongPtr = thismodule.GetWindowLongPtrW;
    },
    .unspecified => if (@import("builtin").is_test) struct {
        pub const SetWindowLongPtr = *opaque {};
        pub const GetWindowLongPtr = *opaque {};
    } else struct {
        pub const SetWindowLongPtr = @compileError("'SetWindowLongPtr' requires that UNICODE be set to true or false in the root module");
        pub const GetWindowLongPtr = @compileError("'GetWindowLongPtr' requires that UNICODE be set to true or false in the root module");
    },
};
