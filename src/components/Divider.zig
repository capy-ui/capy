const std = @import("std");
const backend = @import("../backend.zig");
const Size = @import("../data.zig").Size;
const Atom = @import("../data.zig").Atom;
const Color = @import("../color.zig").Color;
const sys = @import("../system_colors.zig");
const Orientation = @import("Slider.zig").Orientation;

/// A horizontal or vertical line separator.
pub const Divider = struct {
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
    widget_data: Divider.WidgetData = .{},

    orientation: Atom(Orientation) = Atom(Orientation).of(.Horizontal),
    color: Atom(Color) = Atom(Color).of(Color.fromRGB(0xCC, 0xCC, 0xCC)),
    thickness: Atom(f32) = Atom(f32).of(1.0),

    pub fn init(config: Divider.Config) Divider {
        var div = Divider.init_events(Divider{});
        div.color.set(sys.separator());
        @import("../internal.zig").applyConfigStruct(&div, config);
        div.addDrawHandler(&Divider.draw) catch unreachable;
        return div;
    }

    pub fn getPreferredSize(self: *Divider, available: Size) Size {
        const t = @max(1.0, self.thickness.get());
        return switch (self.orientation.get()) {
            .Horizontal => available.intersect(Size.init(available.width, t)),
            .Vertical => available.intersect(Size.init(t, available.height)),
        };
    }

    pub fn draw(self: *Divider, ctx: *backend.DrawContext) !void {
        ctx.setColorByte(self.color.get());
        ctx.rectangle(0, 0, self.getWidth(), self.getHeight());
        ctx.fill();
    }

    pub fn show(self: *Divider) !void {
        if (self.peer == null) {
            self.peer = try backend.Canvas.create();
            _ = try self.color.addChangeListener(.{ .function = struct {
                fn callback(_: Color, userdata: ?*anyopaque) void {
                    const ptr: *Divider = @ptrCast(@alignCast(userdata.?));
                    ptr.peer.?.requestDraw() catch {};
                }
            }.callback, .userdata = self });
            _ = try self.thickness.addChangeListener(.{ .function = struct {
                fn callback(_: f32, userdata: ?*anyopaque) void {
                    const ptr: *Divider = @ptrCast(@alignCast(userdata.?));
                    ptr.peer.?.requestDraw() catch {};
                }
            }.callback, .userdata = self });
            try self.setupEvents();
        }
    }
};

pub fn divider(config: Divider.Config) *Divider {
    return Divider.alloc(config);
}

test "Divider default properties" {
    try backend.init();
    const d = Divider.alloc(.{});
    defer d.deinit();

    try std.testing.expectEqual(Orientation.Horizontal, d.orientation.get());
    try std.testing.expectApproxEqAbs(@as(f32, 1.0), d.thickness.get(), 0.001);
    // Default color is light gray (0xCC, 0xCC, 0xCC)
    const c = d.color.get();
    try std.testing.expectEqual(@as(u8, 0xCC), c.red);
    try std.testing.expectEqual(@as(u8, 0xCC), c.green);
    try std.testing.expectEqual(@as(u8, 0xCC), c.blue);
}

test "Divider with custom orientation" {
    try backend.init();
    const d = Divider.alloc(.{ .orientation = .Vertical, .thickness = 3.0 });
    defer d.deinit();

    try std.testing.expectEqual(Orientation.Vertical, d.orientation.get());
    try std.testing.expectApproxEqAbs(@as(f32, 3.0), d.thickness.get(), 0.001);
}

test Divider {
    var div1 = divider(.{ .orientation = .Horizontal });
    div1.ref();
    defer div1.unref();
    try std.testing.expectEqual(Orientation.Horizontal, div1.orientation.get());
    try std.testing.expectApproxEqAbs(@as(f32, 1.0), div1.thickness.get(), 0.001);

    var div2 = divider(.{ .orientation = .Vertical, .thickness = 2.0 });
    div2.ref();
    defer div2.unref();
    try std.testing.expectEqual(Orientation.Vertical, div2.orientation.get());
    try std.testing.expectApproxEqAbs(@as(f32, 2.0), div2.thickness.get(), 0.001);
}
