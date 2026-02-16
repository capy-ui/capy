const std = @import("std");
const builtin = @import("builtin");
const backend = @import("../backend.zig");
const internal = @import("../internal.zig");
const Size = @import("../data.zig").Size;
const Atom = @import("../data.zig").Atom;
const Color = @import("../color.zig").Color;
const sys = @import("../system_colors.zig");
const MouseButton = @import("../backends/shared.zig").MouseButton;

/// A modal alert dialog drawn as a canvas overlay.
/// Shows a title, message, and one or more action buttons.
pub const AlertDialog = struct {
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
    widget_data: AlertDialog.WidgetData = .{},

    /// Dialog title text.
    title: Atom([:0]const u8) = Atom([:0]const u8).of("Alert"),
    /// Dialog message body.
    message: Atom([:0]const u8) = Atom([:0]const u8).of(""),
    /// Primary button label.
    primary_label: Atom([:0]const u8) = Atom([:0]const u8).of("OK"),
    /// Secondary button label. Empty string hides the button.
    secondary_label: Atom([:0]const u8) = Atom([:0]const u8).of(""),
    /// Whether the dialog is visible.
    visible: Atom(bool) = Atom(bool).of(true),

    _hovered_button: ?u8 = null,
    _on_primary: ?*const fn () void = null,
    _on_secondary: ?*const fn () void = null,

    const DIALOG_WIDTH: u31 = 320;
    const DIALOG_HEIGHT: u31 = 180;
    const BUTTON_WIDTH: u31 = 80;
    const BUTTON_HEIGHT: u31 = 32;

    pub fn init(config: AlertDialog.Config) AlertDialog {
        var dlg = AlertDialog.init_events(AlertDialog{});
        internal.applyConfigStruct(&dlg, config);
        dlg.addDrawHandler(&AlertDialog.draw) catch unreachable;
        dlg.addMouseButtonHandler(&AlertDialog.onMouseButton) catch unreachable;
        dlg.addMouseMotionHandler(&AlertDialog.onMouseMove) catch unreachable;
        return dlg;
    }

    pub fn onPrimary(self: *AlertDialog, callback: *const fn () void) *AlertDialog {
        self._on_primary = callback;
        return self;
    }

    pub fn onSecondary(self: *AlertDialog, callback: *const fn () void) *AlertDialog {
        self._on_secondary = callback;
        return self;
    }

    pub fn getPreferredSize(self: *AlertDialog, available: Size) Size {
        _ = self;
        return available;
    }

    fn getDialogRect(self: *AlertDialog) struct { x: i32, y: i32, w: u31, h: u31 } {
        const total_w: i32 = @intCast(self.getWidth());
        const total_h: i32 = @intCast(self.getHeight());
        return .{
            .x = @divFloor(total_w - DIALOG_WIDTH, 2),
            .y = @divFloor(total_h - DIALOG_HEIGHT, 2),
            .w = DIALOG_WIDTH,
            .h = DIALOG_HEIGHT,
        };
    }

    fn onMouseButton(self: *AlertDialog, button: MouseButton, pressed: bool, x: i32, y: i32) !void {
        if (button != .Left or !pressed or !self.visible.get()) return;

        const dlg = self.getDialogRect();
        const has_secondary = self.secondary_label.get().len > 0;

        // Primary button
        const pri_x = if (has_secondary) dlg.x + @as(i32, DIALOG_WIDTH) - BUTTON_WIDTH * 2 - 16 else dlg.x + @as(i32, DIALOG_WIDTH) - BUTTON_WIDTH - 8;
        const btn_y = dlg.y + @as(i32, DIALOG_HEIGHT) - BUTTON_HEIGHT - 12;

        if (x >= pri_x and x < pri_x + BUTTON_WIDTH and y >= btn_y and y < btn_y + BUTTON_HEIGHT) {
            if (self._on_primary) |cb| cb();
            self.visible.set(false);
            return;
        }

        // Secondary button
        if (has_secondary) {
            const sec_x = dlg.x + @as(i32, DIALOG_WIDTH) - BUTTON_WIDTH - 8;
            if (x >= sec_x and x < sec_x + BUTTON_WIDTH and y >= btn_y and y < btn_y + BUTTON_HEIGHT) {
                if (self._on_secondary) |cb| cb();
                self.visible.set(false);
                return;
            }
        }
    }

    fn onMouseMove(self: *AlertDialog, x: i32, y: i32) !void {
        if (!self.visible.get()) return;
        const dlg = self.getDialogRect();
        const btn_y = dlg.y + @as(i32, DIALOG_HEIGHT) - BUTTON_HEIGHT - 12;
        const has_secondary = self.secondary_label.get().len > 0;

        var new_hovered: ?u8 = null;

        const pri_x = if (has_secondary) dlg.x + @as(i32, DIALOG_WIDTH) - BUTTON_WIDTH * 2 - 16 else dlg.x + @as(i32, DIALOG_WIDTH) - BUTTON_WIDTH - 8;
        if (x >= pri_x and x < pri_x + BUTTON_WIDTH and y >= btn_y and y < btn_y + BUTTON_HEIGHT) {
            new_hovered = 0;
        } else if (has_secondary) {
            const sec_x = dlg.x + @as(i32, DIALOG_WIDTH) - BUTTON_WIDTH - 8;
            if (x >= sec_x and x < sec_x + BUTTON_WIDTH and y >= btn_y and y < btn_y + BUTTON_HEIGHT) {
                new_hovered = 1;
            }
        }

        if (new_hovered != self._hovered_button) {
            self._hovered_button = new_hovered;
            self.peer.?.requestDraw() catch {};
        }
    }

    pub fn draw(self: *AlertDialog, ctx: *backend.DrawContext) !void {
        if (!self.visible.get()) return;

        const w = self.getWidth();
        const h = self.getHeight();
        const dlg = self.getDialogRect();

        // Draw scrim (semi-transparent background)
        ctx.setColorByte(sys.scrim());
        ctx.rectangle(0, 0, w, h);
        ctx.fill();

        // Draw dialog background
        ctx.setColorByte(sys.background());
        if (builtin.os.tag == .windows) {
            ctx.rectangle(dlg.x, dlg.y, dlg.w, dlg.h);
        } else {
            ctx.roundedRectangleEx(dlg.x, dlg.y, dlg.w, dlg.h, [4]f32{ 8, 8, 8, 8 });
        }
        ctx.fill();

        var title_layout = backend.DrawContext.TextLayout.init();
        title_layout.setFont(.{ .face = "Helvetica-Bold", .size = 16.0 });
        var body_layout = backend.DrawContext.TextLayout.init();
        body_layout.setFont(.{ .face = "Helvetica", .size = 13.0 });
        var btn_layout = backend.DrawContext.TextLayout.init();
        btn_layout.setFont(.{ .face = "Helvetica", .size = 13.0 });

        // Draw title
        ctx.setColorByte(sys.label());
        ctx.text(dlg.x + 16, dlg.y + 16, title_layout, self.title.get());

        // Draw message
        ctx.setColorByte(sys.secondaryLabel());
        ctx.text(dlg.x + 16, dlg.y + 48, body_layout, self.message.get());

        // Draw buttons
        const has_secondary = self.secondary_label.get().len > 0;
        const btn_y = dlg.y + @as(i32, DIALOG_HEIGHT) - BUTTON_HEIGHT - 12;

        // Primary button
        const pri_x = if (has_secondary) dlg.x + @as(i32, DIALOG_WIDTH) - BUTTON_WIDTH * 2 - 16 else dlg.x + @as(i32, DIALOG_WIDTH) - BUTTON_WIDTH - 8;

        const pri_bg = if (self._hovered_button != null and self._hovered_button.? == 0) sys.accentHover() else sys.accent();
        ctx.setColorByte(pri_bg);
        if (builtin.os.tag == .windows) {
            ctx.rectangle(pri_x, btn_y, BUTTON_WIDTH, BUTTON_HEIGHT);
        } else {
            ctx.roundedRectangleEx(pri_x, btn_y, BUTTON_WIDTH, BUTTON_HEIGHT, [4]f32{ 4, 4, 4, 4 });
        }
        ctx.fill();

        const pri_label = self.primary_label.get();
        const pri_text_size = btn_layout.getTextSize(pri_label);
        ctx.setColorByte(sys.accentLabel());
        ctx.text(
            pri_x + @as(i32, BUTTON_WIDTH / 2) - @as(i32, @intCast(pri_text_size.width / 2)),
            btn_y + @as(i32, BUTTON_HEIGHT / 2) - @as(i32, @intCast(pri_text_size.height / 2)),
            btn_layout,
            pri_label,
        );

        // Secondary button
        if (has_secondary) {
            const sec_x = dlg.x + @as(i32, DIALOG_WIDTH) - BUTTON_WIDTH - 8;
            const sec_bg = if (self._hovered_button != null and self._hovered_button.? == 1) sys.controlBorder() else sys.controlBackground();
            ctx.setColorByte(sec_bg);
            if (builtin.os.tag == .windows) {
                ctx.rectangle(sec_x, btn_y, BUTTON_WIDTH, BUTTON_HEIGHT);
            } else {
                ctx.roundedRectangleEx(sec_x, btn_y, BUTTON_WIDTH, BUTTON_HEIGHT, [4]f32{ 4, 4, 4, 4 });
            }
            ctx.fill();

            const sec_label = self.secondary_label.get();
            const sec_text_size = btn_layout.getTextSize(sec_label);
            ctx.setColorByte(sys.label());
            ctx.text(
                sec_x + @as(i32, BUTTON_WIDTH / 2) - @as(i32, @intCast(sec_text_size.width / 2)),
                btn_y + @as(i32, BUTTON_HEIGHT / 2) - @as(i32, @intCast(sec_text_size.height / 2)),
                btn_layout,
                sec_label,
            );
        }
    }

    pub fn show(self: *AlertDialog) !void {
        if (self.peer == null) {
            self.peer = try backend.Canvas.create();
            _ = try self.visible.addChangeListener(.{ .function = struct {
                fn callback(_: bool, userdata: ?*anyopaque) void {
                    const ptr: *AlertDialog = @ptrCast(@alignCast(userdata.?));
                    ptr.peer.?.requestDraw() catch {};
                }
            }.callback, .userdata = self });
            try self.setupEvents();
        }
    }
};

pub fn alertDialog(config: AlertDialog.Config) *AlertDialog {
    return AlertDialog.alloc(config);
}

test "AlertDialog default properties" {
    try backend.init();
    const dlg = alertDialog(.{});
    defer dlg.deinit();

    try std.testing.expectEqualStrings("Alert", dlg.title.get());
    try std.testing.expectEqualStrings("", dlg.message.get());
    try std.testing.expectEqualStrings("OK", dlg.primary_label.get());
    try std.testing.expectEqualStrings("", dlg.secondary_label.get());
    try std.testing.expect(dlg.visible.get());
}

test "AlertDialog with custom message" {
    try backend.init();
    const dlg = alertDialog(.{
        .title = "Error",
        .message = "Something went wrong",
        .primary_label = "Retry",
        .secondary_label = "Cancel",
    });
    defer dlg.deinit();

    try std.testing.expectEqualStrings("Error", dlg.title.get());
    try std.testing.expectEqualStrings("Something went wrong", dlg.message.get());
    try std.testing.expectEqualStrings("Retry", dlg.primary_label.get());
    try std.testing.expectEqualStrings("Cancel", dlg.secondary_label.get());
}

test "AlertDialog callback setters" {
    try backend.init();
    var dlg = alertDialog(.{});
    defer dlg.deinit();

    const State = struct {
        var primary_called: bool = false;
    };
    State.primary_called = false;

    _ = dlg.onPrimary(&struct {
        fn handler() void {
            State.primary_called = true;
        }
    }.handler);

    try std.testing.expect(dlg._on_primary != null);
}

test AlertDialog {
    var dlg = alertDialog(.{ .title = "Test", .message = "Hello" });
    dlg.ref();
    defer dlg.unref();
    try std.testing.expectEqual(true, dlg.visible.get());
    try std.testing.expect(std.mem.eql(u8, "Test", dlg.title.get()));
}
