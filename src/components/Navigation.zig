const std = @import("std");
const backend = @import("../backend.zig");
const internal = @import("../internal.zig");
const Size = @import("../data.zig").Size;
const Atom = @import("../data.zig").Atom;
const Widget = @import("../widget.zig").Widget;

pub const Navigation_Impl = struct {
    pub usingnamespace @import("../internal.zig").All(Navigation_Impl);

    peer: ?backend.Container = null,
    widget_data: Navigation_Impl.WidgetData = .{},

    relayouting: std.atomic.Atomic(bool) = std.atomic.Atomic(bool).init(false),
    routeName: Atom([]const u8),
    activeChild: *Widget,
    routes: std.StringHashMap(Widget),

    pub fn init(config: Navigation_Impl.Config, routes: std.StringHashMap(Widget)) !Navigation_Impl {
        var iterator = routes.valueIterator();
        const activeChild = iterator.next() orelse @panic("navigation component is empty");
        var component = Navigation_Impl.init_events(Navigation_Impl{
            .routeName = Atom([]const u8).of(config.routeName),
            .routes = routes,
            .activeChild = activeChild,
        });
        try component.addResizeHandler(&onResize);

        return component;
    }

    pub fn _pointerMoved(self: *Navigation_Impl) void {
        self.routeName.updateBinders();
    }

    pub fn onResize(self: *Navigation_Impl, _: Size) !void {
        self.relayout();
    }

    pub fn getChild(self: *Navigation_Impl, name: []const u8) ?*Widget {
        // TODO: check self.activeChild.get if it's a container or something like that
        if (self.activeChild.name.*.get()) |child_name| {
            if (std.mem.eql(u8, child_name, name)) {
                return &self.activeChild;
            }
        }
        return null;
    }

    pub fn _showWidget(widget: *Widget, self: *Navigation_Impl) !void {
        self.activeChild.parent = widget;
        self.activeChild.class.setWidgetFn(self.activeChild);
    }

    pub fn show(self: *Navigation_Impl) !void {
        if (self.peer == null) {
            var peer = try backend.Container.create();
            self.peer = peer;

            self.activeChild.class.setWidgetFn(self.activeChild);
            try self.activeChild.show();
            peer.add(self.activeChild.peer.?);

            try self.show_events();
        }
    }

    pub fn relayout(self: *Navigation_Impl) void {
        if (self.relayouting.load(.SeqCst) == true) return;
        if (self.peer) |peer| {
            self.relayouting.store(true, .SeqCst);
            defer self.relayouting.store(false, .SeqCst);

            const available = Size{
                .width = @as(u32, @intCast(peer.getWidth())),
                .height = @as(u32, @intCast(peer.getHeight())),
            };

            if (self.activeChild.peer) |widgetPeer| {
                peer.move(widgetPeer, 0, 0);
                peer.resize(widgetPeer, available.width, available.height);
            }
        }
    }

    /// Go deep inside the given URI.
    /// This will show up as entering the given screen, which you can exit using pop()
    /// This is analoguous to zooming in on a screen.
    pub fn push(self: *Navigation_Impl, name: []const u8, params: anytype) void {
        // TODO: implement push
        self.navigateTo(name, params);
    }

    /// Navigate to a given screen without pushing it on the stack.
    /// This is analoguous to sliding to a screen.
    pub fn navigateTo(self: *Navigation_Impl, name: []const u8, params: anytype) !void {
        _ = params;
        if (self.peer) |*peer| {
            peer.remove(self.activeChild.peer.?);
            const child = self.routes.getPtr(name) orelse return error.NoSuchRoute;
            self.activeChild = child;
            try self.activeChild.show();
            peer.add(self.activeChild.peer.?);
        }
    }

    pub fn pop(self: *Navigation_Impl) void {
        _ = self;
        // TODO: implement pop
    }

    pub fn getPreferredSize(self: *Navigation_Impl, available: Size) Size {
        return self.activeChild.getPreferredSize(available);
    }

    pub fn _deinit(self: *Navigation_Impl) void {
        var iterator = self.routes.valueIterator();
        while (iterator.next()) |widget| {
            widget.deinit();
        }
    }
};

pub fn Navigation(opts: Navigation_Impl.Config, children: anytype) anyerror!Navigation_Impl {
    var routes = std.StringHashMap(Widget).init(internal.lasting_allocator);
    const fields = std.meta.fields(@TypeOf(children));

    inline for (fields) |field| {
        const child = @field(children, field.name);
        const element =
            if (comptime internal.isErrorUnion(@TypeOf(child)))
            try child
        else
            child;
        const widget = try internal.genericWidgetFrom(element);
        try routes.put(field.name, widget);
    }

    return try Navigation_Impl.init(opts, routes);
}
