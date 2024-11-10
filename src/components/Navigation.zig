const std = @import("std");
const backend = @import("../backend.zig");
const internal = @import("../internal.zig");
const Size = @import("../data.zig").Size;
const Atom = @import("../data.zig").Atom;
const Widget = @import("../widget.zig").Widget;

pub const Navigation = struct {
    pub usingnamespace @import("../internal.zig").All(Navigation);

    peer: ?backend.Container = null,
    widget_data: Navigation.WidgetData = .{},

    relayouting: std.atomic.Value(bool) = std.atomic.Value(bool).init(false),
    routeName: Atom([]const u8),
    activeChild: *Widget,
    routes: std.StringHashMap(*Widget),

    pub fn init(config: Navigation.Config, routes: std.StringHashMap(*Widget)) !Navigation {
        var iterator = routes.valueIterator();
        const activeChild = iterator.next() orelse @panic("navigation component is empty");
        var component = Navigation.init_events(Navigation{
            .routeName = Atom([]const u8).of(config.routeName),
            .routes = routes,
            .activeChild = activeChild.*,
        });
        try component.addResizeHandler(&onResize);

        return component;
    }

    pub fn onResize(self: *Navigation, _: Size) !void {
        self.relayout();
    }

    pub fn getChild(self: *Navigation, name: []const u8) ?*Widget {
        // TODO: check self.activeChild.get if it's a container or something like that
        if (self.activeChild.name.*.get()) |child_name| {
            if (std.mem.eql(u8, child_name, name)) {
                return self.activeChild;
            }
        }
        return null;
    }

    pub fn _showWidget(widget: *Widget, self: *Navigation) !void {
        self.activeChild.parent = widget;
    }

    pub fn show(self: *Navigation) !void {
        if (self.peer == null) {
            var peer = try backend.Container.create();
            self.peer = peer;

            try self.activeChild.show();
            peer.add(self.activeChild.peer.?);

            try self.setupEvents();
        }
    }

    pub fn relayout(self: *Navigation) void {
        if (self.relayouting.load(.seq_cst) == true) return;
        if (self.peer) |peer| {
            self.relayouting.store(true, .seq_cst);
            defer self.relayouting.store(false, .seq_cst);

            const available = self.getSize();
            if (self.activeChild.peer) |widgetPeer| {
                peer.move(widgetPeer, 0, 0);
                peer.resize(widgetPeer, @intFromFloat(available.width), @intFromFloat(available.height));
            }
        }
    }

    /// Go deep inside the given URI.
    /// This will show up as entering the given screen, which you can exit using pop()
    /// This is analoguous to zooming in on a screen.
    pub fn push(self: *Navigation, name: []const u8, params: anytype) void {
        // TODO: implement push
        self.navigateTo(name, params);
    }

    /// Navigate to a given screen without pushing it on the stack.
    /// This is analoguous to sliding to a screen.
    pub fn navigateTo(self: *Navigation, name: []const u8, params: anytype) !void {
        _ = params;
        if (self.peer) |*peer| {
            peer.remove(self.activeChild.peer.?);
            const child = self.routes.get(name) orelse return error.NoSuchRoute;
            self.activeChild = child;
            try self.activeChild.show();
            peer.add(self.activeChild.peer.?);
        }
    }

    pub fn pop(self: *Navigation) void {
        _ = self;
        // TODO: implement pop
    }

    pub fn getPreferredSize(self: *Navigation, available: Size) Size {
        return self.activeChild.getPreferredSize(available);
    }

    pub fn _deinit(self: *Navigation) void {
        var iterator = self.routes.valueIterator();
        while (iterator.next()) |widget| {
            widget.*.unref();
        }
    }
};

pub fn navigation(opts: Navigation.Config, children: anytype) anyerror!*Navigation {
    var routes = std.StringHashMap(*Widget).init(internal.lasting_allocator);
    const fields = std.meta.fields(@TypeOf(children));

    inline for (fields) |field| {
        const child = @field(children, field.name);
        const element =
            if (comptime internal.isErrorUnion(@TypeOf(child)))
            try child
        else
            child;
        const widget = internal.getWidgetFrom(element);
        try routes.put(field.name, widget);
    }

    const instance = @import("../internal.zig").lasting_allocator.create(Navigation) catch @panic("out of memory");
    instance.* = try Navigation.init(opts, routes);
    instance.widget_data.widget = @import("../internal.zig").genericWidgetFrom(instance);
    return instance;
}
