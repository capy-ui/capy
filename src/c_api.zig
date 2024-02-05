//! Export capy as a C API
const std = @import("std");
const capy = @import("capy");

const allocator = std.heap.c_allocator;

pub const CapyWindow = *capy.Window;
pub const CapyWidget = *capy.Widget;

// TODO: define errors (in a stable way)

/// Initializes the backend that capy uses.
/// Returns 0 on success, and 1 or above on error
export fn capy_init_backend() c_int {
    capy.backend.init() catch |err| {
        return @as(c_int, @intCast(@intFromError(err) + 1));
    };
    return 0;
}

// Window //

/// Returns null on error
export fn capy_window_init() ?CapyWindow {
    const window = allocator.create(capy.Window) catch return null;

    window.* = capy.Window.init() catch {
        // can't benefit from errdefer in a C function
        allocator.destroy(window);
        return null;
    };
    return window;
}

export fn capy_window_show(window: CapyWindow) void {
    window.show();
}

export fn capy_window_close(window: CapyWindow) void {
    window.close();
}

export fn capy_window_deinit(window: CapyWindow) void {
    window.deinit();
    allocator.destroy(window);
}

export fn capy_window_set_preferred_size(window: CapyWindow, width: c_uint, height: c_uint) void {
    window.setPreferredSize(width, height);
}

export fn capy_window_set(window: CapyWindow, widget: CapyWidget) c_int {
    window.set(widget) catch |err| {
        return @as(c_int, @intCast(@intFromError(err) + 1));
    };
    return 0;
}

export fn capy_window_get_child(window: CapyWindow) ?CapyWidget {
    return window._child;
}

// Button //
/// Returns null on error
export fn capy_button_new() ?CapyWidget {
    const button = capy.button(.{});
    return capy.internal.getWidgetFrom(button);
}

export fn capy_button_set_label(widget: CapyWidget, label: [*:0]const u8) void {
    const button = widget.as(capy.Button);
    button.label.set(std.mem.span(label));
}

export fn capy_run_event_loop() void {
    capy.runEventLoop();
}
