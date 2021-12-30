const std = @import("std");
const builtin = @import("builtin");

const backend = if (@hasDecl(@import("root"), "zgtBackend"))
    @import("root").zgtBackend
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
    else => @compileError(std.fmt.comptimePrint("Unsupported OS: {}", .{builtin.os.tag})),
};
pub usingnamespace backend;

test "backend: create window" {
    try backend.init();
    var window = try backend.Window.create();
    window.show();

    {var i: usize = 0; while (i < 30) : (i += 1) {
        if (i == 15) {
            window.close();
        }
        try std.testing.expectEqual(i < 15, backend.runStep(.Asynchronous));
    }}
}
