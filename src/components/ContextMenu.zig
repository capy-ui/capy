const std = @import("std");
const builtin = @import("builtin");
const backend = @import("../backend.zig");
const internal = @import("../internal.zig");
const Size = @import("../data.zig").Size;
const Atom = @import("../data.zig").Atom;
const Color = @import("../color.zig").Color;
const sys = @import("../system_colors.zig");
const MouseButton = @import("../backends/shared.zig").MouseButton;

/// A single context menu item.
pub const ContextMenuItem = struct {
    label: [:0]const u8,
    on_click: ?*const fn () void = null,
    enabled: bool = true,
    separator: bool = false,
};

/// A right-click context menu drawn as a canvas overlay at a specific position.
pub const ContextMenu = struct {
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
    widget_data: ContextMenu.WidgetData = .{},

    /// Whether the context menu is visible.
    visible: Atom(bool) = Atom(bool).of(false),
    /// X position of the menu.
    menu_x: Atom(i32) = Atom(i32).of(0),
    /// Y position of the menu.
    menu_y: Atom(i32) = Atom(i32).of(0),

    _items: []const ContextMenuItem = &.{},
    _hovered_item: ?usize = null,
    _on_dismiss: ?*const fn () void = null,

    const MENU_WIDTH: u31 = 180;
    const ITEM_HEIGHT: u31 = 28;
    const SEPARATOR_HEIGHT: u31 = 8;

    pub fn init(config: ContextMenu.Config) ContextMenu {
        var menu = ContextMenu.init_events(ContextMenu{});
        internal.applyConfigStruct(&menu, config);
        menu.addDrawHandler(&ContextMenu.draw) catch unreachable;
        menu.addMouseButtonHandler(&ContextMenu.onMouseButton) catch unreachable;
        menu.addMouseMotionHandler(&ContextMenu.onMouseMove) catch unreachable;
        return menu;
    }

    pub fn setItems(self: *ContextMenu, items: []const ContextMenuItem) *ContextMenu {
        self._items = items;
        return self;
    }

    pub fn onDismiss(self: *ContextMenu, callback: *const fn () void) *ContextMenu {
        self._on_dismiss = callback;
        return self;
    }

    /// Open the context menu at position (x, y).
    pub fn openAt(self: *ContextMenu, x: i32, y: i32) void {
        self.menu_x.set(x);
        self.menu_y.set(y);
        self.visible.set(true);
        self._hovered_item = null;
    }

    /// Close the context menu.
    pub fn close(self: *ContextMenu) void {
        self.visible.set(false);
        self._hovered_item = null;
    }

    pub fn getPreferredSize(self: *ContextMenu, available: Size) Size {
        _ = self;
        return available;
    }

    fn getMenuHeight(self: *ContextMenu) u31 {
        var h: u31 = 4; // padding
        for (self._items) |item| {
            h += if (item.separator) SEPARATOR_HEIGHT else ITEM_HEIGHT;
        }
        return h + 4; // padding
    }

    fn hitTestItem(self: *ContextMenu, x: i32, y: i32) ?usize {
        const mx = self.menu_x.get();
        const my = self.menu_y.get();

        if (x < mx or x >= mx + MENU_WIDTH) return null;

        var current_y: i32 = my + 4;
        for (self._items, 0..) |item, i| {
            const item_h: i32 = if (item.separator) SEPARATOR_HEIGHT else ITEM_HEIGHT;
            if (y >= current_y and y < current_y + item_h) {
                if (item.separator or !item.enabled) return null;
                return i;
            }
            current_y += item_h;
        }
        return null;
    }

    fn onMouseButton(self: *ContextMenu, button: MouseButton, pressed: bool, x: i32, y: i32) !void {
        if (button != .Left or !pressed or !self.visible.get()) return;

        if (self.hitTestItem(x, y)) |idx| {
            if (self._items[idx].on_click) |cb| cb();
            self.close();
        } else {
            // Click outside menu: dismiss
            self.close();
            if (self._on_dismiss) |cb| cb();
        }
    }

    fn onMouseMove(self: *ContextMenu, x: i32, y: i32) !void {
        if (!self.visible.get()) return;
        const new_hovered = self.hitTestItem(x, y);
        if (new_hovered != self._hovered_item) {
            self._hovered_item = new_hovered;
            self.peer.?.requestDraw() catch {};
        }
    }

    pub fn draw(self: *ContextMenu, ctx: *backend.DrawContext) !void {
        if (!self.visible.get()) return;

        const w = self.getWidth();
        const h = self.getHeight();
        const mx = self.menu_x.get();
        const my = self.menu_y.get();
        const menu_h = self.getMenuHeight();

        // Draw transparent scrim (catches clicks)
        ctx.setColorByte(Color.fromARGB(0x01, 0x00, 0x00, 0x00));
        ctx.rectangle(0, 0, w, h);
        ctx.fill();

        // Draw menu background with shadow
        ctx.setColorByte(sys.shadow());
        ctx.rectangle(mx + 2, my + 2, MENU_WIDTH, menu_h);
        ctx.fill();

        ctx.setColorByte(sys.background());
        if (builtin.os.tag == .windows) {
            ctx.rectangle(mx, my, MENU_WIDTH, menu_h);
        } else {
            ctx.roundedRectangleEx(mx, my, MENU_WIDTH, menu_h, [4]f32{ 4, 4, 4, 4 });
        }
        ctx.fill();

        // Draw border
        ctx.setColorByte(sys.controlBorder());
        if (builtin.os.tag == .windows) {
            ctx.rectangle(mx, my, MENU_WIDTH, menu_h);
        } else {
            ctx.roundedRectangleEx(mx, my, MENU_WIDTH, menu_h, [4]f32{ 4, 4, 4, 4 });
        }
        ctx.setStrokeWidth(1.0);
        ctx.stroke();

        var layout = backend.DrawContext.TextLayout.init();
        layout.setFont(.{ .face = "Helvetica", .size = 13.0 });

        var current_y: i32 = my + 4;
        for (self._items, 0..) |item, i| {
            if (item.separator) {
                ctx.setColorByte(sys.separator());
                ctx.rectangle(mx + 8, current_y + SEPARATOR_HEIGHT / 2, MENU_WIDTH - 16, 1);
                ctx.fill();
                current_y += SEPARATOR_HEIGHT;
                continue;
            }

            // Hover highlight
            if (self._hovered_item != null and self._hovered_item.? == i and item.enabled) {
                ctx.setColorByte(sys.hoverBackground());
                ctx.rectangle(mx + 2, current_y, MENU_WIDTH - 4, ITEM_HEIGHT);
                ctx.fill();
            }

            // Item text
            const text_color = if (item.enabled) sys.label() else sys.tertiaryLabel();
            ctx.setColorByte(text_color);
            const text_size = layout.getTextSize(item.label);
            ctx.text(mx + 12, current_y + @as(i32, ITEM_HEIGHT / 2) - @as(i32, @intCast(text_size.height / 2)), layout, item.label);

            current_y += ITEM_HEIGHT;
        }
    }

    pub fn show(self: *ContextMenu) !void {
        if (self.peer == null) {
            self.peer = try backend.Canvas.create();
            _ = try self.visible.addChangeListener(.{ .function = struct {
                fn callback(_: bool, userdata: ?*anyopaque) void {
                    const ptr: *ContextMenu = @ptrCast(@alignCast(userdata.?));
                    ptr.peer.?.requestDraw() catch {};
                }
            }.callback, .userdata = self });
            try self.setupEvents();
        }
    }
};

pub fn contextMenu(config: ContextMenu.Config) *ContextMenu {
    return ContextMenu.alloc(config);
}

test "ContextMenu default properties" {
    try backend.init();
    var cm = contextMenu(.{});
    defer cm.deinit();

    try std.testing.expect(!cm.visible.get());
    try std.testing.expectEqual(@as(i32, 0), cm.menu_x.get());
    try std.testing.expectEqual(@as(i32, 0), cm.menu_y.get());
    try std.testing.expectEqual(@as(usize, 0), cm._items.len);
    try std.testing.expectEqual(@as(?usize, null), cm._hovered_item);
}

test "ContextMenu setItems" {
    try backend.init();
    var cm = contextMenu(.{});
    defer cm.deinit();

    _ = cm.setItems(&.{
        .{ .label = "Cut", .on_click = null },
        .{ .label = "", .separator = true },
        .{ .label = "Paste", .on_click = null },
    });
    try std.testing.expectEqual(@as(usize, 3), cm._items.len);
    try std.testing.expectEqualStrings("Cut", cm._items[0].label);
    try std.testing.expect(cm._items[1].separator);
    try std.testing.expectEqualStrings("Paste", cm._items[2].label);
}

test "ContextMenu openAt sets position and visibility" {
    try backend.init();
    var cm = contextMenu(.{});
    defer cm.deinit();

    _ = cm.openAt(100, 200);
    try std.testing.expectEqual(@as(i32, 100), cm.menu_x.get());
    try std.testing.expectEqual(@as(i32, 200), cm.menu_y.get());
    try std.testing.expect(cm.visible.get());
}

test "ContextMenu close resets visibility" {
    try backend.init();
    var cm = contextMenu(.{});
    defer cm.deinit();

    _ = cm.openAt(50, 60);
    try std.testing.expect(cm.visible.get());

    _ = cm.close();
    try std.testing.expect(!cm.visible.get());
}

test ContextMenu {
    var menu = contextMenu(.{});
    menu.ref();
    defer menu.unref();
    try std.testing.expectEqual(false, menu.visible.get());
}
