const std = @import("std");
const backend = @import("../backend.zig");
const internal = @import("../internal.zig");
const Size = @import("../data.zig").Size;
const ListAtom = @import("../data.zig").ListAtom;
const Atom = @import("../data.zig").Atom;

/// A dropdown to select a value.
pub const Dropdown = struct {
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

    peer: ?backend.Dropdown = null,
    widget_data: Dropdown.WidgetData = .{},
    /// The list of values that the user can select in the dropdown.
    /// The strings are owned by the caller.
    values: ListAtom([]const u8),
    /// Whether the user can interact with the button, that is
    /// whether the button can be pressed or not.
    enabled: Atom(bool) = Atom(bool).of(true),
    selected_index: Atom(usize) = Atom(usize).of(0),
    // TODO: exclude of Dropdown.Config
    /// This is a read-only property.
    selected_value: Atom([]const u8) = Atom([]const u8).of(""),

    pub fn init(config: Dropdown.Config) Dropdown {
        var component = Dropdown.init_events(Dropdown{
            .values = ListAtom([]const u8).init(internal.allocator),
        });
        internal.applyConfigStruct(&component, config);
        // TODO: self.selected_value.dependOn(&.{ self.values, self.selected_index })
        return component;
    }

    fn onEnabledAtomChange(newValue: bool, userdata: ?*anyopaque) void {
        const self: *Dropdown = @ptrCast(@alignCast(userdata));
        self.peer.?.setEnabled(newValue);
    }

    fn onSelectedIndexAtomChange(newValue: usize, userdata: ?*anyopaque) void {
        const self: *Dropdown = @ptrCast(@alignCast(userdata));
        self.peer.?.setSelectedIndex(newValue);
        self.selected_value.set(self.values.get(newValue));
    }

    fn onValuesChange(list: *ListAtom([]const u8), userdata: ?*anyopaque) void {
        const self: *Dropdown = @ptrCast(@alignCast(userdata));
        self.selected_value.set(list.get(self.selected_index.get()));
        var iterator = list.iterate();
        defer iterator.deinit();
        self.peer.?.setValues(iterator.getSlice());
    }

    fn onPropertyChange(self: *Dropdown, property_name: []const u8, new_value: *const anyopaque) !void {
        if (std.mem.eql(u8, property_name, "selected")) {
            const value: *const usize = @ptrCast(@alignCast(new_value));
            self.selected_index.set(value.*);
        }
    }

    pub fn show(self: *Dropdown) !void {
        if (self.peer == null) {
            var peer = try backend.Dropdown.create();
            peer.setEnabled(self.enabled.get());
            {
                var iterator = self.values.iterate();
                defer iterator.deinit();
                peer.setValues(iterator.getSlice());
            }
            self.selected_value.set(self.values.get(self.selected_index.get()));
            peer.setSelectedIndex(self.selected_index.get());
            self.peer = peer;
            try self.setupEvents();
            _ = try self.enabled.addChangeListener(.{ .function = onEnabledAtomChange, .userdata = self });
            _ = try self.selected_index.addChangeListener(.{ .function = onSelectedIndexAtomChange, .userdata = self });
            _ = try self.values.addChangeListener(.{ .function = onValuesChange, .userdata = self });
            try self.addPropertyChangeHandler(&onPropertyChange);
        }
    }

    pub fn getPreferredSize(self: *Dropdown, available: Size) Size {
        _ = available;
        if (self.peer) |peer| {
            return peer.getPreferredSize();
        } else {
            return Size{ .width = 100.0, .height = 40.0 };
        }
    }
};

pub fn dropdown(config: Dropdown.Config) *Dropdown {
    return Dropdown.alloc(config);
}
