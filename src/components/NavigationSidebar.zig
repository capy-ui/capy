const std = @import("std");
const backend = @import("../backend.zig");
const Size = @import("../data.zig").Size;
const DataWrapper = @import("../data.zig").DataWrapper;
const Container_Impl = @import("../containers.zig").Container_Impl;

pub const NavigationSidebar_Impl = struct {
    pub usingnamespace @import("../internal.zig").All(NavigationSidebar_Impl);

    peer: ?backend.NavigationSidebar = null,
    handlers: NavigationSidebar_Impl.Handlers = undefined,
    dataWrappers: NavigationSidebar_Impl.DataWrappers = .{},

    pub fn init() NavigationSidebar_Impl {
        return NavigationSidebar_Impl.init_events(NavigationSidebar_Impl{});
    }

    pub fn _pointerMoved(self: *NavigationSidebar_Impl) void {
        _ = self;
    }

    pub fn show(self: *NavigationSidebar_Impl) !void {
        if (self.peer == null) {
            self.peer = try backend.NavigationSidebar.create();
            try self.show_events();
        }
    }

    pub fn getPreferredSize(self: *NavigationSidebar_Impl, available: Size) Size {
        _ = available;
        if (self.peer) |peer| {
            return peer.getPreferredSize();
        } else {
            return Size{ .width = 100.0, .height = 40.0 };
        }
    }
};

pub fn NavigationSidebar(config: NavigationSidebar_Impl.Config) NavigationSidebar_Impl {
    var btn = NavigationSidebar_Impl.init();
    btn.dataWrappers.name.set(config.name);
    if (config.onclick) |onclick| {
        btn.addClickHandler(onclick) catch unreachable; // TODO: improve
    }
    return btn;
}
