//! Export zgt as a C API
const std = @import("std");
const zgt = @import("main.zig");

const allocator = std.heap.c_allocator;

pub const ZgtWindow = *zgt.Window;
pub const ZgtWidget = *zgt.Widget;

// TODO: define errors (in a stable way)

/// Initializes the backend that zgt uses.
/// Returns 0 on success, and 1 or above on error
export fn zgt_init_backend() c_int {
    zgt.backend.init() catch |err| {
        return @intCast(c_int, @errorToInt(err) + 1);
    };
    return 0;
}

// Window //

/// Returns null on error
export fn zgt_window_init() ?ZgtWindow {
    const window = allocator.create(zgt.Window) catch return null;

    window.* = zgt.Window.init() catch {
        // can't benefit from errdefer in a C function
        allocator.destroy(window);
        return null;
    };
    return window;
}

export fn zgt_window_show(window: ZgtWindow) void {
    window.show();
}

export fn zgt_window_close(window: ZgtWindow) void {
    window.close();
}

export fn zgt_window_deinit(window: ZgtWindow) void {
    window.deinit();
    allocator.destroy(window);
}

export fn zgt_window_resize(window: ZgtWindow, width: c_uint, height: c_uint) void {
    window.resize(width, height);
}

export fn zgt_window_set(window: ZgtWindow, widget: ZgtWidget) c_int {
    // TODO: do something about original widget object
    window.set(widget.*) catch |err| {
        return @intCast(c_int, @errorToInt(err) + 1);
    };
    return 0;
}

export fn zgt_window_get_child(window: ZgtWindow) ?ZgtWidget {
    if (window._child) |*child| {
        return child;
    } else {
        return null;
    }
}

// Button //
/// Returns null on error
export fn zgt_button(label: [*:0]const u8) ?ZgtWidget {
    const button = allocator.create(zgt.Button_Impl) catch return null;
    button.* = zgt.Button(.{ .label = std.mem.span(label) });

    const widget = allocator.create(zgt.Widget) catch return null;
    widget.* = zgt.internal.genericWidgetFrom(button) catch unreachable; // it can't error as the component doesn't have a widget and no allocation is necessary
    button.dataWrappers.widget = widget;
    return widget;
}

export fn zgt_run_event_loop() void {
    zgt.runEventLoop();
}
