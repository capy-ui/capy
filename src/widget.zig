const backend = @import("backend.zig");
const data = @import("data.zig");

pub const Class = struct {
    showFn: fn(widget: *Widget) anyerror!void,
    preferredSizeFn: fn(widget: *const Widget, available: data.Size) data.Size,
};

/// A widget is a unique representation and constant size of any view.
pub const Widget = struct {
    data: usize,
    peer: ?backend.PeerType = null,
    container_expanded: bool = false,
    class: *const Class,
    name: *?[]const u8,

    /// If there is more available size than preferred size and the widget is not expanded,
    /// this will determine where will the widget be located horizontally.
    alignX: *data.DataWrapper(f32),

    /// If there is more available size than preferred size and the widget is not expanded,
    /// this will determine where will the widget be located vertically.
    alignY: *data.DataWrapper(f32),

    pub fn show(self: *Widget) anyerror!void {
        try self.class.showFn(self);
    }

    /// Get the preferred size for the given available space.
    /// With this system, minimum size is widget.getPreferredSize(Size { .width = 0, .height = 0 }),
    /// and maximum size is widget.getPreferredSize(Size { .width = std.math.maxInt(u32), .height = std.math.maxInt(u32) })
    pub fn getPreferredSize(self: *const Widget, available: data.Size) data.Size {
        return self.class.preferredSizeFn(self, available);
    }

    pub fn as(self: *Widget, comptime T: type) *T {
        return @intToPtr(*T, self.data);
    }
};
