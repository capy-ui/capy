const std = @import("std");
const backend = @import("../backend.zig");
const Size = @import("../data.zig").Size;
const DataWrapper = @import("../data.zig").DataWrapper;
const Container_Impl = @import("../containers.zig").Container_Impl;

pub const NavigationSidebar = struct {
    pub usingnamespace @import("../internal.zig").All(NavigationSidebar);

    peer: ?backend.NavigationSidebar = null,
    widget_data: NavigationSidebar.WidgetData = .{},

    pub fn init() NavigationSidebar {
        return NavigationSidebar.init_events(NavigationSidebar{});
    }

    pub fn _pointerMoved(self: *NavigationSidebar) void {
        _ = self;
    }

    pub fn show(self: *NavigationSidebar) !void {
        if (self.peer == null) {
            self.peer = try backend.NavigationSidebar.create();
            try self.show_events();
        }
    }

    pub fn getPreferredSize(self: *NavigationSidebar, available: Size) Size {
        _ = available;
        if (self.peer) |peer| {
            return peer.getPreferredSize();
        } else {
            return Size{ .width = 100.0, .height = 40.0 };
        }
    }
};

pub fn navigationSidebar(config: NavigationSidebar.Config) NavigationSidebar {
    var btn = NavigationSidebar.init();
    btn.widget_data.atoms.name.set(config.name);
    if (config.onclick) |onclick| {
        btn.addClickHandler(onclick) catch unreachable; // TODO: improve
    }
    return btn;
}
