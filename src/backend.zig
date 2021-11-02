const std = @import("std");
const builtin = @import("builtin");

pub usingnamespace 
    if (@hasDecl(@import("root"), "zgtBackend")) @import("root").zgtBackend
    else switch (builtin.os.tag) {
        .windows => @import("backends/win32/backend.zig"),
        .linux => @import("backends/gtk/backend.zig"),
        .freestanding => blk: {
            if (builtin.cpu.arch == .wasm32) {
                break :blk @import("backends/wasm/backend.zig");
            } else {
                @compileError("Unsupported OS: freestanding");
            }
        },
        else => @compileError(std.fmt.comptimePrint("Unsupported OS: {}", .{builtin.os.tag}))
    };
