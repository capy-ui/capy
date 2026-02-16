const std = @import("std");
const builtin = @import("builtin");
const backend = @import("../backend.zig");
const internal = @import("../internal.zig");
const Size = @import("../data.zig").Size;
const Atom = @import("../data.zig").Atom;
const ListAtom = @import("../data.zig").ListAtom;
const Color = @import("../color.zig").Color;
const sys = @import("../system_colors.zig");
const MouseButton = @import("../backends/shared.zig").MouseButton;

/// A row of mutually exclusive toggle segments (like iOS segmented picker).
pub const SegmentedControl = struct {
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
    widget_data: SegmentedControl.WidgetData = .{},

    /// The labels for each segment. Required.
    labels: ListAtom([:0]const u8),
    /// Index of the currently selected segment.
    selected: Atom(usize) = Atom(usize).of(0),
    /// Background color for the control track.
    bg_color: Atom(Color) = Atom(Color).of(Color.fromRGB(0xE8, 0xE8, 0xE8)),
    /// Color of the selected segment.
    selected_color: Atom(Color) = Atom(Color).of(Color.fromRGB(0xFF, 0xFF, 0xFF)),
    /// Text color.
    text_color: Atom(Color) = Atom(Color).of(Color.fromRGB(0x33, 0x33, 0x33)),
    /// Corner radius of the overall control.
    corner_radius: Atom(f32) = Atom(f32).of(6.0),

    _hovered: ?usize = null,

    pub fn init(config: SegmentedControl.Config) SegmentedControl {
        var seg = SegmentedControl.init_events(SegmentedControl{
            .labels = ListAtom([:0]const u8).init(internal.allocator),
        });
        seg.bg_color.set(sys.controlBackground());
        seg.selected_color.set(sys.controlAccentBackground());
        seg.text_color.set(sys.label());
        internal.applyConfigStruct(&seg, config);
        seg.addDrawHandler(&SegmentedControl.draw) catch unreachable;
        seg.addMouseButtonHandler(&SegmentedControl.onMouseButton) catch unreachable;
        seg.addMouseMotionHandler(&SegmentedControl.onMouseMove) catch unreachable;
        return seg;
    }

    pub fn getPreferredSize(self: *SegmentedControl, available: Size) Size {
        const num = self.labels.length.get();
        return available.intersect(Size.init(@as(f32, @floatFromInt(num * 80)), 32));
    }

    fn hitTestSegment(self: *SegmentedControl, x: i32) ?usize {
        const num = self.labels.length.get();
        if (num == 0) return null;
        const w: f32 = @floatFromInt(self.getWidth());
        const seg_w = w / @as(f32, @floatFromInt(num));
        const idx: usize = @intFromFloat(@as(f32, @floatFromInt(x)) / seg_w);
        return if (idx < num) idx else null;
    }

    fn onMouseButton(self: *SegmentedControl, button: MouseButton, pressed: bool, x: i32, _: i32) !void {
        if (button == .Left and pressed) {
            if (self.hitTestSegment(x)) |idx| {
                self.selected.set(idx);
                self.peer.?.requestDraw() catch {};
            }
        }
    }

    fn onMouseMove(self: *SegmentedControl, x: i32, _: i32) !void {
        const new_hovered = self.hitTestSegment(x);
        if (new_hovered != self._hovered) {
            self._hovered = new_hovered;
            self.peer.?.requestDraw() catch {};
        }
    }

    pub fn draw(self: *SegmentedControl, ctx: *backend.DrawContext) !void {
        const w = self.getWidth();
        const h = self.getHeight();
        const num = self.labels.length.get();
        if (num == 0) return;

        const cr = self.corner_radius.get();
        const radii = [4]f32{ cr, cr, cr, cr };

        // Draw background track
        ctx.setColorByte(self.bg_color.get());
        if (builtin.os.tag == .windows) {
            ctx.rectangle(0, 0, w, h);
        } else {
            ctx.roundedRectangleEx(0, 0, w, h, radii);
        }
        ctx.fill();

        const w_f: f32 = @floatFromInt(w);
        const seg_w = w_f / @as(f32, @floatFromInt(num));
        const selected_idx = self.selected.get();

        // Draw segments
        var layout = backend.DrawContext.TextLayout.init();
        layout.setFont(.{ .face = "Helvetica", .size = 13.0 });

        var iter = self.labels.iterate();
        defer iter.deinit();
        const items = iter.getSlice();

        for (items, 0..) |label, i| {
            const seg_x: i32 = @intFromFloat(@as(f32, @floatFromInt(i)) * seg_w);
            const seg_end: i32 = @intFromFloat(@as(f32, @floatFromInt(i + 1)) * seg_w);
            const seg_width: u31 = @intCast(@max(1, seg_end - seg_x));

            // Draw selected/hovered background
            if (i == selected_idx) {
                ctx.setColorByte(self.selected_color.get());
                if (builtin.os.tag == .windows) {
                    ctx.rectangle(seg_x + 2, 2, @max(1, seg_width -| 4), @max(1, h -| 4));
                } else {
                    ctx.roundedRectangleEx(seg_x + 2, 2, @max(1, seg_width -| 4), @max(1, h -| 4), [4]f32{ cr - 1, cr - 1, cr - 1, cr - 1 });
                }
                ctx.fill();
            } else if (self._hovered != null and self._hovered.? == i) {
                ctx.setColorByte(sys.hoverBackground());
                ctx.rectangle(seg_x + 2, 2, @max(1, seg_width -| 4), @max(1, h -| 4));
                ctx.fill();
            }

            // Draw separator (skip first and adjacent to selected)
            if (i > 0 and i != selected_idx and (selected_idx == 0 or i != selected_idx)) {
                ctx.setColorByte(Color.fromARGB(0x40, 0x00, 0x00, 0x00));
                ctx.rectangle(seg_x, 4, 1, @max(1, h -| 8));
                ctx.fill();
            }

            // Draw label text centered in segment
            const text_size = layout.getTextSize(label);
            const text_x = seg_x + @as(i32, @intCast(seg_width / 2)) - @as(i32, @intCast(text_size.width / 2));
            const text_y = @as(i32, @intCast(h / 2)) - @as(i32, @intCast(text_size.height / 2));
            ctx.setColorByte(self.text_color.get());
            ctx.text(text_x, text_y, layout, label);
        }
    }

    pub fn _deinit(self: *SegmentedControl) void {
        self.labels.deinit();
    }

    pub fn show(self: *SegmentedControl) !void {
        if (self.peer == null) {
            self.peer = try backend.Canvas.create();
            _ = try self.selected.addChangeListener(.{ .function = struct {
                fn callback(_: usize, userdata: ?*anyopaque) void {
                    const ptr: *SegmentedControl = @ptrCast(@alignCast(userdata.?));
                    ptr.peer.?.requestDraw() catch {};
                }
            }.callback, .userdata = self });
            try self.setupEvents();
        }
    }
};

pub fn segmentedControl(config: SegmentedControl.Config) *SegmentedControl {
    return SegmentedControl.alloc(config);
}

test "SegmentedControl default properties" {
    try backend.init();
    const sc = segmentedControl(.{ .labels = &.{ "A", "B", "C" } });
    defer sc.deinit();

    try std.testing.expectEqual(@as(usize, 0), sc.selected.get());
    try std.testing.expectEqual(@as(usize, 3), sc.labels.length.get());
    try std.testing.expectApproxEqAbs(@as(f32, 6.0), sc.corner_radius.get(), 0.001);
    try std.testing.expectEqual(@as(?usize, null), sc._hovered);
}

test "SegmentedControl with custom selected" {
    try backend.init();
    const sc = segmentedControl(.{ .labels = &.{ "X", "Y" }, .selected = 1 });
    defer sc.deinit();

    try std.testing.expectEqual(@as(usize, 1), sc.selected.get());
    try std.testing.expectEqual(@as(usize, 2), sc.labels.length.get());
}

test "SegmentedControl label contents" {
    try backend.init();
    const sc = segmentedControl(.{ .labels = &.{ "Day", "Week", "Month" } });
    defer sc.deinit();

    var iter = sc.labels.iterate();
    defer iter.deinit();
    const items = iter.getSlice();
    try std.testing.expectEqualStrings("Day", items[0]);
    try std.testing.expectEqualStrings("Week", items[1]);
    try std.testing.expectEqualStrings("Month", items[2]);
}

test SegmentedControl {
    var seg = segmentedControl(.{ .labels = &.{ "One", "Two", "Three" } });
    seg.ref();
    defer seg.unref();
    try std.testing.expectEqual(@as(usize, 0), seg.selected.get());
    try std.testing.expectEqual(@as(usize, 3), seg.labels.length.get());
}
