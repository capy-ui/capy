const std = @import("std");
const shared = @import("../shared.zig");
const lib = @import("../../main.zig");
pub const c = @cImport({
    @cInclude("gtk/gtk.h");
});
const wbin_new = @import("windowbin.zig").wbin_new;
const wbin_set_child = @import("windowbin.zig").wbin_set_child;

const EventFunctions = shared.EventFunctions(@This());
const EventType = shared.BackendEventType;
const BackendError = shared.BackendError;
const MouseButton = shared.MouseButton;

// Supported GTK version
const GTK_VERSION = std.SemanticVersion.Range{
    .min = std.SemanticVersion.parse("4.0.0") catch unreachable,
    .max = std.SemanticVersion.parse("4.11.0") catch unreachable,
};

pub const Capabilities = .{ .useEventLoop = true };

var activeWindows = std.atomic.Atomic(usize).init(0);
var randomWindow: *c.GtkWidget = undefined;

var hasInit: bool = false;

pub fn init() BackendError!void {
    if (!hasInit) {
        hasInit = true;
        if (c.gtk_init_check() == 0) {
            return BackendError.InitializationError;
        }
    }
}

pub fn showNativeMessageDialog(msgType: shared.MessageType, comptime fmt: []const u8, args: anytype) void {
    const msg = std.fmt.allocPrintZ(lib.internal.scratch_allocator, fmt, args) catch {
        std.log.err("Could not launch message dialog, original text: " ++ fmt, args);
        return;
    };
    defer lib.internal.scratch_allocator.free(msg);

    const cType = @as(c_uint, @intCast(switch (msgType) {
        .Information => c.GTK_MESSAGE_INFO,
        .Warning => c.GTK_MESSAGE_WARNING,
        .Error => c.GTK_MESSAGE_ERROR,
    }));

    if (comptime GTK_VERSION.min.order(.{ .major = 4, .minor = 10, .patch = 0 }) != .lt) {
        // GTK 4.10 deprecated MessageDialog and introduced AlertDialog
        const dialog = c.gtk_alert_dialog_new("%s", msg.ptr);
        c.gtk_alert_dialog_show(dialog, null);
        // TODO: wait for the dialog using a lock and the gtk_alert_dialog_choose method
    } else {
        const dialog = c.gtk_message_dialog_new(null, c.GTK_DIALOG_DESTROY_WITH_PARENT, cType, c.GTK_BUTTONS_CLOSE, msg.ptr);
        c.gtk_window_set_modal(@ptrCast(dialog), 1);
        c.gtk_widget_show(@ptrCast(dialog));
        // TODO: wait for the dialog using a lock and the ::response signal
        // c.gtk_widget_destroy(dialog);
    }
}

pub const PeerType = *c.GtkWidget;

pub const Window = struct {
    peer: *c.GtkWidget,
    wbin: *c.GtkWidget,
    /// A VBox is required to contain the menu and the window's child (wrapped in wbin)
    vbox: *c.GtkWidget,
    menuBar: ?*c.GtkWidget = null,
    source_dpi: u32 = 96,
    scale: f32 = 1.0,
    child: ?*c.GtkWidget = null,

    pub usingnamespace Events(Window);

    fn gtkWindowHidden(_: *c.GtkWidget, _: usize) callconv(.C) void {
        _ = activeWindows.fetchSub(1, .Release);
    }

    pub fn create() BackendError!Window {
        const window = c.gtk_window_new() orelse return error.UnknownError;
        //const screen = c.gtk_window_get_screen(@ptrCast(*c.GtkWindow, window));
        //std.log.info("{d} dpi", .{c.gdk_screen_get_resolution(screen)});
        const wbin = wbin_new() orelse unreachable;

        const vbox = c.gtk_box_new(c.GTK_ORIENTATION_VERTICAL, 0) orelse return error.UnknownError;
        c.gtk_box_append(@ptrCast(vbox), wbin);
        c.gtk_box_set_homogeneous(@ptrCast(vbox), @intFromBool(true));

        c.gtk_window_set_child(@ptrCast(window), vbox);
        c.gtk_widget_show(window);
        c.gtk_widget_map(window);

        _ = c.g_signal_connect_data(window, "hide", @as(c.GCallback, @ptrCast(&gtkWindowHidden)), null, null, c.G_CONNECT_AFTER);
        randomWindow = window;
        try Window.setupEvents(window);

        const surface = c.gtk_native_get_surface(@ptrCast(window));
        _ = c.g_signal_connect_data(surface, "layout", @ptrCast(&gtkConfigure), null, null, c.G_CONNECT_AFTER);
        return Window{ .peer = window, .wbin = wbin, .vbox = vbox };
    }

    fn gtkConfigure(peer: *c.GdkSurface, _: *anyopaque, userdata: usize) callconv(.C) c.gboolean {
        _ = userdata;
        const native: *c.GtkWidget = @ptrCast(@alignCast(c.gtk_native_get_for_surface(@ptrCast(peer))));
        const data = getEventUserData(@ptrCast(native));
        const width = c.gdk_surface_get_width(peer);
        const height = c.gdk_surface_get_height(peer);

        const child_data = getEventUserData(
            c.gtk_widget_get_first_child(
                c.gtk_widget_get_first_child(
                    c.gtk_window_get_child(@ptrCast(native)),
                ),
            ),
        );
        const w_changed = if (child_data.actual_width) |old_width| width != old_width else true;
        const h_changed = if (child_data.actual_height) |old_height| height != old_height else true;
        const size_changed = w_changed or h_changed;
        child_data.actual_width = @intCast(width);
        child_data.actual_height = @intCast(height);
        if (data.class.resizeHandler) |handler|
            handler(@as(u32, @intCast(width)), @as(u32, @intCast(height)), @intFromPtr(data));
        if (data.user.resizeHandler) |handler|
            handler(@as(u32, @intCast(width)), @as(u32, @intCast(height)), data.userdata);
        if (size_changed) {
            if (child_data.class.resizeHandler) |handler|
                handler(@as(u32, @intCast(width)), @as(u32, @intCast(height)), @intFromPtr(child_data));
            if (child_data.user.resizeHandler) |handler|
                handler(@as(u32, @intCast(width)), @as(u32, @intCast(height)), child_data.userdata);
        }
        return 0;
    }

    pub fn resize(self: *Window, width: c_int, height: c_int) void {
        c.gtk_window_set_default_size(@ptrCast(self.peer), width, height);
    }

    pub fn setTitle(self: *Window, title: [*:0]const u8) void {
        c.gtk_window_set_title(@as(*c.GtkWindow, @ptrCast(self.peer)), title);
    }

    pub fn setIcon(self: *Window, data: ImageData) void {
        c.gtk_window_set_icon(@as(*c.GtkWindow, @ptrCast(self.peer)), data.peer);
    }

    pub fn setIconName(self: *Window, name: [:0]const u8) void {
        c.gtk_window_set_icon_name(@as(*c.GtkWindow, @ptrCast(self.peer)), name);
    }

    pub fn setChild(self: *Window, peer: ?*c.GtkWidget) void {
        self.child = peer;
        wbin_set_child(@ptrCast(self.wbin), peer);
    }

    pub fn setMenuBar(self: *Window, bar: lib.MenuBar_Impl) void {
        const menuBar = c.gtk_menu_bar_new().?;
        initMenu(@as(*c.GtkMenuShell, @ptrCast(menuBar)), bar.menus);

        c.gtk_box_pack_start(@as(*c.GtkBox, @ptrCast(self.vbox)), menuBar, 0, 0, 0);
        self.menuBar = menuBar;
    }

    pub fn setSourceDpi(self: *Window, dpi: u32) void {
        self.source_dpi = 96;
        // TODO: Handle GtkWindow moving between screens with different DPIs
        const resolution = @as(f32, 96.0);
        self.scale = resolution / @as(f32, @floatFromInt(dpi));
    }

    fn initMenu(menu: *c.GtkMenuShell, items: []const lib.MenuItem_Impl) void {
        for (items) |item| {
            const menuItem = c.gtk_menu_item_new_with_label(item.config.label);
            if (item.items.len > 0) {
                // The menu associated to the menu item
                const itemMenu = c.gtk_menu_new();
                initMenu(@as(*c.GtkMenuShell, @ptrCast(itemMenu)), item.items);
                c.gtk_menu_item_set_submenu(@as(*c.GtkMenuItem, @ptrCast(menuItem)), itemMenu);
            }
            if (item.config.onClick) |callback| {
                const data = @as(?*anyopaque, @ptrFromInt(@intFromPtr(callback)));
                _ = c.g_signal_connect_data(menuItem, "activate", @as(c.GCallback, @ptrCast(&gtkActivate)), data, null, c.G_CONNECT_AFTER);
            }

            c.gtk_menu_shell_append(menu, menuItem);
        }
    }

    fn gtkActivate(peer: *c.GtkMenuItem, userdata: ?*anyopaque) callconv(.C) void {
        _ = peer;

        const callback = @as(*const fn () void, @ptrCast(userdata.?));
        callback();
    }

    pub fn show(self: *Window) void {
        c.gtk_widget_show(self.peer);
        _ = activeWindows.fetchAdd(1, .Release);
    }

    pub fn close(self: *Window) void {
        c.gtk_window_close(@as(*c.GtkWindow, @ptrCast(self.peer)));
    }
};

/// user data used for handling events
pub const EventUserData = struct {
    user: EventFunctions = .{},
    class: EventFunctions = .{},
    userdata: usize = 0,
    classUserdata: usize = 0,
    peer: PeerType,
    focusOnClick: bool = false,
    actual_width: ?u31 = null,
    actual_height: ?u31 = null,
};

pub inline fn getEventUserData(peer: *c.GtkWidget) *EventUserData {
    return @as(*EventUserData, @ptrCast(@alignCast(c.g_object_get_data(@as(*c.GObject, @ptrCast(peer)), "eventUserData").?)));
}

pub fn getWidthFromPeer(peer: PeerType) c_int {
    const data = getEventUserData(peer);
    if (data.actual_width) |width| return width;
    return c.gtk_widget_get_allocated_width(peer);
}

pub fn getHeightFromPeer(peer: PeerType) c_int {
    const data = getEventUserData(peer);
    if (data.actual_height) |height| return height;
    return c.gtk_widget_get_allocated_height(peer);
}

/// Since GTK4 removed the ::size-allocate signal which was used to listen to widget resizes,
/// backend.Container now directly calls this method in order to emit the event.
pub fn widgetSizeChanged(peer: *c.GtkWidget, width: u32, height: u32) void {
    const data = getEventUserData(peer);
    data.actual_width = @intCast(width);
    data.actual_height = @intCast(height);
    if (data.class.resizeHandler) |handler|
        handler(width, height, @intFromPtr(data));
    if (data.user.resizeHandler) |handler|
        handler(width, height, data.userdata);
}

pub fn Events(comptime T: type) type {
    return struct {
        const Self = @This();

        pub fn setupEvents(widget: *c.GtkWidget) BackendError!void {
            // _ = c.g_signal_connect_data(widget, "button-press-event", @as(c.GCallback, @ptrCast(&gtkButtonPress)), null, null, c.G_CONNECT_AFTER);
            // _ = c.g_signal_connect_data(widget, "button-release-event", @as(c.GCallback, @ptrCast(&gtkButtonPress)), null, null, c.G_CONNECT_AFTER);
            // _ = c.g_signal_connect_data(widget, "motion-notify-event", @as(c.GCallback, @ptrCast(&gtkMouseMotion)), null, null, c.G_CONNECT_AFTER);
            // _ = c.g_signal_connect_data(widget, "scroll-event", @as(c.GCallback, @ptrCast(&gtkMouseScroll)), null, null, c.G_CONNECT_AFTER);

            const event_controller_key = c.gtk_event_controller_key_new();
            _ = c.g_signal_connect_data(event_controller_key, "key-pressed", @as(c.GCallback, @ptrCast(&gtkKeyPress)), null, null, c.G_CONNECT_AFTER);
            c.gtk_widget_add_controller(widget, event_controller_key);

            var data = try lib.internal.lasting_allocator.create(EventUserData);
            data.* = EventUserData{ .peer = widget }; // ensure that it uses default values
            c.g_object_set_data(@as(*c.GObject, @ptrCast(widget)), "eventUserData", data);
            _ = c.g_object_ref(@as(*c.GObject, @ptrCast(widget)));
        }

        pub inline fn copyEventUserData(source: *c.GtkWidget, destination: anytype) void {
            const data = getEventUserData(source);
            c.g_object_set_data(@as(*c.GObject, @ptrCast(destination)), "eventUserData", data);
        }

        const GdkEventKey = extern struct {
            type: c.GdkEventType,
            window: *c.GdkWindow,
            send_event: c.gint8,
            time: c.guint32,
            state: *c.GdkModifierType,
            keyval: c.guint,
            length: c.gint,
            string: [*:0]c.gchar,
            hardware_keycode: c.guint16,
            group: c.guint8,
            is_modifier: c.guint,
        };

        fn gtkKeyPress(controller: *c.GtkEventControllerKey, keyval: c.guint, keycode: c.guint, state: c.GdkModifierType, _: usize) callconv(.C) c.gboolean {
            _ = state;
            const peer = c.gtk_event_controller_get_widget(@ptrCast(controller));
            const data = getEventUserData(peer);

            // Decode keyval to unicode
            // NOTE: this isn't the proper way to do it as an IME should be used, but this does provide a crude approximation that can still be useful
            var finalKeyval: u21 = @intCast(keyval);
            if (keyval >= 0xFF00 and keyval < 0xFF20) { // control characters
                finalKeyval = @as(u21, @intCast(keyval)) - 0xFF00;
            }
            if (finalKeyval >= 32768) return 0;
            const codepoint = c.gdk_keyval_to_unicode(finalKeyval);
            var buf: [4]u8 = undefined;
            const str_length = std.unicode.utf8Encode(@intCast(codepoint), &buf) catch unreachable;
            const str = buf[0..str_length];

            if (str.len != 0) {
                if (data.class.keyTypeHandler) |handler| {
                    handler(str, @intFromPtr(data));
                    if (data.user.keyTypeHandler == null) return 1;
                }
                if (data.user.keyTypeHandler) |handler| {
                    handler(str, data.userdata);
                    return 1;
                }
            }
            if (data.class.keyPressHandler) |handler| {
                handler(@as(u16, @intCast(keycode)), @intFromPtr(data));
                if (data.user.keyPressHandler == null) return 1;
            }
            if (data.user.keyPressHandler) |handler| {
                handler(@as(u16, @intCast(keycode)), data.userdata);
                return 1;
            }

            return 0;
        }

        fn gtkButtonPress(peer: *c.GtkWidget, event: *c.GdkEvent, _: usize) callconv(.C) c.gboolean {
            const data = getEventUserData(peer);
            const pressed = switch (c.gdk_event_get_event_type(event)) {
                c.GDK_BUTTON_PRESS => true,
                c.GDK_BUTTON_RELEASE => false,
                // don't send released button in case of GDK_2BUTTON_PRESS, GDK_3BUTTON_PRESS, ...
                else => return 0,
            };

            var x: f64 = undefined;
            std.debug.assert(c.gdk_event_get_axis(event, c.GDK_AXIS_X, &x));
            var y: f64 = undefined;
            std.debug.assert(c.gdk_event_get_axis(event, c.GDK_AXIS_Y, &y));

            if (x < 0 or y < 0) return 0;

            const button = switch (c.gdk_button_event_get_button(event)) {
                1 => MouseButton.Left,
                2 => MouseButton.Middle,
                3 => MouseButton.Right,
                else => @as(MouseButton, @enumFromInt(event.button)),
            };
            const mx = @as(i32, @intFromFloat(@floor(x)));
            const my = @as(i32, @intFromFloat(@floor(y)));

            if (data.class.mouseButtonHandler) |handler| {
                handler(button, pressed, mx, my, @intFromPtr(data));
            }
            if (data.user.mouseButtonHandler) |handler| {
                if (data.focusOnClick) {
                    c.gtk_widget_grab_focus(peer);
                }
                handler(button, pressed, mx, my, data.userdata);
            }
            return 0;
        }

        fn gtkMouseMotion(peer: *c.GtkWidget, event: *c.GdkEvent, _: usize) callconv(.C) c.gboolean {
            const data = getEventUserData(peer);

            const mx = @as(i32, @intFromFloat(@floor(event.x)));
            const my = @as(i32, @intFromFloat(@floor(event.y)));
            if (data.class.mouseMotionHandler) |handler| {
                handler(mx, my, @intFromPtr(data));
                if (data.user.mouseMotionHandler == null) return 1;
            }
            if (data.user.mouseMotionHandler) |handler| {
                handler(mx, my, data.userdata);
                return 1;
            }
            return 0;
        }

        /// Temporary hack until translate-c can translate this struct
        const GdkEventScroll = extern struct { type: c.GdkEventType, window: *c.GdkWindow, send_event: c.gint8, time: c.guint32, x: c.gdouble, y: c.gdouble, state: c.guint, direction: c.GdkScrollDirection, device: *c.GdkDevice, x_root: c.gdouble, y_root: c.gdouble, delta_x: c.gdouble, delta_y: c.gdouble, is_stop: c.guint };

        fn gtkMouseScroll(peer: *c.GtkWidget, event: *c.GdkEvent, _: usize) callconv(.C) void {
            const data = getEventUserData(peer);
            const dx: f32 = switch (event.direction) {
                c.GDK_SCROLL_LEFT => -1,
                c.GDK_SCROLL_RIGHT => 1,
                else => @as(f32, @floatCast(event.delta_x)),
            };
            const dy: f32 = switch (event.direction) {
                c.GDK_SCROLL_UP => -1,
                c.GDK_SCROLL_DOWN => 1,
                else => @as(f32, @floatCast(event.delta_y)),
            };

            if (data.class.scrollHandler) |handler|
                handler(dx, dy, @intFromPtr(data));
            if (data.user.scrollHandler) |handler|
                handler(dx, dy, data.userdata);
        }

        pub fn deinit(self: *const T) void {
            const data = getEventUserData(self.peer);
            lib.internal.lasting_allocator.destroy(data);

            if (@hasDecl(T, "_deinit")) {
                self._deinit();
            }
            _ = c.g_object_unref(@as(*c.GObject, @ptrCast(self.peer)));
        }

        pub inline fn setUserData(self: *T, data: anytype) void {
            comptime {
                if (!std.meta.trait.isSingleItemPtr(@TypeOf(data))) {
                    @compileError(std.fmt.comptimePrint("Expected single item pointer, got {s}", .{@typeName(@TypeOf(data))}));
                }
            }

            getEventUserData(self.peer).userdata = @intFromPtr(data);
        }

        pub inline fn setCallback(self: *T, comptime eType: EventType, cb: anytype) !void {
            const data = &getEventUserData(self.peer).user;
            switch (eType) {
                .Click => data.clickHandler = cb,
                .Draw => data.drawHandler = cb,
                .MouseButton => data.mouseButtonHandler = cb,
                .MouseMotion => data.mouseMotionHandler = cb,
                .Scroll => data.scrollHandler = cb,
                .TextChanged => data.changedTextHandler = cb,
                .Resize => data.resizeHandler = cb,
                .KeyType => data.keyTypeHandler = cb,
                .KeyPress => data.keyPressHandler = cb,
                .PropertyChange => data.propertyChangeHandler = cb,
            }
        }

        pub fn setOpacity(self: *T, opacity: f64) void {
            c.gtk_widget_set_opacity(self.peer, opacity);
        }

        /// Requests a redraw
        pub fn requestDraw(self: *T) !void {
            c.gtk_widget_queue_draw(self.peer);
        }

        pub fn getWidth(self: *const T) c_int {
            return getWidthFromPeer(self.peer);
        }

        pub fn getHeight(self: *const T) c_int {
            return getHeightFromPeer(self.peer);
        }

        pub fn getPreferredSize(self: *const T) lib.Size {
            if (@hasDecl(T, "getPreferredSize_impl")) {
                return self.getPreferredSize_impl();
            }
            var requisition: c.GtkRequisition = undefined;
            c.gtk_widget_get_preferred_size(self.peer, null, &requisition);
            return lib.Size.init(
                @as(u32, @intCast(requisition.width)),
                @as(u32, @intCast(requisition.height)),
            );
        }
    };
}

// pub const Button = @import("../../flat/button.zig").FlatButton;

pub const Button = struct {
    peer: *c.GtkWidget,

    pub usingnamespace Events(Button);

    fn gtkClicked(peer: *c.GtkWidget, userdata: usize) callconv(.C) void {
        _ = userdata;
        const data = getEventUserData(peer);

        if (data.user.clickHandler) |handler| {
            handler(data.userdata);
        }
    }

    pub fn create() BackendError!Button {
        const button = c.gtk_button_new() orelse return error.UnknownError;
        try Button.setupEvents(button);
        _ = c.g_signal_connect_data(button, "clicked", @as(c.GCallback, @ptrCast(&gtkClicked)), null, @as(c.GClosureNotify, null), 0);
        return Button{ .peer = button };
    }

    pub fn setLabel(self: *const Button, label: [:0]const u8) void {
        c.gtk_button_set_label(@as(*c.GtkButton, @ptrCast(self.peer)), label.ptr);
    }

    pub fn getLabel(self: *const Button) [:0]const u8 {
        const label = c.gtk_button_get_label(@as(*c.GtkButton, @ptrCast(self.peer)));
        return std.mem.span(label);
    }

    pub fn setEnabled(self: *const Button, enabled: bool) void {
        c.gtk_widget_set_sensitive(self.peer, @intFromBool(enabled));
    }
};

pub const CheckBox = struct {
    peer: *c.GtkWidget,

    pub usingnamespace Events(CheckBox);

    fn gtkClicked(peer: *c.GtkWidget, userdata: usize) callconv(.C) void {
        _ = userdata;
        const data = getEventUserData(peer);

        if (data.user.clickHandler) |handler| {
            handler(data.userdata);
        }
    }

    pub fn create() BackendError!CheckBox {
        const button = c.gtk_check_button_new() orelse return error.UnknownError;
        try CheckBox.setupEvents(button);
        _ = c.g_signal_connect_data(button, "clicked", @as(c.GCallback, @ptrCast(&gtkClicked)), null, @as(c.GClosureNotify, null), 0);
        return CheckBox{ .peer = button };
    }

    pub fn setLabel(self: *const CheckBox, label: [:0]const u8) void {
        c.gtk_button_set_label(@as(*c.GtkButton, @ptrCast(self.peer)), label.ptr);
    }

    pub fn getLabel(self: *const CheckBox) [:0]const u8 {
        const label = c.gtk_button_get_label(@as(*c.GtkButton, @ptrCast(self.peer)));
        return std.mem.span(label);
    }

    pub fn setEnabled(self: *const CheckBox, enabled: bool) void {
        c.gtk_widget_set_sensitive(self.peer, @intFromBool(enabled));
    }

    pub fn setChecked(self: *const CheckBox, checked: bool) void {
        c.gtk_toggle_button_set_active(@as(*c.GtkToggleButton, @ptrCast(self.peer)), @intFromBool(checked));
    }

    pub fn isChecked(self: *const CheckBox) bool {
        return c.gtk_toggle_button_get_active(@as(*c.GtkToggleButton, @ptrCast(self.peer))) != 0;
    }
};

pub const Slider = struct {
    peer: *c.GtkWidget,

    pub usingnamespace Events(Slider);

    fn gtkValueChanged(peer: *c.GtkWidget, userdata: usize) callconv(.C) void {
        _ = userdata;
        const data = getEventUserData(peer);

        if (data.user.propertyChangeHandler) |handler| {
            const adjustment = c.gtk_range_get_adjustment(@as(*c.GtkRange, @ptrCast(peer)));
            const stepSize = c.gtk_adjustment_get_minimum_increment(adjustment);
            const value = c.gtk_range_get_value(@as(*c.GtkRange, @ptrCast(peer)));
            var adjustedValue = @round(value / stepSize) * stepSize;

            // check if it is equal to -0.0 (a quirk from IEEE 754), if it is then set to 0.0
            if (adjustedValue == 0 and std.math.copysign(@as(f64, 1.0), adjustedValue) == -1.0) {
                adjustedValue = 0.0;
            }

            if (!std.math.approxEqAbs(f64, value, adjustedValue, 0.001)) {
                c.gtk_range_set_value(@as(*c.GtkRange, @ptrCast(peer)), adjustedValue);
            } else {
                const value_f32 = @as(f32, @floatCast(adjustedValue));
                handler("value", &value_f32, data.userdata);
            }
        }
    }

    pub fn create() BackendError!Slider {
        const adjustment = c.gtk_adjustment_new(0, 0, 100 + 10, 10, 10, 10);
        const slider = c.gtk_scale_new(c.GTK_ORIENTATION_HORIZONTAL, adjustment) orelse return error.UnknownError;
        c.gtk_scale_set_draw_value(@as(*c.GtkScale, @ptrCast(slider)), @intFromBool(false));
        try Slider.setupEvents(slider);
        _ = c.g_signal_connect_data(slider, "value-changed", @as(c.GCallback, @ptrCast(&gtkValueChanged)), null, @as(c.GClosureNotify, null), 0);
        return Slider{ .peer = slider };
    }

    pub fn getValue(self: *const Slider) f32 {
        return @as(f32, @floatCast(c.gtk_range_get_value(@as(*c.GtkRange, @ptrCast(self.peer)))));
    }

    pub fn setValue(self: *Slider, value: f32) void {
        c.gtk_range_set_value(@as(*c.GtkRange, @ptrCast(self.peer)), value);
    }

    pub fn setMinimum(self: *Slider, minimum: f32) void {
        const adjustment = c.gtk_range_get_adjustment(@as(*c.GtkRange, @ptrCast(self.peer)));
        c.gtk_adjustment_set_lower(adjustment, minimum);
        c.gtk_range_set_adjustment(@as(*c.GtkRange, @ptrCast(self.peer)), adjustment);
    }

    pub fn setMaximum(self: *Slider, maximum: f32) void {
        const adjustment = c.gtk_range_get_adjustment(@as(*c.GtkRange, @ptrCast(self.peer)));
        c.gtk_adjustment_set_upper(adjustment, maximum + c.gtk_adjustment_get_step_increment(adjustment));
        c.gtk_range_set_adjustment(@as(*c.GtkRange, @ptrCast(self.peer)), adjustment);
    }

    pub fn setStepSize(self: *Slider, stepSize: f32) void {
        c.gtk_range_set_increments(@as(*c.GtkRange, @ptrCast(self.peer)), stepSize, stepSize * 10);
    }

    pub fn setEnabled(self: *Slider, enabled: bool) void {
        c.gtk_widget_set_sensitive(self.peer, @intFromBool(enabled));
    }

    pub fn setOrientation(self: *Slider, orientation: lib.Orientation) void {
        const gtkOrientation = switch (orientation) {
            .Horizontal => c.GTK_ORIENTATION_HORIZONTAL,
            .Vertical => c.GTK_ORIENTATION_VERTICAL,
        };
        c.gtk_orientable_set_orientation(@as(*c.GtkOrientable, @ptrCast(self.peer)), gtkOrientation);
    }
};

pub const Label = struct {
    peer: *c.GtkWidget,
    /// Temporary value invalidated once setText_uiThread is called
    nullTerminated: ?[:0]const u8 = null,

    pub usingnamespace Events(Label);

    pub fn create() BackendError!Label {
        const label = c.gtk_label_new("") orelse return BackendError.UnknownError;
        try Label.setupEvents(label);
        return Label{ .peer = label };
    }

    pub fn setAlignment(self: *Label, alignment: f32) void {
        c.gtk_label_set_xalign(@as(*c.GtkLabel, @ptrCast(self.peer)), alignment);
    }

    const RunOpts = struct {
        label: *c.GtkLabel,
        text: [:0]const u8,
    };

    fn setText_uiThread(userdata: ?*anyopaque) callconv(.C) c_int {
        const runOpts = @as(*RunOpts, @ptrCast(@alignCast(userdata.?)));
        const nullTerminated = runOpts.text;
        defer lib.internal.scratch_allocator.free(nullTerminated);
        defer lib.internal.scratch_allocator.destroy(runOpts);

        c.gtk_label_set_text(runOpts.label, runOpts.text);
        return c.G_SOURCE_REMOVE;
    }

    pub fn setText(self: *Label, text: []const u8) void {
        self.nullTerminated = lib.internal.lasting_allocator.dupeZ(u8, text) catch unreachable;

        // It must be run in UI thread otherwise set_text might crash randomly
        const runOpts = lib.internal.scratch_allocator.create(RunOpts) catch unreachable;
        runOpts.* = .{
            .label = @as(*c.GtkLabel, @ptrCast(self.peer)),
            .text = self.nullTerminated.?,
        };
        _ = c.g_idle_add(setText_uiThread, runOpts);
    }
};

pub const TextArea = struct {
    /// This is not actually the GtkTextView but this is the GtkScrolledWindow
    peer: *c.GtkWidget,
    textView: *c.GtkWidget,

    pub usingnamespace Events(TextArea);

    fn gtkTextChanged(peer: *c.GtkWidget, userdata: usize) callconv(.C) void {
        _ = userdata;
        const data = getEventUserData(peer);
        if (data.user.changedTextHandler) |handler| {
            handler(data.userdata);
        }
    }

    pub fn create() BackendError!TextArea {
        const textArea = c.gtk_text_view_new() orelse return BackendError.UnknownError;
        const scrolledWindow = c.gtk_scrolled_window_new(null, null) orelse return BackendError.UnknownError;
        c.gtk_container_add(@as(*c.GtkContainer, @ptrCast(scrolledWindow)), textArea);
        try TextArea.setupEvents(scrolledWindow);

        const buffer = c.gtk_text_view_get_buffer(@as(*c.GtkTextView, @ptrCast(textArea))).?;
        _ = c.g_signal_connect_data(buffer, "changed", @as(c.GCallback, @ptrCast(&gtkTextChanged)), null, @as(c.GClosureNotify, null), c.G_CONNECT_AFTER);
        TextArea.copyEventUserData(scrolledWindow, buffer);
        return TextArea{ .peer = scrolledWindow, .textView = textArea };
    }

    pub fn setText(self: *TextArea, text: []const u8) void {
        const buffer = c.gtk_text_view_get_buffer(@as(*c.GtkTextView, @ptrCast(self.textView)));
        c.gtk_text_buffer_set_text(buffer, text.ptr, @as(c_int, @intCast(text.len)));
    }

    pub fn setMonospaced(self: *TextArea, monospaced: bool) void {
        c.gtk_text_view_set_monospace(@as(*c.GtkTextView, @ptrCast(self.textView)), @intFromBool(monospaced));
    }

    pub fn getText(self: *TextArea) [:0]const u8 {
        const buffer = c.gtk_text_view_get_buffer(@as(*c.GtkTextView, @ptrCast(self.textView)));
        var start: c.GtkTextIter = undefined;
        var end: c.GtkTextIter = undefined;
        c.gtk_text_buffer_get_bounds(buffer, &start, &end);

        const text = c.gtk_text_buffer_get_text(buffer, &start, &end, 1);
        return std.mem.span(text);
    }
};

pub const TextField = struct {
    peer: *c.GtkWidget,
    // duplicate text to keep the same behaviour as other backends
    dup_text: std.ArrayList(u8),

    pub usingnamespace Events(TextField);

    fn gtkTextChanged(peer: *c.GtkWidget, userdata: usize) callconv(.C) void {
        _ = userdata;
        const data = getEventUserData(peer);
        if (data.user.changedTextHandler) |handler| {
            handler(data.userdata);
        }
    }

    pub fn create() BackendError!TextField {
        const textField = c.gtk_entry_new() orelse return BackendError.UnknownError;
        try TextField.setupEvents(textField);
        _ = c.g_signal_connect_data(textField, "changed", @as(c.GCallback, @ptrCast(&gtkTextChanged)), null, @as(c.GClosureNotify, null), c.G_CONNECT_AFTER);
        return TextField{ .peer = textField, .dup_text = std.ArrayList(u8).init(lib.internal.lasting_allocator) };
    }

    pub fn setText(self: *TextField, text: []const u8) void {
        var view = std.unicode.Utf8View.initUnchecked(text);
        var iterator = view.iterator();
        var numChars: c_int = 0;
        while (iterator.nextCodepoint() != null) {
            numChars += 1;
        }

        const buffer = c.gtk_entry_get_buffer(@as(*c.GtkEntry, @ptrCast(self.peer)));
        self.dup_text.clearRetainingCapacity();
        self.dup_text.appendSlice(text) catch return;

        c.gtk_entry_buffer_set_text(buffer, self.dup_text.items.ptr, numChars);
    }

    pub fn getText(self: *TextField) [:0]const u8 {
        const buffer = c.gtk_entry_get_buffer(@as(*c.GtkEntry, @ptrCast(self.peer)));
        const text = c.gtk_entry_buffer_get_text(buffer);
        const length = c.gtk_entry_buffer_get_bytes(buffer);
        return text[0..length :0];
    }

    pub fn setReadOnly(self: *TextField, readOnly: bool) void {
        c.gtk_editable_set_editable(@as(*c.GtkEditable, @ptrCast(self.peer)), @intFromBool(!readOnly));
        c.gtk_widget_set_can_focus(self.peer, @intFromBool(!readOnly));
    }

    pub fn _deinit(self: *const TextField) void {
        self.dup_text.deinit();
    }
};

pub const Canvas = struct {
    /// Actual GtkCanvas
    peer: *c.GtkWidget,

    pub usingnamespace Events(Canvas);

    // TODO: use f32 for coordinates?
    // avoid the burden of converting between signed and unsigned integers?

    pub const DrawContext = struct {
        cr: *c.cairo_t,
        widget: ?*c.GtkWidget = null,

        pub const Font = struct {
            face: [:0]const u8,
            size: f64,
        };

        pub const TextSize = struct { width: u32, height: u32 };

        pub const TextLayout = struct {
            _layout: *c.PangoLayout,
            _context: *c.PangoContext,
            /// If null, no text wrapping is applied, otherwise the text is wrapping as if this was the maximum width.
            wrap: ?f64 = null,

            pub fn setFont(self: *TextLayout, font: Font) void {
                const fontDescription = c.pango_font_description_from_string(font.face.ptr) orelse unreachable;
                c.pango_font_description_set_size(fontDescription, @as(c_int, @intFromFloat(@floor(font.size * @as(f64, c.PANGO_SCALE)))));
                c.pango_layout_set_font_description(self._layout, fontDescription);
                c.pango_font_description_free(fontDescription);
            }

            pub fn deinit(self: *TextLayout) void {
                c.g_object_unref(self._layout);
                c.g_object_unref(self._context);
            }

            pub fn getTextSize(self: *TextLayout, str: []const u8) TextSize {
                var width: c_int = undefined;
                var height: c_int = undefined;
                c.pango_layout_set_width(self._layout, if (self.wrap) |w| @as(c_int, @intFromFloat(@floor(w * @as(f64, c.PANGO_SCALE)))) else -1);
                c.pango_layout_set_text(self._layout, str.ptr, @as(c_int, @intCast(str.len)));
                c.pango_layout_get_pixel_size(self._layout, &width, &height);

                return TextSize{ .width = @as(u32, @intCast(width)), .height = @as(u32, @intCast(height)) };
            }

            pub fn init() TextLayout {
                const context = c.gdk_pango_context_get().?;
                return TextLayout{ ._context = context, ._layout = c.pango_layout_new(context).? };
            }
        };

        pub fn setColorByte(self: *DrawContext, color: lib.Color) void {
            self.setColorRGBA(@as(f32, @floatFromInt(color.red)) / 255.0, @as(f32, @floatFromInt(color.green)) / 255.0, @as(f32, @floatFromInt(color.blue)) / 255.0, @as(f32, @floatFromInt(color.alpha)) / 255.0);
        }

        /// Colors components are from 0 to 1.
        pub fn setColor(self: *DrawContext, r: f32, g: f32, b: f32) void {
            self.setColorRGBA(r, g, b, 1);
        }

        pub fn setColorRGBA(self: *DrawContext, r: f32, g: f32, b: f32, a: f32) void {
            const color = c.GdkRGBA{ .red = r, .green = g, .blue = b, .alpha = a };
            c.gdk_cairo_set_source_rgba(self.cr, &color);
        }

        pub const LinearGradient = struct {
            x0: f32,
            y0: f32,
            x1: f32,
            y1: f32,
            stops: []const Stop,

            pub const Stop = struct {
                offset: f32,
                color: lib.Color,
            };
        };

        pub fn setLinearGradient(self: *DrawContext, gradient: LinearGradient) void {
            const pattern = c.cairo_pattern_create_linear(gradient.x0, gradient.y0, gradient.x1, gradient.y1).?;
            for (gradient.stops) |stop| {
                c.cairo_pattern_add_color_stop_rgba(
                    pattern,
                    stop.offset,
                    @as(f32, @floatFromInt(stop.color.red)) / 255.0,
                    @as(f32, @floatFromInt(stop.color.green)) / 255.0,
                    @as(f32, @floatFromInt(stop.color.blue)) / 255.0,
                    @as(f32, @floatFromInt(stop.color.alpha)) / 255.0,
                );
            }
            c.cairo_set_source(self.cr, pattern);
        }

        /// Add a rectangle to the current path
        pub fn rectangle(self: *DrawContext, x: i32, y: i32, w: u32, h: u32) void {
            c.cairo_rectangle(self.cr, @as(f64, @floatFromInt(x)), @as(f64, @floatFromInt(y)), @as(f64, @floatFromInt(w)), @as(f64, @floatFromInt(h)));
        }

        pub fn roundedRectangle(self: *DrawContext, x: i32, y: i32, w: u32, h: u32, corner_radius: f32) void {
            self.roundedRectangleEx(x, y, w, h, .{corner_radius} ** 4);
        }

        /// The radiuses are in order: top left, top right, bottom left, bottom right
        pub fn roundedRectangleEx(self: *DrawContext, x: i32, y: i32, w: u32, h: u32, corner_radiuses: [4]f32) void {
            var corners: [4]f32 = corner_radiuses;
            if (corners[0] + corners[1] > @as(f32, @floatFromInt(w))) {
                const left_prop = corners[0] / (corners[0] + corners[1]);
                corners[0] = left_prop * @as(f32, @floatFromInt(w));
                corners[1] = (1 - left_prop) * @as(f32, @floatFromInt(w));
            }
            if (corners[2] + corners[3] > @as(f32, @floatFromInt(w))) {
                const left_prop = corners[2] / (corners[2] + corners[3]);
                corners[2] = left_prop * @as(f32, @floatFromInt(w));
                corners[3] = (1 - left_prop) * @as(f32, @floatFromInt(w));
            }
            if (corners[0] + corners[2] > @as(f32, @floatFromInt(h))) {
                const top_prop = corners[0] / (corners[0] + corners[2]);
                corners[0] = top_prop * @as(f32, @floatFromInt(h));
                corners[2] = (1 - top_prop) * @as(f32, @floatFromInt(h));
            }
            if (corners[1] + corners[3] > @as(f32, @floatFromInt(h))) {
                const top_prop = corners[1] / (corners[1] + corners[3]);
                corners[1] = top_prop * @as(f32, @floatFromInt(h));
                corners[3] = (1 - top_prop) * @as(f32, @floatFromInt(h));
            }

            c.cairo_new_sub_path(self.cr);
            c.cairo_arc(
                self.cr,
                @as(f64, @floatFromInt(x + @as(i32, @intCast(w)))) - corners[1],
                @as(f64, @floatFromInt(y)) + corners[1],
                corners[1],
                -std.math.pi / 2.0,
                0.0,
            );
            c.cairo_arc(
                self.cr,
                @as(f64, @floatFromInt(x + @as(i32, @intCast(w)))) - corners[3],
                @as(f64, @floatFromInt(y + @as(i32, @intCast(h)))) - corners[3],
                corners[3],
                0.0,
                std.math.pi / 2.0,
            );
            c.cairo_arc(
                self.cr,
                @as(f64, @floatFromInt(x)) + corners[2],
                @as(f64, @floatFromInt(y + @as(i32, @intCast(h)))) - corners[2],
                corners[2],
                std.math.pi / 2.0,
                std.math.pi,
            );
            c.cairo_arc(
                self.cr,
                @as(f64, @floatFromInt(x)) + corners[0],
                @as(f64, @floatFromInt(y)) + corners[0],
                corners[0],
                std.math.pi,
                std.math.pi / 2.0 * 3.0,
            );
            c.cairo_close_path(self.cr);
        }

        pub fn ellipse(self: *DrawContext, x: i32, y: i32, w: u32, h: u32) void {
            if (w == h) { // if it is a circle, we can use something slightly faster
                c.cairo_arc(self.cr, @as(f64, @floatFromInt(x + @as(i32, @intCast(w / 2)))), @as(f64, @floatFromInt(y + @as(i32, @intCast(w / 2)))), @as(f64, @floatFromInt(w / 2)), 0, 2 * std.math.pi);
                return;
            }
            var matrix: c.cairo_matrix_t = undefined;
            c.cairo_get_matrix(self.cr, &matrix);
            const scale = @as(f32, @floatFromInt(@max(w, h))) / 2;
            c.cairo_scale(self.cr, @as(f32, @floatFromInt(w / 2)) / scale, @as(f32, @floatFromInt(h / 2)) / scale);
            c.cairo_arc(self.cr, @as(f32, @floatFromInt(w / 2)), @as(f32, @floatFromInt(h / 2)), scale, 0, 2 * std.math.pi);
            c.cairo_set_matrix(self.cr, &matrix);
        }

        pub fn clear(self: *DrawContext, x: u32, y: u32, w: u32, h: u32) void {
            if (self.widget) |widget| {
                const styleContext = c.gtk_widget_get_style_context(widget);
                c.gtk_render_background(styleContext, self.cr, @as(f64, @floatFromInt(x)), @as(f64, @floatFromInt(y)), @as(f64, @floatFromInt(w)), @as(f64, @floatFromInt(h)));
            }
        }

        pub fn text(self: *DrawContext, x: i32, y: i32, layout: TextLayout, str: []const u8) void {
            const pangoLayout = layout._layout;
            var inkRect: c.PangoRectangle = undefined;
            c.pango_layout_get_pixel_extents(pangoLayout, null, &inkRect);

            const dx = @as(f64, @floatFromInt(inkRect.x));
            const dy = @as(f64, @floatFromInt(inkRect.y));
            c.cairo_move_to(self.cr, @as(f64, @floatFromInt(x)) + dx, @as(f64, @floatFromInt(y)) + dy);
            c.pango_layout_set_width(pangoLayout, if (layout.wrap) |w| @as(c_int, @intFromFloat(@floor(w * @as(f64, c.PANGO_SCALE)))) else -1);
            c.pango_layout_set_text(pangoLayout, str.ptr, @as(c_int, @intCast(str.len)));
            c.pango_layout_set_single_paragraph_mode(pangoLayout, 1); // used for coherence with other backends
            c.pango_cairo_update_layout(self.cr, pangoLayout);
            c.pango_cairo_show_layout(self.cr, pangoLayout);
        }

        pub fn line(self: *DrawContext, x1: i32, y1: i32, x2: i32, y2: i32) void {
            c.cairo_move_to(self.cr, @as(f64, @floatFromInt(x1)), @as(f64, @floatFromInt(y1)));
            c.cairo_line_to(self.cr, @as(f64, @floatFromInt(x2)), @as(f64, @floatFromInt(y2)));
            c.cairo_stroke(self.cr);
        }

        pub fn image(self: *DrawContext, x: i32, y: i32, w: u32, h: u32, data: lib.ImageData) void {
            c.cairo_save(self.cr);
            defer c.cairo_restore(self.cr);

            const width = @as(f64, @floatFromInt(data.width));
            const height = @as(f64, @floatFromInt(data.height));
            c.cairo_scale(self.cr, @as(f64, @floatFromInt(w)) / width, @as(f64, @floatFromInt(h)) / height);
            c.gdk_cairo_set_source_pixbuf(
                self.cr,
                data.peer.peer,
                @as(f64, @floatFromInt(x)) / (@as(f64, @floatFromInt(w)) / width),
                @as(f64, @floatFromInt(y)) / (@as(f64, @floatFromInt(h)) / height),
            );
            c.cairo_paint(self.cr);
        }

        pub fn setStrokeWidth(self: *DrawContext, width: f32) void {
            c.cairo_set_line_width(self.cr, width);
        }

        /// Stroke the current path and reset the path.
        pub fn stroke(self: *DrawContext) void {
            c.cairo_stroke(self.cr);
        }

        /// Fill the current path and reset the path.
        pub fn fill(self: *DrawContext) void {
            c.cairo_fill(self.cr);
        }
    };

    fn gtkCanvasDraw(peer: ?*c.GtkDrawingArea, cr: ?*c.cairo_t, _: c_int, _: c_int, _: ?*anyopaque) callconv(.C) void {
        const data = getEventUserData(@ptrCast(peer.?));
        var dc = DrawContext{ .cr = cr.?, .widget = @ptrCast(peer.?) };

        if (data.class.drawHandler) |handler|
            handler(&dc, @intFromPtr(data));
        if (data.user.drawHandler) |handler|
            handler(&dc, data.userdata);
    }

    pub fn create() BackendError!Canvas {
        const peer = c.gtk_drawing_area_new() orelse return BackendError.UnknownError;
        c.gtk_widget_set_can_focus(peer, 1);
        c.gtk_drawing_area_set_draw_func(@ptrCast(peer), &gtkCanvasDraw, null, null);

        try Canvas.setupEvents(peer);
        getEventUserData(peer).focusOnClick = true;

        return Canvas{ .peer = peer };
    }
};

pub const Container = struct {
    peer: *c.GtkWidget,
    container: *c.GtkWidget,

    pub usingnamespace Events(Container);

    pub fn create() BackendError!Container {
        const layout = c.gtk_fixed_new() orelse return BackendError.UnknownError;

        // A custom component is used to bypass GTK's minimum size mechanism
        const wbin = wbin_new() orelse return BackendError.UnknownError;
        wbin_set_child(@ptrCast(wbin), layout);
        try Container.setupEvents(wbin);
        return Container{ .peer = wbin, .container = layout };
    }

    pub fn add(self: *const Container, peer: PeerType) void {
        c.gtk_fixed_put(@as(*c.GtkFixed, @ptrCast(self.container)), peer, 0, 0);
    }

    pub fn remove(self: *const Container, peer: PeerType) void {
        // TODO(fix): the component might not be able to be added back
        // to fix this every peer type (Container, Button..) would have to hold a reference
        // that GTK knows about to their GtkWidget
        c.gtk_fixed_remove(@as(*c.GtkFixed, @ptrCast(self.container)), peer);
    }

    pub fn move(self: *const Container, peer: PeerType, x: u32, y: u32) void {
        c.gtk_fixed_move(@ptrCast(self.container), peer, @floatFromInt(x), @floatFromInt(y));
    }

    pub fn resize(self: *const Container, peer: PeerType, w: u32, h: u32) void {
        _ = self;
        c.gtk_widget_set_size_request(peer, @as(c_int, @intCast(w)), @as(c_int, @intCast(h)));
        // c.gtk_container_resize_children(@as(*c.GtkContainer, @ptrCast(self.container)));
        // c.gtk_widget_allocate(peer, @intCast(w), @intCast(h), -1, null);
        c.gtk_widget_queue_resize(peer);
        widgetSizeChanged(peer, w, h);
    }
};

pub const TabContainer = struct {
    peer: *c.GtkWidget,

    pub usingnamespace Events(TabContainer);

    pub fn create() BackendError!TabContainer {
        const layout = c.gtk_notebook_new() orelse return BackendError.UnknownError;
        try TabContainer.setupEvents(layout);
        return TabContainer{ .peer = layout };
    }

    /// Returns the index of the newly added tab
    pub fn insert(self: *const TabContainer, position: usize, peer: PeerType) usize {
        return @as(usize, @intCast(c.gtk_notebook_insert_page(@as(*c.GtkNotebook, @ptrCast(self.peer)), peer, null, @as(c_int, @intCast(position)))));
    }

    pub fn setLabel(self: *const TabContainer, position: usize, text: [:0]const u8) void {
        const child = c.gtk_notebook_get_nth_page(@as(*c.GtkNotebook, @ptrCast(self.peer)), @as(c_int, @intCast(position)));
        c.gtk_notebook_set_tab_label_text(@as(*c.GtkNotebook, @ptrCast(self.peer)), child, text.ptr);
    }

    /// Returns the number of tabs added to this tab container
    pub fn getTabsNumber(self: *const TabContainer) usize {
        return @as(usize, @intCast(c.gtk_notebook_get_n_pages(@as(*c.GtkNotebook, @ptrCast(self.peer)))));
    }
};

pub const ScrollView = struct {
    peer: *c.GtkWidget,

    pub usingnamespace Events(ScrollView);

    pub fn create() BackendError!ScrollView {
        const scrolledWindow = c.gtk_scrolled_window_new(null, null) orelse return BackendError.UnknownError;
        try ScrollView.setupEvents(scrolledWindow);
        return ScrollView{ .peer = scrolledWindow };
    }

    pub fn setChild(self: *ScrollView, peer: PeerType, _: *const lib.Widget) void {
        // TODO: remove old widget if there was one
        c.gtk_container_add(@as(*c.GtkContainer, @ptrCast(self.peer)), peer);
    }
};

pub const ImageData = struct {
    peer: *c.GdkPixbuf,
    mutex: std.Thread.Mutex = .{},
    width: usize,
    height: usize,

    pub const DrawLock = struct {
        _surface: *c.cairo_surface_t,
        draw_context: Canvas.DrawContext,
        data: *ImageData,

        pub fn end(self: DrawLock) void {
            const width = @as(c_int, @intCast(self.data.width));
            const height = @as(c_int, @intCast(self.data.height));

            c.g_object_unref(@as(*c.GObject, @ptrCast(@alignCast(self.data.peer))));
            self.data.peer = c.gdk_pixbuf_get_from_surface(self._surface, 0, 0, width, height).?;
            c.cairo_destroy(self.draw_context.cr);
            c.cairo_surface_destroy(self._surface);
            self.data.mutex.unlock();
        }
    };

    // TODO: copy bytes to a new array
    pub fn from(width: usize, height: usize, stride: usize, cs: lib.Colorspace, bytes: []const u8) !ImageData {
        const pixbuf = c.gdk_pixbuf_new_from_data(bytes.ptr, c.GDK_COLORSPACE_RGB, @intFromBool(cs == .RGBA), 8, @as(c_int, @intCast(width)), @as(c_int, @intCast(height)), @as(c_int, @intCast(stride)), null, null) orelse return BackendError.UnknownError;

        return ImageData{ .peer = pixbuf, .width = width, .height = height };
    }

    pub fn draw(self: *ImageData) DrawLock {
        self.mutex.lock();
        // TODO: just create one surface and use it forever
        const surface = c.gdk_cairo_surface_create_from_pixbuf(self.peer, 1, null).?;
        const cr = c.cairo_create(surface).?;
        return DrawLock{
            ._surface = surface,
            .draw_context = .{ .cr = cr },
            .data = self,
        };
    }

    pub fn deinit(self: *ImageData) void {
        self.mutex.lock();
        defer self.mutex.unlock();

        c.g_object_unref(@as(*c.GObject, @ptrCast(@alignCast(self.peer))));
    }
};

pub const NavigationSidebar = struct {
    peer: *c.GtkWidget,
    list: *c.GtkWidget,

    pub usingnamespace Events(NavigationSidebar);

    pub fn create() BackendError!NavigationSidebar {
        const listBox = c.gtk_list_box_new();

        // A custom component is used to bypass GTK's minimum size mechanism
        const wbin = wbin_new() orelse return BackendError.UnknownError;
        c.gtk_container_add(@as(*c.GtkContainer, @ptrCast(wbin)), listBox);
        try NavigationSidebar.setupEvents(wbin);

        var sidebar = NavigationSidebar{ .peer = wbin, .list = listBox };
        sidebar.append(undefined, "Test");
        return sidebar;
    }

    pub fn append(self: *NavigationSidebar, image: ImageData, label: [:0]const u8) void {
        const box = c.gtk_box_new(c.GTK_ORIENTATION_HORIZONTAL, 6);
        // TODO: append not prepend
        c.gtk_list_box_prepend(@as(*c.GtkListBox, @ptrCast(self.list)), box);

        _ = image;
        const icon = c.gtk_image_new_from_icon_name("dialog-warning-symbolic", c.GTK_ICON_SIZE_DIALOG);
        // TODO: create GtkImage from ImageData
        c.gtk_container_add(@as(*c.GtkContainer, @ptrCast(box)), icon);

        const label_gtk = c.gtk_label_new(label);
        c.gtk_container_add(@as(*c.GtkContainer, @ptrCast(box)), label_gtk);

        var context: *c.GtkStyleContext = c.gtk_widget_get_style_context(box);
        c.gtk_style_context_add_class(context, "activatable");
        c.gtk_style_context_add_class(context, "row");
    }

    pub fn getPreferredSize_impl(self: *const NavigationSidebar) lib.Size {
        _ = self;
        return lib.Size.init(
            @as(u32, @intCast(200)),
            @as(u32, @intCast(100)),
        );
    }
};

// downcasting to [*]u8 due to translate-c bugs which won't even accept
// pointer to an event.
extern fn gdk_event_new(type: c_int) [*]align(8) u8;
extern fn gtk_main_do_event(event: [*c]u8) void;

pub fn postEmptyEvent() void {
    // const event = gdk_event_new(c.GDK_DAMAGE);
    // const expose = @ptrCast(*c.GdkEventExpose, event);
    // expose.window = c.gtk_widget_get_window(randomWindow);
    // expose.send_event = 1;
    // expose.count = 0;
    // expose.area = c.GdkRectangle {
    //     .x = 0, .y = 0, .width = 1000, .height = 1000
    // };
    // gtk_main_do_event(event);
    var rect = c.GdkRectangle{ .x = 0, .y = 0, .width = 100, .height = 100 };
    c.gdk_window_invalidate_rect(c.gtk_widget_get_window(randomWindow), &rect, 0);
}

pub fn runStep(step: shared.EventLoopStep) bool {
    const context = c.g_main_context_default();
    _ = c.g_main_context_iteration(context, @intFromBool(step == .Blocking));

    if (GTK_VERSION.min.order(.{ .major = 4, .minor = 0, .patch = 0 }) != .lt) {
        return c.g_list_model_get_n_items(c.gtk_window_get_toplevels()) > 0;
    } else {
        return activeWindows.load(.Acquire) != 0;
    }
}
