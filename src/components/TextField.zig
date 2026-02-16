const std = @import("std");
const backend = @import("../backend.zig");
const dataStructures = @import("../data.zig");
const internal = @import("../internal.zig");
const Size = dataStructures.Size;
const Atom = dataStructures.Atom;

/// Editable one-line text input box.
pub const TextField = struct {
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
    pub const addKeyReleaseHandler = _all.addKeyReleaseHandler;
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

    peer: ?backend.TextField = null,
    widget_data: TextField.WidgetData = .{},
    /// The text displayed by this TextField. This is assumed to be valid UTF-8.
    text: Atom([]const u8) = Atom([]const u8).of(""),
    /// Whether the TextField is read-only
    readOnly: Atom(bool) = Atom(bool).of(false),
    /// Owned copy of text from the backend (guards against backends returning
    /// temporary pointers, e.g. NSString's UTF8String on macOS).
    text_alloc: ?[]u8 = null,

    pub fn init(config: TextField.Config) TextField {
        var field = TextField.init_events(TextField{});
        internal.applyConfigStruct(&field, config);
        return field;
    }

    /// When the text is changed in the Atom([]const u8)
    fn onTextAtomChange(newValue: []const u8, userdata: ?*anyopaque) void {
        const self: *TextField = @ptrCast(@alignCast(userdata));
        if (std.mem.eql(u8, self.peer.?.getText(), newValue)) return;
        self.peer.?.setText(newValue);
    }

    fn onReadOnlyAtomChange(newValue: bool, userdata: ?*anyopaque) void {
        const self: *TextField = @ptrCast(@alignCast(userdata));
        self.peer.?.setReadOnly(newValue);
    }

    fn textChanged(userdata: usize) void {
        const self: *TextField = @ptrFromInt(userdata);
        const text = self.peer.?.getText();
        // Copy text into owned memory so the Atom doesn't hold a dangling
        // pointer (macOS backend returns a temporary NSString UTF8String buffer).
        const owned = internal.allocator.dupe(u8, text) catch return;
        if (self.text_alloc) |prev| internal.allocator.free(prev);
        self.text_alloc = owned;
        self.text.set(owned);
    }

    pub fn show(self: *TextField) !void {
        if (self.peer == null) {
            var peer = try backend.TextField.create();
            peer.setText(self.text.get());
            peer.setReadOnly(self.readOnly.get());
            self.peer = peer;

            try self.setupEvents();
            try peer.setCallback(.TextChanged, textChanged);
            _ = try self.text.addChangeListener(.{ .function = onTextAtomChange, .userdata = self });
            _ = try self.readOnly.addChangeListener(.{ .function = onReadOnlyAtomChange, .userdata = self });
        }
    }

    pub fn getPreferredSize(self: *TextField, available: Size) Size {
        _ = available;
        if (self.peer) |peer| {
            return peer.getPreferredSize();
        } else {
            return Size{ .width = 200.0, .height = 40.0 };
        }
    }

    pub fn setText(self: *TextField, text: []const u8) void {
        self.text.set(text);
    }

    pub fn getText(self: *TextField) []const u8 {
        return self.text.get();
    }

    pub fn setReadOnly(self: *TextField, readOnly: bool) void {
        self.readOnly.set(readOnly);
    }

    pub fn isReadOnly(self: *TextField) bool {
        return self.readOnly.get();
    }
};

pub fn textField(config: TextField.Config) *TextField {
    return TextField.alloc(config);
}
