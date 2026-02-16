const std = @import("std");
const backend = @import("../backend.zig");
const dataStructures = @import("../data.zig");
const internal = @import("../internal.zig");
const Size = dataStructures.Size;
const Atom = dataStructures.Atom;

/// Editable multi-line text input box.
pub const TextArea = struct {
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

    peer: ?backend.TextArea = null,
    widget_data: TextArea.WidgetData = .{},
    /// The text this TextArea contains.
    text: Atom([]const u8) = Atom([]const u8).of(""),
    /// Owned copy of text from the backend (guards against backends returning
    /// temporary pointers, e.g. NSString's UTF8String on macOS).
    text_alloc: ?[]u8 = null,

    // TODO: replace with TextArea.setFont(.{ .family = "monospace" }) ?
    /// Whether to let the system choose a monospace font for us and use it in this TextArea..
    monospace: Atom(bool) = Atom(bool).of(false),

    pub fn init(config: TextArea.Config) TextArea {
        var area = TextArea.init_events(TextArea{
            .text = Atom([]const u8).of(config.text),
            .monospace = Atom(bool).of(config.monospace),
        });
        @import("../internal.zig").applyConfigStruct(&area, config);
        area.setName(config.name);
        return area;
    }

    fn onTextAtomChanged(newValue: []const u8, userdata: ?*anyopaque) void {
        const self: *TextArea = @ptrCast(@alignCast(userdata));
        if (std.mem.eql(u8, self.peer.?.getText(), newValue)) return;
        self.peer.?.setText(newValue);
    }

    fn onMonospaceAtomChanged(newValue: bool, userdata: ?*anyopaque) void {
        const self: *TextArea = @ptrCast(@alignCast(userdata));
        self.peer.?.setMonospaced(newValue);
    }

    fn textChanged(userdata: usize) void {
        const self = @as(*TextArea, @ptrFromInt(userdata));
        const text = self.peer.?.getText();
        // Copy text into owned memory so the Atom doesn't hold a dangling
        // pointer (macOS backend returns a temporary NSString UTF8String buffer).
        const owned = internal.allocator.dupe(u8, text) catch return;
        if (self.text_alloc) |prev| internal.allocator.free(prev);
        self.text_alloc = owned;
        self.text.set(owned);
    }

    pub fn show(self: *TextArea) !void {
        if (self.peer == null) {
            var peer = try backend.TextArea.create();
            peer.setText(self.text.get());
            peer.setMonospaced(self.monospace.get());
            self.peer = peer;
            try self.setupEvents();

            try peer.setCallback(.TextChanged, textChanged);
            _ = try self.text.addChangeListener(.{ .function = onTextAtomChanged, .userdata = self });
            _ = try self.monospace.addChangeListener(.{ .function = onMonospaceAtomChanged, .userdata = self });
        }
    }

    pub fn getPreferredSize(self: *TextArea, available: Size) Size {
        _ = available;
        if (self.peer) |peer| {
            return peer.getPreferredSize();
        } else {
            return Size{ .width = 100.0, .height = 100.0 };
        }
    }

    pub fn setText(self: *TextArea, text: []const u8) void {
        self.text.set(text);
    }

    pub fn getText(self: *TextArea) []const u8 {
        return self.text.get();
    }
};

pub fn textArea(config: TextArea.Config) *TextArea {
    return TextArea.alloc(config);
}
