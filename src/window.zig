const std = @import("std");
const backend = @import("backend.zig");
const Widget = @import("widget.zig").Widget;
const Image_Impl = @import("image.zig").Image_Impl;
const MenuBar_Impl = @import("menu.zig").MenuBar_Impl;


pub const Window = struct {
    /// The DPI the GUI has been developed against
    source_dpi: u32 = 96,
    peer: backend.Window,
    _child: ?Widget = null,

    pub fn init() !Window {
        const peer = try backend.Window.create();
        return Window{ .peer = peer };
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
            else => false,
        };
    }

    /// wrappedContainer can be an error union, a pointer to the container or the container itself.
    pub inline fn set(self: *Window, wrappedContainer: anytype) anyerror!void {
        var container =
            if (comptime isErrorUnion(@TypeOf(wrappedContainer)))
            try wrappedContainer
        else
            wrappedContainer;
        const ComponentType = @import("internal.zig").DereferencedType(@TypeOf(container));

        self._child = try @import("internal.zig").genericWidgetFrom(container);
        if (ComponentType != Widget) {
            self._child.?.as(ComponentType).dataWrappers.widget = &self._child.?;
        }

        try self._child.?.show();

        self.peer.setChild(self._child.?.peer);
    }

    pub fn getChild(self: Window) ?Widget {
        return self._child;
    }

    pub fn resize(self: *Window, width: u32, height: u32) void {
        self.peer.resize(@intCast(c_int, width), @intCast(c_int, height));
    }

    pub fn setTitle(self: *Window, title: [:0]const u8) void {
        self.peer.setTitle(title);
    }

    pub fn setMenuBar(self: *Window, bar: MenuBar_Impl) void {
        self.peer.setMenuBar(bar);
    }

    pub fn setIcon(self: *Window, icon: *Image_Impl) void {
        self.peer.setIcon(icon.data.peer);
    }

    pub fn setIconName(self: *Window, name: [:0]const u8) void {
        self.peer.setIconName(name);
    }

    pub fn setProgramName(self: *Window, name: [:0]const u8) void {
        self.peer.setProgramName(name);
    }

    pub fn deinit(self: *Window) void {
        if (self._child) |*child| {
            child.deinit();
        }
    }
};
