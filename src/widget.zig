const backend = @import("backend");

pub const Widget = struct {
    data: usize,
    peer: backend.PeerType,
    container_expanded: bool = false,

    pub fn as(self: *Widget, comptime T: type) *T {
        return @intToPtr(*T, self.data);
    }
};

