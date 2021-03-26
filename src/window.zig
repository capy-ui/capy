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

    fn isErrorUnion(comptime T: type) bool {
        return switch (@typeInfo(T)) {
            .ErrorUnion => true,
            else => false
        };
    }

    /// wrappedContainer can be an error union, a pointer to the container or the container itself.
    pub fn set(self: *Window, wrappedContainer: anytype) callconv(.Inline) anyerror!void {
        var container = 
            if (comptime isErrorUnion(@TypeOf(wrappedContainer)))
                try wrappedContainer
            else
                wrappedContainer;

        try container.show();
        self.peer.setChild(container.peer.?.peer);
    }

    pub fn resize(self: *Window, width: u32, height: u32) void {
        self.peer.resize(
            @intCast(c_int, width),
            @intCast(c_int, height)
        );
    }

    pub fn run(self: *Window) void {
        backend.run();
    }

};
