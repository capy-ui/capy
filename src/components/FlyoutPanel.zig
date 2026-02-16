const std = @import("std");
const builtin = @import("builtin");
const backend = @import("../backend.zig");
const internal = @import("../internal.zig");
const Size = @import("../data.zig").Size;
const Atom = @import("../data.zig").Atom;
const Color = @import("../color.zig").Color;
const sys = @import("../system_colors.zig");
const MouseButton = @import("../backends/shared.zig").MouseButton;

/// Edge from which the flyout panel slides in.
pub const Edge = enum { left, right };

/// A sliding overlay panel from the left or right edge with an optional scrim.
/// This is a canvas-based widget that draws a panel and scrim backdrop.
pub const FlyoutPanel = struct {
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

    peer: ?backend.Canvas = null,
    widget_data: FlyoutPanel.WidgetData = .{},

    /// Whether the panel is open.
    open: Atom(bool) = Atom(bool).of(false),
    /// Width of the panel.
    panel_size: Atom(f32) = Atom(f32).of(280.0),
    /// Which edge the panel slides from.
    edge: Atom(Edge) = Atom(Edge).of(.left),
    /// Whether to show a scrim behind the panel.
    show_scrim: Atom(bool) = Atom(bool).of(true),
    /// Panel background color.
    panel_color: Atom(Color) = Atom(Color).of(Color.fromRGB(0xFF, 0xFF, 0xFF)),

    _on_dismiss: ?*const fn () void = null,

    pub fn init(config: FlyoutPanel.Config) FlyoutPanel {
        var panel = FlyoutPanel.init_events(FlyoutPanel{});
        panel.panel_color.set(sys.secondaryBackground());
        internal.applyConfigStruct(&panel, config);
        panel.addDrawHandler(&FlyoutPanel.draw) catch unreachable;
        panel.addMouseButtonHandler(&FlyoutPanel.onMouseButton) catch unreachable;
        return panel;
    }

    pub fn onDismiss(self: *FlyoutPanel, callback: *const fn () void) *FlyoutPanel {
        self._on_dismiss = callback;
        return self;
    }

    pub fn getPreferredSize(self: *FlyoutPanel, available: Size) Size {
        _ = self;
        return available;
    }

    fn onMouseButton(self: *FlyoutPanel, button: MouseButton, pressed: bool, x: i32, _: i32) !void {
        if (button != .Left or !pressed or !self.open.get()) return;

        const ps: i32 = @intFromFloat(self.panel_size.get());
        const w: i32 = @intCast(self.getWidth());

        // Check if click is outside the panel (on scrim)
        const in_panel = switch (self.edge.get()) {
            .left => x < ps,
            .right => x >= (w - ps),
        };

        if (!in_panel) {
            self.open.set(false);
            if (self._on_dismiss) |cb| cb();
        }
    }

    pub fn draw(self: *FlyoutPanel, ctx: *backend.DrawContext) !void {
        if (!self.open.get()) return;

        const w = self.getWidth();
        const h = self.getHeight();
        const ps: u31 = @intFromFloat(self.panel_size.get());

        // Draw scrim
        if (self.show_scrim.get()) {
            ctx.setColorByte(sys.scrim());
            ctx.rectangle(0, 0, w, h);
            ctx.fill();
        }

        // Draw panel
        ctx.setColorByte(self.panel_color.get());
        switch (self.edge.get()) {
            .left => ctx.rectangle(0, 0, ps, h),
            .right => ctx.rectangle(@as(i32, @intCast(w)) - @as(i32, ps), 0, ps, h),
        }
        ctx.fill();

        // Draw shadow edge
        ctx.setColorByte(sys.shadow());
        switch (self.edge.get()) {
            .left => ctx.rectangle(@as(i32, ps), 0, 2, h),
            .right => ctx.rectangle(@as(i32, @intCast(w)) - @as(i32, ps) - 2, 0, 2, h),
        }
        ctx.fill();
    }

    pub fn show(self: *FlyoutPanel) !void {
        if (self.peer == null) {
            self.peer = try backend.Canvas.create();
            _ = try self.open.addChangeListener(.{ .function = struct {
                fn callback(_: bool, userdata: ?*anyopaque) void {
                    const ptr: *FlyoutPanel = @ptrCast(@alignCast(userdata.?));
                    ptr.peer.?.requestDraw() catch {};
                }
            }.callback, .userdata = self });
            try self.setupEvents();
        }
    }
};

pub fn flyoutPanel(config: FlyoutPanel.Config) *FlyoutPanel {
    return FlyoutPanel.alloc(config);
}

test "FlyoutPanel default properties" {
    try backend.init();
    const fp = flyoutPanel(.{});
    defer fp.deinit();

    try std.testing.expect(!fp.open.get());
    try std.testing.expectApproxEqAbs(@as(f32, 280.0), fp.panel_size.get(), 0.001);
    try std.testing.expectEqual(Edge.left, fp.edge.get());
    try std.testing.expect(fp.show_scrim.get());
    // Default panel_color is white
    const c = fp.panel_color.get();
    try std.testing.expectEqual(@as(u8, 0xFF), c.red);
    try std.testing.expectEqual(@as(u8, 0xFF), c.green);
    try std.testing.expectEqual(@as(u8, 0xFF), c.blue);
}

test "FlyoutPanel with custom config" {
    try backend.init();
    const fp = flyoutPanel(.{
        .open = true,
        .panel_size = 350.0,
        .edge = .right,
        .show_scrim = false,
    });
    defer fp.deinit();

    try std.testing.expect(fp.open.get());
    try std.testing.expectApproxEqAbs(@as(f32, 350.0), fp.panel_size.get(), 0.001);
    try std.testing.expectEqual(Edge.right, fp.edge.get());
    try std.testing.expect(!fp.show_scrim.get());
}

test FlyoutPanel {
    var panel = flyoutPanel(.{});
    panel.ref();
    defer panel.unref();
    try std.testing.expectEqual(false, panel.open.get());
    try std.testing.expectApproxEqAbs(@as(f32, 280.0), panel.panel_size.get(), 0.001);
}
