//! Export zgt as a C API
const std = @import("std");
const zgt = @import("main.zig");

const allocator = std.heap.c_allocator;

// TODO: define errors (in a stable way)

/// Initializes the backend that zgt uses.
/// Returns 0 on success, and 1 or above on error
export fn zgt_init_backend() c_int {
    zgt.backend.init() catch |err| {
        return @intCast(c_int, @errorToInt(err) + 1);
    };
    return 0;
}

/// Returns null on error
export fn zgt_window_init() ?*zgt.Window {
    const window = allocator.create(zgt.Window) catch return null;

    window.* = zgt.Window.init() catch {
        // can't benefit from errdefer in a C function
        allocator.destroy(window);
        return null;
    };
    return window;
}

export fn zgt_window_show(window: *zgt.Window) void {
    window.show();
}

export fn zgt_run_event_loop() void {
    zgt.runEventLoop();
}
