const std = @import("std");
const backend = @import("backend.zig");

pub const Window = struct {
    /// The DPI the GUI has been developed against
    source_dpi: u32 = 96,
    peer: backend.Window,

    pub fn init() !Window {
        const peer = try backend.Window.create();
        return Window {
            .peer = peer
        };
    }

    pub fn show(self: *Window) void {
        return self.peer.show();
    }

    pub fn close(self: *Window) void {
        return self.peer.close();
    }

    pub fn set(self: *Window, container: anytype) callconv(.Inline) !void {
        if (comptime std.meta.trait.isPtrTo(.Struct)(@TypeOf(container))) {
            try container.show();
            self.peer.setChild(container.peer.?.peer);
        } else {
            var cont = container;
            try cont.show();
            self.peer.setChild(cont.peer.?.peer);
        }
    }

    pub fn resize(self: *Window, width: usize, height: usize) !void {
        self.peer.resize(
            try std.math.cast(c_int, width),
            try std.math.cast(c_int, height)
        );
    }

    pub fn run(self: *Window) void {
        backend.run();
    }

};
