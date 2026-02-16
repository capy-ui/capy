const std = @import("std");
const builtin = @import("builtin");
const backend = @import("../backend.zig");
const Size = @import("../data.zig").Size;
const Atom = @import("../data.zig").Atom;
const Color = @import("../color.zig").Color;
const Colors = @import("../color.zig").Colors;

/// Arbitrary size area on which the application may draw content.
///
/// It also has the particularity of being the only component on which the draw handler works.
pub const Canvas = struct {
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

    peer: ?backend.Canvas = null,
    widget_data: Canvas.WidgetData = .{},
    /// The preferred size of the canvas, or null to take the least possible.
    preferredSize: Atom(?Size) = Atom(?Size).of(null),

    pub const DrawContext = backend.DrawContext;

    pub fn init(config: Canvas.Config) Canvas {
        var cnv = Canvas.init_events(Canvas{});
        @import("../internal.zig").applyConfigStruct(&cnv, config);
        return cnv;
    }

    pub fn getPreferredSize(self: *Canvas, available: Size) Size {
        // As it's a canvas, by default it should take the available space
        return self.preferredSize.get() orelse available;
    }

    pub fn setPreferredSize(self: *Canvas, preferred: Size) Canvas {
        self.preferredSize.set(preferred);
        return self.*;
    }

    pub fn show(self: *Canvas) !void {
        if (self.peer == null) {
            self.peer = try backend.Canvas.create();
            try self.setupEvents();
        }
    }
};

pub fn canvas(config: Canvas.Config) *Canvas {
    return Canvas.alloc(config);
}

/// Arbitrary size area filled with a given color.
///
/// *This widget extends `Canvas`.*
pub const Rect = struct {
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

    peer: ?backend.Canvas = null,
    widget_data: Rect.WidgetData = .{},

    /// The preferred size of the canvas, or null to take the least possible.
    preferredSize: Atom(?Size) = Atom(?Size).of(null),
    /// The color the rectangle will be filled with.
    color: Atom(Color) = Atom(Color).of(Colors.black),
    /// The radiuses of the the corners of the rectangle. It can be changed to make
    /// a rounded rectangle.
    cornerRadius: Atom([4]f32) = Atom([4]f32).of(.{0.0} ** 4),

    pub fn init(config: Rect.Config) Rect {
        var rectangle = Rect.init_events(Rect{});
        @import("../internal.zig").applyConfigStruct(&rectangle, config);
        rectangle.addDrawHandler(&Rect.draw) catch unreachable;
        return rectangle;
    }

    pub fn getPreferredSize(self: *Rect, available: Size) Size {
        return self.preferredSize.get() orelse
            available.intersect(Size.init(0, 0));
    }

    pub fn setPreferredSize(self: *Rect, preferred: Size) Rect {
        self.preferredSize.set(preferred);
        return self.*;
    }

    pub fn draw(self: *Rect, ctx: *Canvas.DrawContext) !void {
        ctx.setColorByte(self.color.get());
        if (builtin.os.tag == .windows) {
            ctx.rectangle(0, 0, self.getWidth(), self.getHeight());
        } else {
            ctx.roundedRectangleEx(0, 0, self.getWidth(), self.getHeight(), self.cornerRadius.get());
        }
        ctx.fill();
    }

    pub fn show(self: *Rect) !void {
        if (self.peer == null) {
            self.peer = try backend.Canvas.create();
            _ = try self.color.addChangeListener(.{ .function = struct {
                fn callback(_: Color, userdata: ?*anyopaque) void {
                    const ptr: *Rect = @ptrCast(@alignCast(userdata.?));
                    ptr.peer.?.requestDraw() catch {};
                }
            }.callback, .userdata = self });
            _ = try self.cornerRadius.addChangeListener(.{ .function = struct {
                fn callback(_: [4]f32, userdata: ?*anyopaque) void {
                    const ptr: *Rect = @ptrCast(@alignCast(userdata.?));
                    ptr.peer.?.requestDraw() catch {};
                }
            }.callback, .userdata = self });
            try self.setupEvents();
        }
    }
};

pub fn rect(config: Rect.Config) *Rect {
    return Rect.alloc(config);
}

const fuzz = @import("../fuzz.zig");

test Canvas {
    var cnv = canvas(.{});
    cnv.ref(); // because we keep a reference to canvas we must call ref()
    defer cnv.unref();
}

test Rect {
    var rect1 = rect(.{ .color = Colors.blue });
    rect1.ref();
    defer rect1.unref();
    try std.testing.expectEqual(Colors.blue, rect1.color.get());

    var rect2 = rect(.{ .color = Colors.yellow });
    rect2.ref();
    defer rect2.unref();
    try std.testing.expectEqual(Colors.yellow, rect2.color.get());
}
