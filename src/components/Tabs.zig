const std = @import("std");
const backend = @import("../backend.zig");
const Size = @import("../data.zig").Size;
const Atom = @import("../data.zig").Atom;
const Widget = @import("../widget.zig").Widget;
const isErrorUnion = @import("../internal.zig").isErrorUnion;

pub const Tabs = struct {
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

    peer: ?backend.TabContainer = null,
    widget_data: Tabs.WidgetData = .{},
    tabs: Atom(std.ArrayList(Tab)),

    /// The widget associated to this Tabs
    widget: ?*Widget = null,

    pub fn init(config: Tabs.Config) Tabs {
        return Tabs.init_events(Tabs{ .tabs = Atom(std.ArrayList(Tab)).of(config.tabs) });
    }

    pub fn show(self: *Tabs) !void {
        if (self.peer == null) {
            var peer = try backend.TabContainer.create();
            for (self.tabs.get().items) |*tab_ptr| {
                try tab_ptr.widget.show();
                const tabPosition = peer.insert(peer.getTabsNumber(), tab_ptr.widget.peer.?);
                peer.setLabel(tabPosition, tab_ptr.label);
            }
            self.peer = peer;
            try self.setupEvents();
        }
    }

    pub fn getPreferredSize(self: *Tabs, available: Size) Size {
        _ = self;
        return available; // TODO
    }

    pub fn _showWidget(widget: *Widget, self: *Tabs) !void {
        self.widget = widget;
        for (self.tabs.get().items) |*child| {
            child.widget.parent = widget;
        }
    }

    pub fn add(self: *Tabs, widget: anytype) !void {
        var genericWidget = @import("../internal.zig").getWidgetFrom(widget);
        genericWidget.ref();
        if (self.widget) |parent| {
            genericWidget.parent = parent;
        }

        const slot = try self.tab.addOne();
        slot.* = .{ .label = "Untitled Tab", .widget = genericWidget };

        if (self.peer) |*peer| {
            try slot.show();
            peer.insert(peer.getTabsNumber(), slot.peer.?);
        }
    }

    pub fn _deinit(self: *Tabs) void {
        for (self.tabs.get().items) |*tab_ptr| {
            tab_ptr.widget.unref();
        }
        var tabs_list = self.tabs.get();
        tabs_list.deinit(@import("../internal.zig").allocator);
    }
};

pub inline fn tabs(children: anytype) anyerror!*Tabs {
    const fields = std.meta.fields(@TypeOf(children));
    var list: std.ArrayList(Tab) = .empty;
    const alloc = @import("../internal.zig").allocator;
    inline for (fields) |field| {
        const element = @field(children, field.name);
        const tab1 =
            if (comptime isErrorUnion(@TypeOf(element))) // if it is an error union, unwrap it
                try element
            else
                element;
        tab1.widget.ref();
        const slot = try list.addOne(alloc);
        slot.* = tab1;
    }

    const instance = @import("../internal.zig").allocator.create(Tabs) catch @panic("out of memory");
    instance.* = Tabs.init(.{ .tabs = list });
    instance.widget_data.widget = @import("../internal.zig").genericWidgetFrom(instance);
    return instance;
}

pub const Tab = struct {
    label: [:0]const u8,
    widget: *Widget,
};

pub const TabConfig = struct {
    label: [:0]const u8 = "",
};

pub inline fn tab(config: TabConfig, child: anytype) anyerror!Tab {
    const widget = @import("../internal.zig").getWidgetFrom(if (comptime isErrorUnion(@TypeOf(child)))
        try child
    else
        child);
    return Tab{
        .label = config.label,
        .widget = widget,
    };
}
