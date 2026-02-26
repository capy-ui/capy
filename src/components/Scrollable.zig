const std = @import("std");
const backend = @import("../backend.zig");
const Size = @import("../data.zig").Size;
const Atom = @import("../data.zig").Atom;
const Widget = @import("../widget.zig").Widget;

pub const Scrollable = struct {
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

    peer: ?backend.ScrollView = null,
    widget_data: Scrollable.WidgetData = .{},
    child: Atom(*Widget),

    pub fn init(config: Scrollable.Config) Scrollable {
        var component = Scrollable.init_events(Scrollable{ .child = Atom(*Widget).of(config.child) });
        @import("../internal.zig").applyConfigStruct(&component, config);
        return component;
    }

    // TODO: handle child change

    pub fn show(self: *Scrollable) !void {
        if (self.peer == null) {
            var peer = try backend.ScrollView.create();
            try self.child.get().show();
            peer.setChild(self.child.get().peer.?, self.child.get());
            self.peer = peer;
            try self.setupEvents();
        }
    }

    pub fn getPreferredSize(self: *Scrollable, available: Size) Size {
        return self.child.get().getPreferredSize(available);
    }

    pub fn _deinit(self: *Scrollable) void {
        self.child.get().unref();
    }
};

pub fn scrollable(element: anytype) anyerror!*Scrollable {
    const child =
        if (comptime @import("../internal.zig").isErrorUnion(@TypeOf(element)))
            try element
        else
            element;
    const widget = @import("../internal.zig").getWidgetFrom(child);
    return Scrollable.alloc(.{ .child = widget });
}
