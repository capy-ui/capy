const backend = @import("backend.zig");

pub const Widget = struct {
    data: usize,
    peer: ?backend.PeerType = null,
    container_expanded: bool = false,
    showFn: fn(widget: *Widget) anyerror!void,
    // layouting
    x: f64 = 0,
    y: f64 = 0,
    width: f64 = 0,
    height: f64 = 0,

    pub fn show(self: *Widget) anyerror!void {
        try self.showFn(self);
    }

    pub fn as(self: *Widget, comptime T: type) *T {
        return @intToPtr(*T, self.data);
    }
};
