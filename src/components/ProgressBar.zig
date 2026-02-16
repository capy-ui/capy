const std = @import("std");
const builtin = @import("builtin");
const backend = @import("../backend.zig");
const internal = @import("../internal.zig");
const Size = @import("../data.zig").Size;
const Atom = @import("../data.zig").Atom;
const Color = @import("../color.zig").Color;
const sys = @import("../system_colors.zig");

const has_native = backend.ProgressBar != void;
const ProgressBarPeer = if (has_native) backend.ProgressBar else backend.Canvas;

/// A determinate horizontal progress bar displaying a value from 0.0 to 1.0.
pub const ProgressBar = struct {
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

    peer: ?ProgressBarPeer = null,
    widget_data: ProgressBar.WidgetData = .{},

    /// Progress value from 0.0 (empty) to 1.0 (full). Animatable via Atom.animate().
    value: Atom(f32) = Atom(f32).of(0.0),
    /// Background track color.
    track_color: Atom(Color) = Atom(Color).of(Color.fromRGB(0xE0, 0xE0, 0xE0)),
    /// Filled portion color.
    fill_color: Atom(Color) = Atom(Color).of(Color.fromRGB(0x33, 0x7A, 0xB7)),
    /// Corner radius for both track and fill.
    corner_radius: Atom(f32) = Atom(f32).of(4.0),

    pub fn init(config: ProgressBar.Config) ProgressBar {
        var bar = ProgressBar.init_events(ProgressBar{});
        if (!has_native) {
            bar.track_color.set(sys.trackBackground());
            bar.fill_color.set(sys.accent());
        }
        internal.applyConfigStruct(&bar, config);
        if (!has_native) {
            bar.addDrawHandler(&ProgressBar.draw) catch unreachable;
        }
        return bar;
    }

    pub fn getPreferredSize(self: *ProgressBar, available: Size) Size {
        _ = self;
        return available.intersect(Size.init(200, 20));
    }

    pub fn draw(self: *ProgressBar, ctx: *backend.DrawContext) !void {
        const w = self.getWidth();
        const h = self.getHeight();
        const cr = self.corner_radius.get();
        const radii = [4]f32{ cr, cr, cr, cr };

        // Draw track
        ctx.setColorByte(self.track_color.get());
        if (builtin.os.tag == .windows) {
            ctx.rectangle(0, 0, w, h);
        } else {
            ctx.roundedRectangleEx(0, 0, w, h, radii);
        }
        ctx.fill();

        // Draw fill
        const progress = std.math.clamp(self.value.get(), 0.0, 1.0);
        const fill_w: u31 = @intFromFloat(@as(f32, @floatFromInt(w)) * progress);
        if (fill_w > 0) {
            ctx.setColorByte(self.fill_color.get());
            if (builtin.os.tag == .windows) {
                ctx.rectangle(0, 0, fill_w, h);
            } else {
                ctx.roundedRectangleEx(0, 0, fill_w, h, radii);
            }
            ctx.fill();
        }
    }

    pub fn show(self: *ProgressBar) !void {
        if (self.peer == null) {
            if (comptime has_native) {
                var peer = try backend.ProgressBar.create();
                peer.setValue(self.value.get());
                self.peer = peer;
                _ = try self.value.addChangeListener(.{ .function = struct {
                    fn callback(new_val: f32, userdata: ?*anyopaque) void {
                        const ptr: *ProgressBar = @ptrCast(@alignCast(userdata.?));
                        if (ptr.peer) |*p| p.setValue(new_val);
                    }
                }.callback, .userdata = self });
            } else {
                self.peer = try backend.Canvas.create();
                _ = try self.value.addChangeListener(.{ .function = struct {
                    fn callback(_: f32, userdata: ?*anyopaque) void {
                        const ptr: *ProgressBar = @ptrCast(@alignCast(userdata.?));
                        ptr.peer.?.requestDraw() catch {};
                    }
                }.callback, .userdata = self });
                _ = try self.track_color.addChangeListener(.{ .function = struct {
                    fn callback(_: Color, userdata: ?*anyopaque) void {
                        const ptr: *ProgressBar = @ptrCast(@alignCast(userdata.?));
                        ptr.peer.?.requestDraw() catch {};
                    }
                }.callback, .userdata = self });
                _ = try self.fill_color.addChangeListener(.{ .function = struct {
                    fn callback(_: Color, userdata: ?*anyopaque) void {
                        const ptr: *ProgressBar = @ptrCast(@alignCast(userdata.?));
                        ptr.peer.?.requestDraw() catch {};
                    }
                }.callback, .userdata = self });
            }
            try self.setupEvents();
        }
    }
};

pub fn progressBar(config: ProgressBar.Config) *ProgressBar {
    return ProgressBar.alloc(config);
}

test "ProgressBar default properties" {
    try backend.init();
    const p = ProgressBar.alloc(.{});
    defer p.deinit();

    try std.testing.expectApproxEqAbs(@as(f32, 0.0), p.value.get(), 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 4.0), p.corner_radius.get(), 0.001);
}

test "ProgressBar with custom value" {
    try backend.init();
    const p = ProgressBar.alloc(.{ .value = 0.75 });
    defer p.deinit();

    try std.testing.expectApproxEqAbs(@as(f32, 0.75), p.value.get(), 0.001);
}

test "ProgressBar value clamped in draw" {
    try backend.init();
    const p = ProgressBar.alloc(.{ .value = 1.5 });
    defer p.deinit();

    // Value is stored as-is; clamping happens during draw
    try std.testing.expectApproxEqAbs(@as(f32, 1.5), p.value.get(), 0.001);
}

test ProgressBar {
    var bar1 = progressBar(.{});
    bar1.ref();
    defer bar1.unref();
    try std.testing.expectApproxEqAbs(@as(f32, 0.0), bar1.value.get(), 0.001);

    var bar2 = progressBar(.{ .value = 0.75 });
    bar2.ref();
    defer bar2.unref();
    try std.testing.expectApproxEqAbs(@as(f32, 0.75), bar2.value.get(), 0.001);
}
