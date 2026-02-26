const std = @import("std");
const backend = @import("../backend.zig");
const internal = @import("../internal.zig");
const Size = @import("../data.zig").Size;
const Atom = @import("../data.zig").Atom;
const capy = @import("../capy.zig");

/// Label containing text for the user to view.
pub const Label = struct {
    const _all = internal.All(@This());
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

    peer: ?backend.Label = null,
    widget_data: Label.WidgetData = .{},
    /// The text the label will take. For instance, if this is 'Example', the user
    /// will see the text 'Example'.
    text: Atom([]const u8) = Atom([]const u8).of(""),
    /// Defines how the text will show and take up available space.
    layout: Atom(capy.TextLayout) = Atom(capy.TextLayout).of(.{}),

    pub fn init(config: Label.Config) Label {
        var lbl = Label.init_events(Label{});
        internal.applyConfigStruct(&lbl, config);
        return lbl;
    }

    fn onTextAtomChange(newValue: []const u8, userdata: ?*anyopaque) void {
        const self: *Label = @ptrCast(@alignCast(userdata.?));
        self.peer.?.setText(newValue);
    }

    fn onTextLayoutAtomChange(newValue: capy.TextLayout, userdata: ?*anyopaque) void {
        const self: *Label = @ptrCast(@alignCast(userdata.?));
        self.peer.?.setAlignment(switch (newValue.alignment) {
            .Left => 0,
            .Center => 0.5,
            .Right => 1,
        });
        self.peer.?.setFont(newValue.font);
    }

    pub fn show(self: *Label) !void {
        if (self.peer == null) {
            var peer = try backend.Label.create();
            peer.setText(self.text.get());
            self.peer = peer;
            try self.setupEvents();
            _ = try self.text.addChangeListener(.{ .function = onTextAtomChange, .userdata = self });
            _ = try self.layout.addChangeListener(.{ .function = onTextLayoutAtomChange, .userdata = self });
            onTextLayoutAtomChange(self.layout.get(), self);
        }
    }

    pub fn getPreferredSize(self: *Label, available: Size) Size {
        _ = available;
        if (self.peer) |peer| {
            return peer.getPreferredSize();
        } else {
            // Crude approximation
            const len = self.text.get().len;
            return Size{ .width = @floatFromInt(10 * len), .height = 40.0 };
        }
    }

    pub fn setText(self: *Label, text: []const u8) void {
        self.text.set(text);
    }

    pub fn getText(self: *Label) []const u8 {
        return self.text.get();
    }
};

pub fn label(config: Label.Config) *Label {
    return Label.alloc(config);
}

// TODO: replace with an actual empty element from the backend
// Although this is not necessary and would only provide minimal memory/performance gains
pub fn spacing() !*@import("../widget.zig").Widget {
    return try @import("../containers.zig").expanded(label(.{}));
}
