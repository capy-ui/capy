// TODO: rename to foreach?
const std = @import("std");
const backend = @import("backend.zig");
const Widget = @import("widget.zig").Widget;
const global_allocator = @import("internal.zig").allocator;
const Size = @import("data.zig").Size;
const Rectangle = @import("data.zig").Rectangle;
const containers = @import("containers.zig");
const Atom = @import("data.zig").Atom;

pub const GenericListModel = struct {
    size: *Atom(usize),
    getComponent: *const fn (self: *anyopaque, index: usize) *Widget,
    userdata: *anyopaque,
};

pub const List = struct {
    const _all = @import("internal.zig").All(@This());
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
    widget_data: List.WidgetData = .{},
    child: *Widget,
    model: GenericListModel,

    /// The child 'widget' must be the widget of a container.
    pub fn init(widget: *Widget, model: GenericListModel) List {
        return List.init_events(List{ .child = widget, .model = model });
    }

    fn modelSizeChanged(newSize: usize, userdata: ?*anyopaque) void {
        const self: *List = @ptrCast(@alignCast(userdata));
        const container = self.child.as(containers.Container);

        // TODO: cache widgets!
        container.removeAll();
        {
            var i: usize = 0;
            while (i < newSize) : (i += 1) {
                const widget = self.model.getComponent(self.model.userdata, i);
                container.add(widget) catch {};
            }
        }
    }

    pub fn show(self: *List) !void {
        if (self.peer == null) {
            var peer = try backend.ScrollView.create();
            try self.child.show();
            peer.setChild(self.child.peer.?, self.child);
            self.peer = peer;
            try self.setupEvents();

            _ = try self.model.size.addChangeListener(.{ .function = modelSizeChanged, .userdata = self });
        }
    }

    pub fn getPreferredSize(self: *List, available: Size) Size {
        return self.child.getPreferredSize(available);
    }

    pub fn cloneImpl(self: *List) !*List {
        _ = self;
        return undefined;
    }
};

pub inline fn columnList(config: containers.GridConfig, model: anytype) anyerror!*List {
    // if (comptime !std.meta.trait.isPtrTo(.Struct)(@TypeOf(model))) {
    //     @compileError("Expected a mutable pointer to the list model");
    // }
    var row = try containers.column(config, .{});
    const ModelType = @import("internal.zig").DereferencedType(@TypeOf(model)); // The type of the list model
    const genericModel = GenericListModel{
        .size = &model.size,
        .userdata = model,
        .getComponent = struct {
            fn getComponent(self: *anyopaque, index: usize) *Widget {
                const component = ModelType.getComponent(@as(*ModelType, @ptrCast(@alignCast(self))), index);
                // Convert the component (Label, Button..) to a widget
                const widget = @import("internal.zig").getWidgetFrom(component);
                return widget;
            }
        }.getComponent,
    };

    const size = model.size.get();
    var i: usize = 0;
    while (i < size) : (i += 1) {
        const component = model.getComponent(i);
        try row.add(component);
    }

    const widget = @import("internal.zig").getWidgetFrom(row);

    const instance = global_allocator.create(List) catch @panic("out of memory");
    instance.* = List.init(widget, genericModel);
    instance.widget_data.widget = @import("internal.zig").genericWidgetFrom(instance);
    return instance;
}
