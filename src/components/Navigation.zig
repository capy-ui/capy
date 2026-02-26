const std = @import("std");
const backend = @import("../backend.zig");
const internal = @import("../internal.zig");
const Size = @import("../data.zig").Size;
const Atom = @import("../data.zig").Atom;
const Widget = @import("../widget.zig").Widget;

pub const Navigation = struct {
    const _all = @import("../internal.zig").All(@This());
    pub const WidgetData = _all.WidgetData;
    pub const WidgetClass = _all.WidgetClass;
    pub const Atoms = _all.Atoms;
    pub const Config = _all.Config;
    pub const Callback = _all.Callback;
    pub const DrawCallback = _all.DrawCallback;
    pub const ButtonCallback = _all.ButtonCallback;
    pub const MouseMoveCallback = _all.MouseMoveCallback;
    pub const ScrollCallback = _all.ScrollCallback;
    pub const ResizeCallback = _all.ResizeCallback;
    pub const KeyTypeCallback = _all.KeyTypeCallback;
    pub const KeyPressCallback = _all.KeyPressCallback;
    pub const PropertyChangeCallback = _all.PropertyChangeCallback;
    pub const Handlers = _all.Handlers;
    pub const init_events = _all.init_events;
    pub const setupEvents = _all.setupEvents;
    pub const addClickHandler = _all.addClickHandler;
    pub const addDrawHandler = _all.addDrawHandler;
    pub const addMouseButtonHandler = _all.addMouseButtonHandler;
    pub const addMouseMotionHandler = _all.addMouseMotionHandler;
    pub const addScrollHandler = _all.addScrollHandler;
    pub const addResizeHandler = _all.addResizeHandler;
    pub const addKeyTypeHandler = _all.addKeyTypeHandler;
    pub const addKeyPressHandler = _all.addKeyPressHandler;
    pub const addPropertyChangeHandler = _all.addPropertyChangeHandler;
    pub const requestDraw = _all.requestDraw;
    pub const alloc = _all.alloc;
    pub const ref = _all.ref;
    pub const unref = _all.unref;
    pub const showWidget = _all.showWidget;
    pub const isDisplayedFn = _all.isDisplayedFn;
    pub const deinitWidget = _all.deinitWidget;
    pub const getPreferredSizeWidget = _all.getPreferredSizeWidget;
    pub const getX = _all.getX;
    pub const getY = _all.getY;
    pub const getSize = _all.getSize;
    pub const getWidth = _all.getWidth;
    pub const getHeight = _all.getHeight;
    pub const asWidget = _all.asWidget;
    pub const addUserdata = _all.addUserdata;
    pub const withUserdata = _all.withUserdata;
    pub const getUserdata = _all.getUserdata;
    pub const set = _all.set;
    pub const get = _all.get;
    pub const bind = _all.bind;
    pub const withProperty = _all.withProperty;
    pub const withBinding = _all.withBinding;
    pub const getName = _all.getName;
    pub const setName = _all.setName;
    pub const getParent = _all.getParent;
    pub const getRoot = _all.getRoot;
    pub const getAnimationController = _all.getAnimationController;
    pub const clone = _all.clone;
    pub const widget_clone = _all.widget_clone;
    pub const deinit = _all.deinit;

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
    var routes = std.StringHashMap(*Widget).init(internal.allocator);
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

    const instance = @import("../internal.zig").allocator.create(Navigation) catch @panic("out of memory");
    instance.* = try Navigation.init(opts, routes);
    instance.widget_data.widget = @import("../internal.zig").genericWidgetFrom(instance);
    return instance;
}
