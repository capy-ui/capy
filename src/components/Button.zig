const std = @import("std");
const backend = @import("../backend.zig");
const internal = @import("../internal.zig");
const Size = @import("../data.zig").Size;
const Atom = @import("../data.zig").Atom;

/// A button you can click.
pub const Button = struct {
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

    peer: ?backend.Button = null,
    widget_data: Button.WidgetData = .{},
    /// The label the button will take. For example, if this is 'Test', the user will see a button
    /// which, at the center, has the text 'Test'
    label: Atom([:0]const u8) = Atom([:0]const u8).of(""),
    /// Whether the user can interact with the button, this corresponds to whether the button can be
    /// pressed or not.
    enabled: Atom(bool) = Atom(bool).of(true),

    pub fn init(config: Button.Config) Button {
        var btn = Button.init_events(Button{});
        internal.applyConfigStruct(&btn, config);
        return btn;
    }

    fn onEnabledAtomChange(newValue: bool, userdata: ?*anyopaque) void {
        const self: *Button = @ptrCast(@alignCast(userdata));
        self.peer.?.setEnabled(newValue);
    }

    fn onLabelAtomChange(newValue: [:0]const u8, userdata: ?*anyopaque) void {
        const self: *Button = @ptrCast(@alignCast(userdata));
        self.peer.?.setLabel(newValue);
    }

    pub fn show(self: *Button) !void {
        if (self.peer == null) {
            var peer = try backend.Button.create();
            peer.setEnabled(self.enabled.get());
            peer.setLabel(self.label.get());
            self.peer = peer;
            try self.setupEvents();
            _ = try self.enabled.addChangeListener(.{ .function = onEnabledAtomChange, .userdata = self });
            _ = try self.label.addChangeListener(.{ .function = onLabelAtomChange, .userdata = self });
        }
    }

    pub fn getPreferredSize(self: *Button, available: Size) Size {
        _ = available;
        if (self.peer) |peer| {
            return peer.getPreferredSize();
        } else {
            return Size{ .width = 100.0, .height = 40.0 };
        }
    }

    pub fn setLabel(self: *Button, label: [:0]const u8) void {
        self.label.set(label);
    }

    pub fn getLabel(self: *Button) [:0]const u8 {
        return self.label.get();
    }
};

pub fn button(config: Button.Config) *Button {
    return Button.alloc(config);
}

fn onButtonClicked(btn: *Button) !void {
    btn.setLabel("Stop!");
}

test Button {
    var btn = button(.{ .label = "Test Label", .onclick = @ptrCast(&onButtonClicked) });
    btn.ref(); // because we're keeping a reference, we need to ref() it
    defer btn.unref();
    try std.testing.expectEqualStrings("Test Label", btn.getLabel());

    btn.setLabel("New Label");
    try std.testing.expectEqualStrings("New Label", btn.getLabel());

    try backend.init();
    try btn.show();

    btn.enabled.set(true);

    try std.testing.expectEqualStrings("New Label", btn.getLabel());
    btn.setLabel("One more time");
    try std.testing.expectEqualStrings("One more time", btn.getLabel());
}
