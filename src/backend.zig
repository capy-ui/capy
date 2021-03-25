const std = @import("std");
const builtin = std.builtin;

pub usingnamespace 
    if (@hasDecl(@import("root"), "zgtBackend")) @import("root").zgtBackend
    else switch (builtin.os.tag) {
        .windows => @import("backends/win32/backend.zig"),
        .linux   => @import("backends/gtk/backend.zig"),
        else     => @compileError(comptime std.fmt.comptimePrint("Unsupported OS: {}", .{builtin.os.tag}))
    };
