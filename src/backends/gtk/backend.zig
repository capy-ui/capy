const std = @import("std");
const shared = @import("../shared.zig");
const lib = @import("../../main.zig");
pub const c = @cImport({
    @cInclude("gtk/gtk.h");
});
const wbin_new = @import("windowbin.zig").wbin_new;

const EventFunctions = shared.EventFunctions(@This());
const EventType = shared.BackendEventType;
const BackendError = shared.BackendError;
const MouseButton = shared.MouseButton;

pub const Capabilities = .{ .useEventLoop = true };

var activeWindows = std.atomic.Atomic(usize).init(0);
var randomWindow: *c.GtkWidget = undefined;

var hasInit: bool = false;

pub fn init() BackendError!void {
    if (!hasInit) {
        hasInit = true;
        if (c.gtk_init_check(0, null) == 0) {
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

    const cType = @intCast(c_uint, switch (msgType) {
        .Information => c.GTK_MESSAGE_INFO,
        .Warning => c.GTK_MESSAGE_WARNING,
        .Error => c.GTK_MESSAGE_ERROR,
    });

    const dialog = c.gtk_message_dialog_new(null, c.GTK_DIALOG_DESTROY_WITH_PARENT, cType, c.GTK_BUTTONS_CLOSE, msg.ptr);
    _ = c.gtk_dialog_run(@ptrCast(*c.GtkDialog, dialog));
    c.gtk_widget_destroy(dialog);
}

pub const PeerType = *c.GtkWidget;

export fn gtkWindowHidden(_: *c.GtkWidget, _: usize) void {
    _ = activeWindows.fetchSub(1, .Release);
}

pub const Window = struct {
    peer: *c.GtkWidget,
    wbin: *c.GtkWidget,
    /// A VBox is required to contain the menu and the window's child (wrapped in wbin)
    vbox: *c.GtkWidget,
    menuBar: ?*c.GtkWidget = null,
    source_dpi: u32 = 96,
    scale: f32 = 1.0,

    pub usingnamespace Events(Window);

    pub fn create() BackendError!Window {
        const window = c.gtk_window_new(c.GTK_WINDOW_TOPLEVEL) orelse return error.UnknownError;
        //const screen = c.gtk_window_get_screen(@ptrCast(*c.GtkWindow, window));
        //std.log.info("{d} dpi", .{c.gdk_screen_get_resolution(screen)});
        const wbin = wbin_new() orelse unreachable;
        c.gtk_widget_show(wbin);

        const vbox = c.gtk_vbox_new(0, 0) orelse return error.UnknownError;
        c.gtk_box_pack_end(@ptrCast(*c.GtkBox, vbox), wbin, 1, 1, 0);

        c.gtk_container_add(@ptrCast(*c.GtkContainer, window), vbox);
        c.gtk_widget_show(vbox);

        if (comptime @import("builtin").zig_backend != .stage1) {
            _ = c.g_signal_connect_data(window, "hide", @ptrCast(c.GCallback, &gtkWindowHidden), null, null, c.G_CONNECT_AFTER);
        } else {
            _ = c.g_signal_connect_data(window, "hide", @ptrCast(c.GCallback, gtkWindowHidden), null, null, c.G_CONNECT_AFTER);
        }
        randomWindow = window;
        return Window{ .peer = window, .wbin = wbin, .vbox = vbox };
    }

    pub fn resize(self: *Window, width: c_int, height: c_int) void {
        c.gtk_window_resize(@ptrCast(*c.GtkWindow, self.peer), @floatToInt(c_int, @intToFloat(f32, width) * self.scale), @floatToInt(c_int, @intToFloat(f32, height) * self.scale));
    }

    pub fn setTitle(self: *Window, title: [*:0]const u8) void {
        c.gtk_window_set_title(@ptrCast(*c.GtkWindow, self.peer), title);
    }

    pub fn setIcon(self: *Window, data: ImageData) void {
        c.gtk_window_set_icon(@ptrCast(*c.GtkWindow, self.peer), data.peer);
    }

    pub fn setIconName(self: *Window, name: [:0]const u8) void {
        c.gtk_window_set_icon_name(@ptrCast(*c.GtkWindow, self.peer), name);
    }

    pub fn setChild(self: *Window, peer: ?*c.GtkWidget) void {
        c.gtk_container_add(@ptrCast(*c.GtkContainer, self.wbin), peer);
    }

    pub fn setMenuBar(self: *Window, bar: lib.MenuBar_Impl) void {
        const menuBar = c.gtk_menu_bar_new().?;
        initMenu(@ptrCast(*c.GtkMenuShell, menuBar), bar.menus);

        c.gtk_box_pack_start(@ptrCast(*c.GtkBox, self.vbox), menuBar, 0, 0, 0);
        c.gtk_widget_show(menuBar);
        self.menuBar = menuBar;
    }

    pub fn setSourceDpi(self: *Window, dpi: u32) void {
        self.source_dpi = 96;
        // TODO: Handle GtkWindow moving between screens with different DPIs
        const resolution = @as(f32, 96.0);
        self.scale = resolution / @intToFloat(f32, dpi);
    }

    fn initMenu(menu: *c.GtkMenuShell, items: []const lib.MenuItem_Impl) void {
        for (items) |item| {
            const menuItem = c.gtk_menu_item_new_with_label(item.config.label);
            if (item.items.len > 0) {
                // The menu associated to the menu item
                const itemMenu = c.gtk_menu_new();
                initMenu(@ptrCast(*c.GtkMenuShell, itemMenu), item.items);
                c.gtk_menu_item_set_submenu(@ptrCast(*c.GtkMenuItem, menuItem), itemMenu);
            }
            if (item.config.onClick) |callback| {
                const data = @intToPtr(?*anyopaque, @ptrToInt(callback));
                _ = c.g_signal_connect_data(menuItem, "activate", @ptrCast(c.GCallback, &gtkActivate), data, null, c.G_CONNECT_AFTER);
            }

            c.gtk_menu_shell_append(menu, menuItem);
            c.gtk_widget_show(menuItem);
        }
    }

    fn gtkActivate(peer: *c.GtkMenuItem, userdata: ?*anyopaque) callconv(.C) void {
        _ = peer;

        const callback = @ptrCast(*const fn () void, userdata.?);
        callback();
    }

    pub fn show(self: *Window) void {
        c.gtk_widget_show(self.peer);
        _ = activeWindows.fetchAdd(1, .Release);
    }

    pub fn close(self: *Window) void {
        c.gtk_window_close(@ptrCast(*c.GtkWindow, self.peer));
    }
};

// zig fmt: off
/// user data used for handling events
pub const EventUserData = struct {
    user: EventFunctions = .{},
    class: EventFunctions = .{},
    userdata: usize = 0,
    classUserdata: usize = 0,
    peer: PeerType,
    focusOnClick: bool = false,
};
// zig fmt: on

pub inline fn getEventUserData(peer: *c.GtkWidget) *EventUserData {
    return @ptrCast(*EventUserData, @alignCast(@alignOf(EventUserData), c.g_object_get_data(@ptrCast(*c.GObject, peer), "eventUserData").?));
}

pub fn getWidthFromPeer(peer: PeerType) c_int {
    return c.gtk_widget_get_allocated_width(peer);
}

pub fn getHeightFromPeer(peer: PeerType) c_int {
    return c.gtk_widget_get_allocated_height(peer);
}

pub fn Events(comptime T: type) type {
    return struct {
        const Self = @This();

        pub fn setupEvents(widget: *c.GtkWidget) BackendError!void {
            _ = c.g_signal_connect_data(widget, "button-press-event", @ptrCast(c.GCallback, &gtkButtonPress), null, null, c.G_CONNECT_AFTER);
            _ = c.g_signal_connect_data(widget, "button-release-event", @ptrCast(c.GCallback, &gtkButtonPress), null, null, c.G_CONNECT_AFTER);
            _ = c.g_signal_connect_data(widget, "motion-notify-event", @ptrCast(c.GCallback, &gtkMouseMotion), null, null, c.G_CONNECT_AFTER);
            _ = c.g_signal_connect_data(widget, "scroll-event", @ptrCast(c.GCallback, &gtkMouseScroll), null, null, c.G_CONNECT_AFTER);
            _ = c.g_signal_connect_data(widget, "size-allocate", @ptrCast(c.GCallback, &gtkSizeAllocate), null, null, c.G_CONNECT_AFTER);
            _ = c.g_signal_connect_data(widget, "key-press-event", @ptrCast(c.GCallback, &gtkKeyPress), null, null, c.G_CONNECT_AFTER);
            c.gtk_widget_add_events(widget, c.GDK_SCROLL_MASK | c.GDK_BUTTON_PRESS_MASK | c.GDK_BUTTON_RELEASE_MASK | c.GDK_KEY_PRESS_MASK | c.GDK_POINTER_MOTION_MASK);

            var data = try lib.internal.lasting_allocator.create(EventUserData);
            data.* = EventUserData{ .peer = widget }; // ensure that it uses default values
            c.g_object_set_data(@ptrCast(*c.GObject, widget), "eventUserData", data);
        }

        pub inline fn copyEventUserData(source: *c.GtkWidget, destination: anytype) void {
            const data = getEventUserData(source);
            c.g_object_set_data(@ptrCast(*c.GObject, destination), "eventUserData", data);
        }

        fn gtkSizeAllocate(peer: *c.GtkWidget, allocation: *c.GdkRectangle, userdata: usize) callconv(.C) void {
            _ = userdata;
            const data = getEventUserData(peer);
            if (data.class.resizeHandler) |handler|
                handler(@intCast(u32, allocation.width), @intCast(u32, allocation.height), @ptrToInt(data));
            if (data.user.resizeHandler) |handler|
                handler(@intCast(u32, allocation.width), @intCast(u32, allocation.height), data.userdata);
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

        fn gtkKeyPress(peer: *c.GtkWidget, event: *GdkEventKey, userdata: usize) callconv(.C) c.gboolean {
            _ = userdata;
            const data = getEventUserData(peer);
            const str = event.string[0..@intCast(usize, event.length)];
            if (str.len != 0 and T != Canvas) {
                if (data.class.keyTypeHandler) |handler| {
                    handler(str, @ptrToInt(data));
                    if (data.user.keyTypeHandler == null) return 1;
                }
                if (data.user.keyTypeHandler) |handler| {
                    handler(str, data.userdata);
                    return 1;
                }
            }
            if (data.class.keyPressHandler) |handler| {
                handler(event.hardware_keycode, @ptrToInt(data));
                if (data.user.keyPressHandler == null) return 1;
            }
            if (data.user.keyPressHandler) |handler| {
                handler(event.hardware_keycode, data.userdata);
                return 1;
            }

            return 0;
        }

        fn gtkButtonPress(peer: *c.GtkWidget, event: *c.GdkEventButton, userdata: usize) callconv(.C) c.gboolean {
            _ = userdata;
            const data = getEventUserData(peer);
            const pressed = switch (event.type) {
                c.GDK_BUTTON_PRESS => true,
                c.GDK_BUTTON_RELEASE => false,
                // don't send released button in case of GDK_2BUTTON_PRESS, GDK_3BUTTON_PRESS, ...
                else => return 0,
            };
            if (event.x < 0 or event.y < 0) return 0;

            const button = switch (event.button) {
                1 => MouseButton.Left,
                2 => MouseButton.Middle,
                3 => MouseButton.Right,
                else => @intToEnum(MouseButton, event.button),
            };
            const mx = @floatToInt(i32, @floor(event.x));
            const my = @floatToInt(i32, @floor(event.y));

            if (data.class.mouseButtonHandler) |handler| {
                handler(button, pressed, mx, my, @ptrToInt(data));
            }
            if (data.user.mouseButtonHandler) |handler| {
                if (data.focusOnClick) {
                    c.gtk_widget_grab_focus(peer);
                }
                handler(button, pressed, mx, my, data.userdata);
            }
            return 0;
        }

        fn gtkMouseMotion(peer: *c.GtkWidget, event: *c.GdkEventMotion, userdata: usize) callconv(.C) c.gboolean {
            _ = userdata;
            const data = getEventUserData(peer);

            const mx = @floatToInt(i32, @floor(event.x));
            const my = @floatToInt(i32, @floor(event.y));
            if (data.class.mouseMotionHandler) |handler| {
                handler(mx, my, @ptrToInt(data));
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

        fn gtkMouseScroll(peer: *c.GtkWidget, event: *GdkEventScroll, userdata: usize) callconv(.C) void {
            _ = userdata;
            const data = getEventUserData(peer);
            const dx: f32 = switch (event.direction) {
                c.GDK_SCROLL_LEFT => -1,
                c.GDK_SCROLL_RIGHT => 1,
                else => @floatCast(f32, event.delta_x),
            };
            const dy: f32 = switch (event.direction) {
                c.GDK_SCROLL_UP => -1,
                c.GDK_SCROLL_DOWN => 1,
                else => @floatCast(f32, event.delta_y),
            };

            if (data.class.scrollHandler) |handler|
                handler(dx, dy, @ptrToInt(data));
            if (data.user.scrollHandler) |handler|
                handler(dx, dy, data.userdata);
        }

        pub fn deinit(self: *const T) void {
            std.log.info("deinit {s}", .{@typeName(T)});
            std.log.info("peer = {} width = {d}", .{ self, self.getWidth() });
            const data = getEventUserData(self.peer);
            lib.internal.lasting_allocator.destroy(data);

            if (@hasDecl(T, "_deinit")) {
                self._deinit();
            }
        }

        pub inline fn setUserData(self: *T, data: anytype) void {
            comptime {
                if (!std.meta.trait.isSingleItemPtr(@TypeOf(data))) {
                    @compileError(std.fmt.comptimePrint("Expected single item pointer, got {s}", .{@typeName(@TypeOf(data))}));
                }
            }

            getEventUserData(self.peer).userdata = @ptrToInt(data);
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
                @intCast(u32, requisition.width),
                @intCast(u32, requisition.height),
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
        c.gtk_widget_show(button);
        try Button.setupEvents(button);
        _ = c.g_signal_connect_data(button, "clicked", @ptrCast(c.GCallback, &gtkClicked), null, @as(c.GClosureNotify, null), 0);
        return Button{ .peer = button };
    }

    pub fn setLabel(self: *const Button, label: [:0]const u8) void {
        c.gtk_button_set_label(@ptrCast(*c.GtkButton, self.peer), label.ptr);
    }

    pub fn getLabel(self: *const Button) [:0]const u8 {
        const label = c.gtk_button_get_label(@ptrCast(*c.GtkButton, self.peer));
        return std.mem.span(label);
    }

    pub fn setEnabled(self: *const Button, enabled: bool) void {
        c.gtk_widget_set_sensitive(self.peer, @boolToInt(enabled));
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
        c.gtk_widget_show(button);
        try CheckBox.setupEvents(button);
        _ = c.g_signal_connect_data(button, "clicked", @ptrCast(c.GCallback, &gtkClicked), null, @as(c.GClosureNotify, null), 0);
        return CheckBox{ .peer = button };
    }

    pub fn setLabel(self: *const CheckBox, label: [:0]const u8) void {
        c.gtk_button_set_label(@ptrCast(*c.GtkButton, self.peer), label.ptr);
    }

    pub fn getLabel(self: *const CheckBox) [:0]const u8 {
        const label = c.gtk_button_get_label(@ptrCast(*c.GtkButton, self.peer));
        return std.mem.span(label);
    }

    pub fn setEnabled(self: *const CheckBox, enabled: bool) void {
        c.gtk_widget_set_sensitive(self.peer, @boolToInt(enabled));
    }

    pub fn setChecked(self: *const CheckBox, checked: bool) void {
        c.gtk_toggle_button_set_active(@ptrCast(*c.GtkToggleButton, self.peer), @boolToInt(checked));
    }

    pub fn isChecked(self: *const CheckBox) bool {
        return c.gtk_toggle_button_get_active(@ptrCast(*c.GtkToggleButton, self.peer)) != 0;
    }
};

pub const Slider = struct {
    peer: *c.GtkWidget,

    pub usingnamespace Events(Slider);

    fn gtkValueChanged(peer: *c.GtkWidget, userdata: usize) callconv(.C) void {
        _ = userdata;
        const data = getEventUserData(peer);

        if (data.user.propertyChangeHandler) |handler| {
            const adjustment = c.gtk_range_get_adjustment(@ptrCast(*c.GtkRange, peer));
            const stepSize = c.gtk_adjustment_get_minimum_increment(adjustment);
            const value = c.gtk_range_get_value(@ptrCast(*c.GtkRange, peer));
            var adjustedValue = @round(value / stepSize) * stepSize;

            // check if it is equal to -0.0 (a quirk from IEEE 754), if it is then set to 0.0
            if (adjustedValue == 0 and std.math.copysign(@as(f64, 1.0), adjustedValue) == -1.0) {
                adjustedValue = 0.0;
            }

            if (!std.math.approxEqAbs(f64, value, adjustedValue, 0.001)) {
                c.gtk_range_set_value(@ptrCast(*c.GtkRange, peer), adjustedValue);
            } else {
                const value_f32 = @floatCast(f32, adjustedValue);
                handler("value", &value_f32, data.userdata);
            }
        }
    }

    pub fn create() BackendError!Slider {
        const adjustment = c.gtk_adjustment_new(0, 0, 100 + 10, 10, 10, 10);
        const slider = c.gtk_scale_new(c.GTK_ORIENTATION_HORIZONTAL, adjustment) orelse return error.UnknownError;
        c.gtk_scale_set_draw_value(@ptrCast(*c.GtkScale, slider), @boolToInt(false));
        c.gtk_widget_show(slider);
        try Slider.setupEvents(slider);
        _ = c.g_signal_connect_data(slider, "value-changed", @ptrCast(c.GCallback, &gtkValueChanged), null, @as(c.GClosureNotify, null), 0);
        return Slider{ .peer = slider };
    }

    pub fn getValue(self: *const Slider) f32 {
        return @floatCast(f32, c.gtk_range_get_value(@ptrCast(*c.GtkRange, self.peer)));
    }

    pub fn setValue(self: *Slider, value: f32) void {
        c.gtk_range_set_value(@ptrCast(*c.GtkRange, self.peer), value);
    }

    pub fn setMinimum(self: *Slider, minimum: f32) void {
        const adjustment = c.gtk_range_get_adjustment(@ptrCast(*c.GtkRange, self.peer));
        c.gtk_adjustment_set_lower(adjustment, minimum);
        c.gtk_range_set_adjustment(@ptrCast(*c.GtkRange, self.peer), adjustment);
    }

    pub fn setMaximum(self: *Slider, maximum: f32) void {
        const adjustment = c.gtk_range_get_adjustment(@ptrCast(*c.GtkRange, self.peer));
        c.gtk_adjustment_set_upper(adjustment, maximum + c.gtk_adjustment_get_step_increment(adjustment));
        c.gtk_range_set_adjustment(@ptrCast(*c.GtkRange, self.peer), adjustment);
    }

    pub fn setStepSize(self: *Slider, stepSize: f32) void {
        c.gtk_range_set_increments(@ptrCast(*c.GtkRange, self.peer), stepSize, stepSize * 10);
    }

    pub fn setEnabled(self: *Slider, enabled: bool) void {
        c.gtk_widget_set_sensitive(self.peer, @boolToInt(enabled));
    }

    pub fn setOrientation(self: *Slider, orientation: lib.Orientation) void {
        const gtkOrientation = switch (orientation) {
            .Horizontal => c.GTK_ORIENTATION_HORIZONTAL,
            .Vertical => c.GTK_ORIENTATION_VERTICAL,
        };
        c.gtk_orientable_set_orientation(@ptrCast(*c.GtkOrientable, self.peer), gtkOrientation);
    }
};

pub const Label = struct {
    peer: *c.GtkWidget,
    /// Temporary value invalidated once setText_uiThread is called
    nullTerminated: ?[:0]const u8 = null,

    pub usingnamespace Events(Label);

    pub fn create() BackendError!Label {
        const label = c.gtk_label_new("") orelse return BackendError.UnknownError;
        c.gtk_widget_show(label);
        try Label.setupEvents(label);
        return Label{ .peer = label };
    }

    pub fn setAlignment(self: *Label, alignment: f32) void {
        c.gtk_label_set_xalign(@ptrCast(*c.GtkLabel, self.peer), alignment);
    }

    const RunOpts = struct {
        label: *c.GtkLabel,
        text: [:0]const u8,
    };

    fn setText_uiThread(userdata: ?*anyopaque) callconv(.C) c_int {
        const runOpts = @ptrCast(*RunOpts, @alignCast(@alignOf(RunOpts), userdata.?));
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
            .label = @ptrCast(*c.GtkLabel, self.peer),
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
        c.gtk_container_add(@ptrCast(*c.GtkContainer, scrolledWindow), textArea);
        c.gtk_widget_show(textArea);
        c.gtk_widget_show(scrolledWindow);
        try TextArea.setupEvents(scrolledWindow);

        const buffer = c.gtk_text_view_get_buffer(@ptrCast(*c.GtkTextView, textArea)).?;
        _ = c.g_signal_connect_data(buffer, "changed", @ptrCast(c.GCallback, &gtkTextChanged), null, @as(c.GClosureNotify, null), c.G_CONNECT_AFTER);
        TextArea.copyEventUserData(scrolledWindow, buffer);
        return TextArea{ .peer = scrolledWindow, .textView = textArea };
    }

    pub fn setText(self: *TextArea, text: []const u8) void {
        const buffer = c.gtk_text_view_get_buffer(@ptrCast(*c.GtkTextView, self.textView));
        c.gtk_text_buffer_set_text(buffer, text.ptr, @intCast(c_int, text.len));
    }

    pub fn setMonospaced(self: *TextArea, monospaced: bool) void {
        c.gtk_text_view_set_monospace(@ptrCast(*c.GtkTextView, self.textView), @boolToInt(monospaced));
    }

    pub fn getText(self: *TextArea) [:0]const u8 {
        const buffer = c.gtk_text_view_get_buffer(@ptrCast(*c.GtkTextView, self.textView));
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
        c.gtk_widget_show(textField);
        try TextField.setupEvents(textField);
        _ = c.g_signal_connect_data(textField, "changed", @ptrCast(c.GCallback, &gtkTextChanged), null, @as(c.GClosureNotify, null), c.G_CONNECT_AFTER);
        return TextField{ .peer = textField, .dup_text = std.ArrayList(u8).init(lib.internal.lasting_allocator) };
    }

    pub fn setText(self: *TextField, text: []const u8) void {
        var view = std.unicode.Utf8View.initUnchecked(text);
        var iterator = view.iterator();
        var numChars: c_int = 0;
        while (iterator.nextCodepoint() != null) {
            numChars += 1;
        }

        const buffer = c.gtk_entry_get_buffer(@ptrCast(*c.GtkEntry, self.peer));
        self.dup_text.clearRetainingCapacity();
        self.dup_text.appendSlice(text) catch return;

        c.gtk_entry_buffer_set_text(buffer, self.dup_text.items.ptr, numChars);
    }

    pub fn getText(self: *TextField) [:0]const u8 {
        const buffer = c.gtk_entry_get_buffer(@ptrCast(*c.GtkEntry, self.peer));
        const text = c.gtk_entry_buffer_get_text(buffer);
        const length = c.gtk_entry_buffer_get_bytes(buffer);
        return text[0..length :0];
    }

    pub fn setReadOnly(self: *TextField, readOnly: bool) void {
        c.gtk_editable_set_editable(@ptrCast(*c.GtkEditable, self.peer), @boolToInt(!readOnly));
        c.gtk_widget_set_can_focus(self.peer, @boolToInt(!readOnly));
    }

    pub fn _deinit(self: *const TextField) void {
        self.dup_text.deinit();
    }
};

pub const Canvas = struct {
    /// GtkEventBox which will take all of canvas's events
    peer: *c.GtkWidget,
    /// Actual GtkCanvas
    canvas: *c.GtkWidget,
    controller: *c.GtkEventController,

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
                c.pango_font_description_set_size(fontDescription, @floatToInt(c_int, @floor(font.size * @as(f64, c.PANGO_SCALE))));
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
                c.pango_layout_set_width(self._layout, if (self.wrap) |w| @floatToInt(c_int, @floor(w * @as(f64, c.PANGO_SCALE))) else -1);
                c.pango_layout_set_text(self._layout, str.ptr, @intCast(c_int, str.len));
                c.pango_layout_get_pixel_size(self._layout, &width, &height);

                return TextSize{ .width = @intCast(u32, width), .height = @intCast(u32, height) };
            }

            pub fn init() TextLayout {
                const context = c.gdk_pango_context_get().?;
                return TextLayout{ ._context = context, ._layout = c.pango_layout_new(context).? };
            }
        };

        pub fn setColorByte(self: *DrawContext, color: lib.Color) void {
            self.setColorRGBA(@intToFloat(f32, color.red) / 255.0, @intToFloat(f32, color.green) / 255.0, @intToFloat(f32, color.blue) / 255.0, @intToFloat(f32, color.alpha) / 255.0);
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
                    @intToFloat(f32, stop.color.red) / 255.0,
                    @intToFloat(f32, stop.color.green) / 255.0,
                    @intToFloat(f32, stop.color.blue) / 255.0,
                    @intToFloat(f32, stop.color.alpha) / 255.0,
                );
            }
            c.cairo_set_source(self.cr, pattern);
        }

        /// Add a rectangle to the current path
        pub fn rectangle(self: *DrawContext, x: i32, y: i32, w: u32, h: u32) void {
            c.cairo_rectangle(self.cr, @intToFloat(f64, x), @intToFloat(f64, y), @intToFloat(f64, w), @intToFloat(f64, h));
        }

        pub fn roundedRectangle(self: *DrawContext, x: i32, y: i32, w: u32, h: u32, corner_radius: f32) void {
            self.roundedRectangleEx(x, y, w, h, .{corner_radius} ** 4);
        }

        /// The radiuses are in order: top left, top right, bottom left, bottom right
        pub fn roundedRectangleEx(self: *DrawContext, x: i32, y: i32, w: u32, h: u32, corner_radiuses: [4]f32) void {
            var corners: [4]f32 = corner_radiuses;
            if (corners[0] + corners[1] > @intToFloat(f32, w)) {
                const left_prop = corners[0] / (corners[0] + corners[1]);
                corners[0] = left_prop * @intToFloat(f32, w);
                corners[1] = (1 - left_prop) * @intToFloat(f32, w);
            }
            if (corners[2] + corners[3] > @intToFloat(f32, w)) {
                const left_prop = corners[2] / (corners[2] + corners[3]);
                corners[2] = left_prop * @intToFloat(f32, w);
                corners[3] = (1 - left_prop) * @intToFloat(f32, w);
            }
            if (corners[0] + corners[2] > @intToFloat(f32, h)) {
                const top_prop = corners[0] / (corners[0] + corners[2]);
                corners[0] = top_prop * @intToFloat(f32, h);
                corners[2] = (1 - top_prop) * @intToFloat(f32, h);
            }
            if (corners[1] + corners[3] > @intToFloat(f32, h)) {
                const top_prop = corners[1] / (corners[1] + corners[3]);
                corners[1] = top_prop * @intToFloat(f32, h);
                corners[3] = (1 - top_prop) * @intToFloat(f32, h);
            }

            c.cairo_new_sub_path(self.cr);
            c.cairo_arc(
                self.cr,
                @intToFloat(f64, x + @intCast(i32, w)) - corners[1],
                @intToFloat(f64, y) + corners[1],
                corners[1],
                -std.math.pi / 2.0,
                0.0,
            );
            c.cairo_arc(
                self.cr,
                @intToFloat(f64, x + @intCast(i32, w)) - corners[3],
                @intToFloat(f64, y + @intCast(i32, h)) - corners[3],
                corners[3],
                0.0,
                std.math.pi / 2.0,
            );
            c.cairo_arc(
                self.cr,
                @intToFloat(f64, x) + corners[2],
                @intToFloat(f64, y + @intCast(i32, h)) - corners[2],
                corners[2],
                std.math.pi / 2.0,
                std.math.pi,
            );
            c.cairo_arc(
                self.cr,
                @intToFloat(f64, x) + corners[0],
                @intToFloat(f64, y) + corners[0],
                corners[0],
                std.math.pi,
                std.math.pi / 2.0 * 3.0,
            );
            c.cairo_close_path(self.cr);
        }

        pub fn ellipse(self: *DrawContext, x: i32, y: i32, w: u32, h: u32) void {
            if (w == h) { // if it is a circle, we can use something slightly faster
                c.cairo_arc(self.cr, @intToFloat(f64, x + @intCast(i32, w / 2)), @intToFloat(f64, y + @intCast(i32, w / 2)), @intToFloat(f64, w / 2), 0, 2 * std.math.pi);
                return;
            }
            var matrix: c.cairo_matrix_t = undefined;
            c.cairo_get_matrix(self.cr, &matrix);
            const scale = @intToFloat(f32, std.math.max(w, h)) / 2;
            c.cairo_scale(self.cr, @intToFloat(f32, w / 2) / scale, @intToFloat(f32, h / 2) / scale);
            c.cairo_arc(self.cr, @intToFloat(f32, w / 2), @intToFloat(f32, h / 2), scale, 0, 2 * std.math.pi);
            c.cairo_set_matrix(self.cr, &matrix);
        }

        pub fn clear(self: *DrawContext, x: u32, y: u32, w: u32, h: u32) void {
            if (self.widget) |widget| {
                const styleContext = c.gtk_widget_get_style_context(widget);
                c.gtk_render_background(styleContext, self.cr, @intToFloat(f64, x), @intToFloat(f64, y), @intToFloat(f64, w), @intToFloat(f64, h));
            }
        }

        pub fn text(self: *DrawContext, x: i32, y: i32, layout: TextLayout, str: []const u8) void {
            const pangoLayout = layout._layout;
            var inkRect: c.PangoRectangle = undefined;
            c.pango_layout_get_pixel_extents(pangoLayout, null, &inkRect);

            const dx = @intToFloat(f64, inkRect.x);
            const dy = @intToFloat(f64, inkRect.y);
            c.cairo_move_to(self.cr, @intToFloat(f64, x) + dx, @intToFloat(f64, y) + dy);
            c.pango_layout_set_width(pangoLayout, if (layout.wrap) |w| @floatToInt(c_int, @floor(w * @as(f64, c.PANGO_SCALE))) else -1);
            c.pango_layout_set_text(pangoLayout, str.ptr, @intCast(c_int, str.len));
            c.pango_layout_set_single_paragraph_mode(pangoLayout, 1); // used for coherence with other backends
            c.pango_cairo_update_layout(self.cr, pangoLayout);
            c.pango_cairo_show_layout(self.cr, pangoLayout);
        }

        pub fn line(self: *DrawContext, x1: i32, y1: i32, x2: i32, y2: i32) void {
            c.cairo_move_to(self.cr, @intToFloat(f64, x1), @intToFloat(f64, y1));
            c.cairo_line_to(self.cr, @intToFloat(f64, x2), @intToFloat(f64, y2));
            c.cairo_stroke(self.cr);
        }

        pub fn image(self: *DrawContext, x: i32, y: i32, w: u32, h: u32, data: lib.ImageData) void {
            c.cairo_save(self.cr);
            defer c.cairo_restore(self.cr);

            const width = @intToFloat(f64, data.width);
            const height = @intToFloat(f64, data.height);
            c.cairo_scale(self.cr, @intToFloat(f64, w) / width, @intToFloat(f64, h) / height);
            c.gdk_cairo_set_source_pixbuf(
                self.cr,
                data.peer.peer,
                @intToFloat(f64, x) / (@intToFloat(f64, w) / width),
                @intToFloat(f64, y) / (@intToFloat(f64, h) / height),
            );
            c.cairo_paint(self.cr);
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

    fn gtkCanvasDraw(peer: *c.GtkWidget, cr: *c.cairo_t, userdata: usize) callconv(.C) c_int {
        _ = userdata;
        const data = getEventUserData(peer);
        var dc = DrawContext{ .cr = cr, .widget = peer };

        if (data.class.drawHandler) |handler|
            handler(&dc, @ptrToInt(data));
        if (data.user.drawHandler) |handler|
            handler(&dc, data.userdata);
        return 0; // propagate the event further
    }

    fn gtkImKeyPress(key: *c.GtkEventControllerKey, keyval: c.guint, keycode: c.guint, state: *c.GdkModifierType, userdata: c.gpointer) callconv(.C) c.gboolean {
        _ = userdata;
        _ = keycode;
        _ = state;

        const peer = c.gtk_event_controller_get_widget(@ptrCast(*c.GtkEventController, key));
        const data = getEventUserData(peer);
        var finalKeyval = @intCast(u21, keyval);
        if (keyval >= 0xFF00 and keyval < 0xFF20) { // control characters
            finalKeyval = @intCast(u21, keyval) - 0xFF00;
        }
        if (finalKeyval >= 32768) return 0;

        var encodeBuffer: [4]u8 = undefined;
        const strLength = std.unicode.utf8Encode(@intCast(u21, finalKeyval), &encodeBuffer) catch unreachable;
        const str = encodeBuffer[0..strLength];

        if (data.class.keyTypeHandler) |handler| {
            handler(str, @ptrToInt(data));
        }
        if (data.user.keyTypeHandler) |handler| {
            handler(str, data.userdata);
            return 1;
        }
        return 1;
    }

    pub fn create() BackendError!Canvas {
        const canvas = c.gtk_drawing_area_new() orelse return BackendError.UnknownError;
        c.gtk_widget_show(canvas);
        _ = c.g_signal_connect_data(canvas, "draw", @ptrCast(c.GCallback, &gtkCanvasDraw), null, @as(c.GClosureNotify, null), 0);

        const peer = c.gtk_event_box_new() orelse return BackendError.UnknownError;
        c.gtk_widget_set_can_focus(peer, 1);
        c.gtk_widget_show(peer);
        c.gtk_container_add(@ptrCast(*c.GtkContainer, peer), canvas);
        try Canvas.setupEvents(peer);
        getEventUserData(peer).focusOnClick = true;
        // Copy event user data so that :draw can use `getEventUserData`
        Canvas.copyEventUserData(peer, canvas);

        const controller = c.gtk_event_controller_key_new(peer).?;
        _ = c.g_signal_connect_data(controller, "key-pressed", @ptrCast(c.GCallback, &gtkImKeyPress), null, null, c.G_CONNECT_AFTER);
        return Canvas{ .peer = peer, .canvas = canvas, .controller = controller };
    }
};

pub const Container = struct {
    peer: *c.GtkWidget,
    container: *c.GtkWidget,

    pub usingnamespace Events(Container);

    pub fn create() BackendError!Container {
        const layout = c.gtk_fixed_new() orelse return BackendError.UnknownError;
        c.gtk_widget_show(layout);

        // A custom component is used to bypass GTK's minimum size mechanism
        const wbin = wbin_new() orelse return BackendError.UnknownError;
        c.gtk_container_add(@ptrCast(*c.GtkContainer, wbin), layout);
        c.gtk_widget_show(wbin);
        try Container.setupEvents(wbin);
        return Container{ .peer = wbin, .container = layout };
    }

    pub fn add(self: *const Container, peer: PeerType) void {
        c.gtk_fixed_put(@ptrCast(*c.GtkFixed, self.container), peer, 0, 0);
    }

    pub fn remove(self: *const Container, peer: PeerType) void {
        // NOTE: the component might not be able to be added back
        // to fix this every peer type (Container, Button..) would have to hold a reference
        // that GTK knows about to their GtkWidget
        c.gtk_container_remove(@ptrCast(*c.GtkContainer, self.container), peer);
    }

    pub fn move(self: *const Container, peer: PeerType, x: u32, y: u32) void {
        c.gtk_fixed_move(@ptrCast(*c.GtkFixed, self.container), peer, @intCast(c_int, x), @intCast(c_int, y));
    }

    pub fn resize(self: *const Container, peer: PeerType, w: u32, h: u32) void {
        c.gtk_widget_set_size_request(peer, @intCast(c_int, w), @intCast(c_int, h));
        c.gtk_container_resize_children(@ptrCast(*c.GtkContainer, self.container));
    }
};

pub const TabContainer = struct {
    peer: *c.GtkWidget,

    pub usingnamespace Events(TabContainer);

    pub fn create() BackendError!TabContainer {
        const layout = c.gtk_notebook_new() orelse return BackendError.UnknownError;
        c.gtk_widget_show(layout);
        try TabContainer.setupEvents(layout);
        return TabContainer{ .peer = layout };
    }

    /// Returns the index of the newly added tab
    pub fn insert(self: *const TabContainer, position: usize, peer: PeerType) usize {
        return @intCast(usize, c.gtk_notebook_insert_page(@ptrCast(*c.GtkNotebook, self.peer), peer, null, @intCast(c_int, position)));
    }

    pub fn setLabel(self: *const TabContainer, position: usize, text: [:0]const u8) void {
        const child = c.gtk_notebook_get_nth_page(@ptrCast(*c.GtkNotebook, self.peer), @intCast(c_int, position));
        c.gtk_notebook_set_tab_label_text(@ptrCast(*c.GtkNotebook, self.peer), child, text.ptr);
    }

    /// Returns the number of tabs added to this tab container
    pub fn getTabsNumber(self: *const TabContainer) usize {
        return @intCast(usize, c.gtk_notebook_get_n_pages(@ptrCast(*c.GtkNotebook, self.peer)));
    }
};

pub const ScrollView = struct {
    peer: *c.GtkWidget,

    pub usingnamespace Events(ScrollView);

    pub fn create() BackendError!ScrollView {
        const scrolledWindow = c.gtk_scrolled_window_new(null, null) orelse return BackendError.UnknownError;
        c.gtk_widget_show(scrolledWindow);
        try ScrollView.setupEvents(scrolledWindow);
        return ScrollView{ .peer = scrolledWindow };
    }

    pub fn setChild(self: *ScrollView, peer: PeerType, _: *const lib.Widget) void {
        // TODO: remove old widget if there was one
        c.gtk_container_add(@ptrCast(*c.GtkContainer, self.peer), peer);
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
            const width = @intCast(c_int, self.data.width);
            const height = @intCast(c_int, self.data.height);

            c.g_object_unref(@ptrCast(*c.GObject, @alignCast(@alignOf(c.GObject), self.data.peer)));
            self.data.peer = c.gdk_pixbuf_get_from_surface(self._surface, 0, 0, width, height).?;
            c.cairo_destroy(self.draw_context.cr);
            c.cairo_surface_destroy(self._surface);
            self.data.mutex.unlock();
        }
    };

    // TODO: copy bytes to a new array
    pub fn from(width: usize, height: usize, stride: usize, cs: lib.Colorspace, bytes: []const u8) !ImageData {
        const pixbuf = c.gdk_pixbuf_new_from_data(bytes.ptr, c.GDK_COLORSPACE_RGB, @boolToInt(cs == .RGBA), 8, @intCast(c_int, width), @intCast(c_int, height), @intCast(c_int, stride), null, null) orelse return BackendError.UnknownError;

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

        c.g_object_unref(@ptrCast(*c.GObject, @alignCast(@alignOf(c.GObject), self.peer)));
    }
};

pub const NavigationSidebar = struct {
    peer: *c.GtkWidget,
    list: *c.GtkWidget,

    pub usingnamespace Events(NavigationSidebar);

    pub fn create() BackendError!NavigationSidebar {
        const listBox = c.gtk_list_box_new();
        c.gtk_widget_show(listBox);

        // A custom component is used to bypass GTK's minimum size mechanism
        const wbin = wbin_new() orelse return BackendError.UnknownError;
        c.gtk_container_add(@ptrCast(*c.GtkContainer, wbin), listBox);
        c.gtk_widget_show(wbin);
        try NavigationSidebar.setupEvents(wbin);

        var sidebar = NavigationSidebar{ .peer = wbin, .list = listBox };
        sidebar.append(undefined, "Test");
        return sidebar;
    }

    pub fn append(self: *NavigationSidebar, image: ImageData, label: [:0]const u8) void {
        const box = c.gtk_box_new(c.GTK_ORIENTATION_HORIZONTAL, 6);
        // TODO: append not prepend
        c.gtk_list_box_prepend(@ptrCast(*c.GtkListBox, self.list), box);

        _ = image;
        const icon = c.gtk_image_new_from_icon_name("dialog-warning-symbolic", c.GTK_ICON_SIZE_DIALOG);
        // TODO: create GtkImage from ImageData
        c.gtk_container_add(@ptrCast(*c.GtkContainer, box), icon);

        const label_gtk = c.gtk_label_new(label);
        c.gtk_container_add(@ptrCast(*c.GtkContainer, box), label_gtk);

        var context: *c.GtkStyleContext = c.gtk_widget_get_style_context(box);
        c.gtk_style_context_add_class(context, "activatable");
        c.gtk_style_context_add_class(context, "row");

        c.gtk_widget_show_all(box);
    }

    pub fn getPreferredSize_impl(self: *const NavigationSidebar) lib.Size {
        _ = self;
        return lib.Size.init(
            @intCast(u32, 200),
            @intCast(u32, 100),
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
    _ = c.gtk_main_iteration_do(@boolToInt(step == .Blocking));
    return activeWindows.load(.Acquire) != 0;
}
