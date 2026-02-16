const std = @import("std");
const internal = @import("internal.zig");
const Widget = @import("widget.zig").Widget;
const Window = @import("window.zig").Window;
const containers = @import("containers.zig");
const Container = containers.Container;

/// Saved state for overlay dismiss.
pub const OverlayState = struct {
    original_child: ?*Widget,
    overlay_container: *Container,
};

/// Shows an overlay widget on top of the current window content.
/// The original child is saved so it can be restored with `dismissOverlay`.
/// Returns the OverlayState needed for dismissal.
pub fn showOverlay(window: *Window, overlay_widget: *Widget) !OverlayState {
    const original = window.getChild() orelse return error.NoWindowContent;

    // Build an ArrayList with the two children for StackLayout
    var children: std.ArrayList(*Widget) = .empty;
    try children.append(internal.allocator, original);
    try children.append(internal.allocator, overlay_widget);

    const stack_container = try Container.allocA(
        children,
        .{},
        containers.StackLayout,
        {},
    );

    try window.set(stack_container);

    return OverlayState{
        .original_child = original,
        .overlay_container = stack_container,
    };
}

/// Dismisses the overlay and restores the original window content.
pub fn dismissOverlay(window: *Window, state: OverlayState) !void {
    if (state.original_child) |original| {
        try window.set(original);
    }
}
