const std = @import("std");
const backend = @import("../backend.zig");
const Size = @import("../data.zig").Size;
const Atom = @import("../data.zig").Atom;
const Color = @import("../color.zig").Color;
const sys = @import("../system_colors.zig");
const Timer = @import("../timer.zig").Timer;

/// An indeterminate animated loading spinner. Draws rotating dots in a circle.
pub const Spinner = struct {
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
    widget_data: Spinner.WidgetData = .{},

    /// Whether the spinner is animating.
    active: Atom(bool) = Atom(bool).of(true),
    /// Color of the spinner dots.
    color: Atom(Color) = Atom(Color).of(Color.fromRGB(0x33, 0x7A, 0xB7)),
    /// Number of dots in the spinner.
    num_dots: Atom(u8) = Atom(u8).of(10),

    _angle: f32 = 0.0,
    _timer: ?*Timer = null,

    const NUM_DOTS_DEFAULT = 10;

    pub fn init(config: Spinner.Config) Spinner {
        var self_init = Spinner.init_events(Spinner{});
        self_init.color.set(sys.label());
        @import("../internal.zig").applyConfigStruct(&self_init, config);
        self_init.addDrawHandler(&Spinner.draw) catch unreachable;
        return self_init;
    }

    pub fn getPreferredSize(self: *Spinner, available: Size) Size {
        _ = self;
        return available.intersect(Size.init(32, 32));
    }

    pub fn draw(self: *Spinner, ctx: *backend.DrawContext) !void {
        if (!self.active.get()) return;

        const w: f32 = @floatFromInt(self.getWidth());
        const h: f32 = @floatFromInt(self.getHeight());
        const cx = w / 2.0;
        const cy = h / 2.0;
        const radius = @min(cx, cy) * 0.7;
        const dot_r = @min(cx, cy) * 0.12;

        const base_color = self.color.get();
        const n = self.num_dots.get();

        var i: u8 = 0;
        while (i < n) : (i += 1) {
            const angle = self._angle + @as(f32, @floatFromInt(i)) * (2.0 * std.math.pi / @as(f32, @floatFromInt(n)));
            const dx = cx + radius * @cos(angle);
            const dy = cy + radius * @sin(angle);

            // Opacity fades from full to dim based on position
            const alpha_frac = 1.0 - @as(f32, @floatFromInt(i)) / @as(f32, @floatFromInt(n));
            const alpha: u8 = @intFromFloat(alpha_frac * @as(f32, @floatFromInt(base_color.alpha)));

            ctx.setColorByte(Color.fromARGB(alpha, base_color.red, base_color.green, base_color.blue));

            // Draw dot as small ellipse
            const dot_size: u31 = @max(2, @as(u31, @intFromFloat(dot_r * 2.0)));
            const ex: i32 = @intFromFloat(dx - dot_r);
            const ey: i32 = @intFromFloat(dy - dot_r);
            ctx.ellipse(ex, ey, dot_size, dot_size);
            ctx.fill();
        }
    }

    pub fn show(self: *Spinner) !void {
        if (self.peer == null) {
            self.peer = try backend.Canvas.create();

            // Start animation timer (~60fps)
            self._timer = try Timer.init(.{
                .single_shot = false,
                .duration = 16 * std.time.ns_per_ms,
            });
            _ = try self._timer.?.event_source.listen(.{
                .callback = struct {
                    fn callback(userdata: ?*anyopaque) void {
                        const ptr: *Spinner = @ptrCast(@alignCast(userdata.?));
                        if (!ptr.active.get()) return;
                        ptr._angle += 0.15;
                        if (ptr._angle > 2.0 * std.math.pi) {
                            ptr._angle -= 2.0 * std.math.pi;
                        }
                        ptr.peer.?.requestDraw() catch {};
                    }
                }.callback,
                .userdata = self,
            });
            try self._timer.?.start();

            try self.setupEvents();
        }
    }

    pub fn _deinit(self: *Spinner) void {
        if (self._timer) |timer| {
            timer.stop();
        }
    }
};

pub fn spinner(config: Spinner.Config) *Spinner {
    return Spinner.alloc(config);
}

test "Spinner default properties" {
    try backend.init();
    const s = Spinner.alloc(.{});
    defer s.deinit();

    try std.testing.expect(s.active.get());
    try std.testing.expectEqual(@as(u8, 10), s.num_dots.get());
    try std.testing.expectApproxEqAbs(@as(f32, 0.0), s._angle, 0.001);
    try std.testing.expectEqual(@as(?*Timer, null), s._timer);
}

test "Spinner initially inactive" {
    try backend.init();
    const s = Spinner.alloc(.{ .active = false });
    defer s.deinit();

    try std.testing.expect(!s.active.get());
}

test Spinner {
    var s1 = spinner(.{});
    s1.ref();
    defer s1.unref();
    try std.testing.expectEqual(true, s1.active.get());

    var s2 = spinner(.{ .active = false });
    s2.ref();
    defer s2.unref();
    try std.testing.expectEqual(false, s2.active.get());
}
