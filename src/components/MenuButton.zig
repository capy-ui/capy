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

/// A button that displays a dropdown list of options when clicked.
pub const MenuButton = struct {
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
    widget_data: MenuButton.WidgetData = .{},

    /// Button label text.
    label: Atom([:0]const u8) = Atom([:0]const u8).of("Select..."),
    /// The dropdown item labels. Required.
    items: ListAtom([:0]const u8),
    /// The index of the currently selected item, or null if none.
    selected_index: Atom(?usize) = Atom(?usize).of(null),
    /// Background color of the button.
    bg_color: Atom(Color) = Atom(Color).of(Color.fromRGB(0xFF, 0xFF, 0xFF)),
    /// Border color.
    border_color: Atom(Color) = Atom(Color).of(Color.fromRGB(0xCC, 0xCC, 0xCC)),
    /// Text color.
    text_color: Atom(Color) = Atom(Color).of(Color.fromRGB(0x33, 0x33, 0x33)),
    /// Corner radius.
    corner_radius: Atom(f32) = Atom(f32).of(4.0),

    _open: bool = false,
    _hovered_item: ?usize = null,

    const BUTTON_HEIGHT: u31 = 32;
    const ITEM_HEIGHT: u31 = 28;

    pub fn init(config: MenuButton.Config) MenuButton {
        var btn = MenuButton.init_events(MenuButton{
            .items = ListAtom([:0]const u8).init(internal.allocator),
        });
        btn.bg_color.set(sys.background());
        btn.border_color.set(sys.controlBorder());
        btn.text_color.set(sys.label());
        internal.applyConfigStruct(&btn, config);
        btn.addDrawHandler(&MenuButton.draw) catch unreachable;
        btn.addMouseButtonHandler(&MenuButton.onMouseButton) catch unreachable;
        btn.addMouseMotionHandler(&MenuButton.onMouseMove) catch unreachable;
        return btn;
    }

    pub fn getPreferredSize(self: *MenuButton, available: Size) Size {
        if (self._open) {
            const num_items: u31 = @intCast(self.items.length.get());
            const dropdown_h: u31 = num_items * ITEM_HEIGHT;
            return available.intersect(Size.init(160, @as(f32, @floatFromInt(BUTTON_HEIGHT + dropdown_h + 2))));
        }
        return available.intersect(Size.init(160, @as(f32, @floatFromInt(BUTTON_HEIGHT))));
    }

    fn onMouseButton(self: *MenuButton, button: MouseButton, pressed: bool, _: i32, y: i32) !void {
        if (button != .Left or !pressed) return;

        if (y < BUTTON_HEIGHT) {
            // Click on button area: toggle dropdown
            self._open = !self._open;
            self._hovered_item = null;
            self.peer.?.requestDraw() catch {};
        } else if (self._open) {
            // Click on dropdown area
            const item_y = y - BUTTON_HEIGHT;
            const idx: usize = @intCast(@divFloor(item_y, ITEM_HEIGHT));
            if (idx < self.items.length.get()) {
                self.selected_index.set(idx);
                // Update label to selected item
                self.label.set(self.items.get(idx));
                self._open = false;
                self.peer.?.requestDraw() catch {};
            }
        }
    }

    fn onMouseMove(self: *MenuButton, _: i32, y: i32) !void {
        if (!self._open) return;
        if (y >= BUTTON_HEIGHT) {
            const item_y = y - BUTTON_HEIGHT;
            const idx: usize = @intCast(@divFloor(item_y, ITEM_HEIGHT));
            const new_hover: ?usize = if (idx < self.items.length.get()) idx else null;
            if (new_hover != self._hovered_item) {
                self._hovered_item = new_hover;
                self.peer.?.requestDraw() catch {};
            }
        } else {
            if (self._hovered_item != null) {
                self._hovered_item = null;
                self.peer.?.requestDraw() catch {};
            }
        }
    }

    pub fn draw(self: *MenuButton, ctx: *backend.DrawContext) !void {
        const w = self.getWidth();
        const cr = self.corner_radius.get();

        var layout = backend.DrawContext.TextLayout.init();
        layout.setFont(.{ .face = "Helvetica", .size = 13.0 });

        // Draw button background
        ctx.setColorByte(self.bg_color.get());
        if (builtin.os.tag == .windows) {
            ctx.rectangle(0, 0, w, BUTTON_HEIGHT);
        } else {
            ctx.roundedRectangleEx(0, 0, w, BUTTON_HEIGHT, [4]f32{ cr, cr, cr, cr });
        }
        ctx.fill();

        // Draw button border
        ctx.setColorByte(self.border_color.get());
        if (builtin.os.tag == .windows) {
            ctx.rectangle(0, 0, w, BUTTON_HEIGHT);
        } else {
            ctx.roundedRectangleEx(0, 0, w, BUTTON_HEIGHT, [4]f32{ cr, cr, cr, cr });
        }
        ctx.setStrokeWidth(1.0);
        ctx.stroke();

        // Draw button label
        const lbl = self.label.get();
        const text_size = layout.getTextSize(lbl);
        ctx.setColorByte(self.text_color.get());
        ctx.text(8, @as(i32, BUTTON_HEIGHT / 2) - @as(i32, @intCast(text_size.height / 2)), layout, lbl);

        // Draw chevron (down arrow triangle)
        const chev_x: i32 = @as(i32, @intCast(w)) - 20;
        const chev_y: i32 = BUTTON_HEIGHT / 2 - 3;
        ctx.setColorByte(self.text_color.get());
        ctx.line(chev_x, chev_y, chev_x + 5, chev_y + 5);
        ctx.line(chev_x + 5, chev_y + 5, chev_x + 10, chev_y);

        // Draw dropdown if open
        if (self._open) {
            const num_items = self.items.length.get();
            const dropdown_h: u31 = @intCast(num_items * ITEM_HEIGHT);

            // Dropdown background
            ctx.setColorByte(sys.background());
            ctx.rectangle(0, BUTTON_HEIGHT + 1, w, dropdown_h);
            ctx.fill();

            // Dropdown border
            ctx.setColorByte(self.border_color.get());
            ctx.rectangle(0, BUTTON_HEIGHT + 1, w, dropdown_h);
            ctx.setStrokeWidth(1.0);
            ctx.stroke();

            // Draw items
            var iter = self.items.iterate();
            defer iter.deinit();
            const items_slice = iter.getSlice();

            for (items_slice, 0..) |item, i| {
                const iy: i32 = @as(i32, BUTTON_HEIGHT + 1) + @as(i32, @intCast(i * ITEM_HEIGHT));

                // Highlight hovered item
                if (self._hovered_item != null and self._hovered_item.? == i) {
                    ctx.setColorByte(sys.hoverBackground());
                    ctx.rectangle(1, iy, @max(1, w -| 2), ITEM_HEIGHT);
                    ctx.fill();
                }

                // Draw item text
                ctx.setColorByte(self.text_color.get());
                const item_text_size = layout.getTextSize(item);
                ctx.text(8, iy + @as(i32, ITEM_HEIGHT / 2) - @as(i32, @intCast(item_text_size.height / 2)), layout, item);
            }
        }
    }

    pub fn _deinit(self: *MenuButton) void {
        self.items.deinit();
    }

    pub fn show(self: *MenuButton) !void {
        if (self.peer == null) {
            self.peer = try backend.Canvas.create();
            _ = try self.selected_index.addChangeListener(.{ .function = struct {
                fn callback(_: ?usize, userdata: ?*anyopaque) void {
                    const ptr: *MenuButton = @ptrCast(@alignCast(userdata.?));
                    ptr.peer.?.requestDraw() catch {};
                }
            }.callback, .userdata = self });
            _ = try self.label.addChangeListener(.{ .function = struct {
                fn callback(_: [:0]const u8, userdata: ?*anyopaque) void {
                    const ptr: *MenuButton = @ptrCast(@alignCast(userdata.?));
                    ptr.peer.?.requestDraw() catch {};
                }
            }.callback, .userdata = self });
            try self.setupEvents();
        }
    }
};

pub fn menuButton(config: MenuButton.Config) *MenuButton {
    return MenuButton.alloc(config);
}

test "MenuButton default properties" {
    try backend.init();
    const mb = menuButton(.{ .items = &.{ "PDF", "CSV", "JSON" } });
    defer mb.deinit();

    try std.testing.expectEqualStrings("Select...", mb.label.get());
    try std.testing.expectEqual(@as(?usize, null), mb.selected_index.get());
    try std.testing.expectEqual(@as(usize, 3), mb.items.length.get());
    try std.testing.expectApproxEqAbs(@as(f32, 4.0), mb.corner_radius.get(), 0.001);
    try std.testing.expect(!mb._open);
    try std.testing.expectEqual(@as(?usize, null), mb._hovered_item);
}

test "MenuButton item contents" {
    try backend.init();
    const mb = menuButton(.{ .items = &.{ "Alpha", "Beta" } });
    defer mb.deinit();

    var iter = mb.items.iterate();
    defer iter.deinit();
    const items = iter.getSlice();
    try std.testing.expectEqualStrings("Alpha", items[0]);
    try std.testing.expectEqualStrings("Beta", items[1]);
}

test "MenuButton with custom label" {
    try backend.init();
    const mb = menuButton(.{ .items = &.{"One"}, .label = "Choose..." });
    defer mb.deinit();

    try std.testing.expectEqualStrings("Choose...", mb.label.get());
}

test MenuButton {
    var btn = menuButton(.{ .items = &.{ "Apple", "Banana", "Cherry" } });
    btn.ref();
    defer btn.unref();
    try std.testing.expectEqual(@as(?usize, null), btn.selected_index.get());
    try std.testing.expectEqual(@as(usize, 3), btn.items.length.get());
}
