const std = @import("std");
const trait = @import("../../trait.zig");
const c = @import("gtk.zig");
const lib = @import("../../capy.zig");

const shared = @import("../shared.zig");

pub const EventFunctions = @import("backend.zig").EventFunctions;
pub const EventType = shared.BackendEventType;
pub const BackendError = shared.BackendError;
pub const MouseButton = shared.MouseButton;
pub const PeerType = *c.GtkWidget;

/// user data used for handling events
pub const EventUserData = struct {
    user: EventFunctions = .{},
    class: EventFunctions = .{},
    userdata: usize = 0,
    classUserdata: usize = 0,
    peer: PeerType,
    focusOnClick: bool = false,
    actual_x: ?u31 = null,
    actual_y: ?u31 = null,
    actual_width: ?u31 = null,
    actual_height: ?u31 = null,
};

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

            const event_controller_motion = c.gtk_event_controller_motion_new();
            _ = c.g_signal_connect_data(event_controller_motion, "motion", @as(c.GCallback, @ptrCast(&gtkMouseMotion)), null, null, c.G_CONNECT_AFTER);
            c.gtk_widget_add_controller(widget, event_controller_motion);

            const event_controller_scroll = c.gtk_event_controller_scroll_new(c.GTK_EVENT_CONTROLLER_SCROLL_BOTH_AXES | c.GTK_EVENT_CONTROLLER_SCROLL_DISCRETE);
            _ = c.g_signal_connect_data(event_controller_scroll, "scroll", @as(c.GCallback, @ptrCast(&gtkMouseScroll)), null, null, c.G_CONNECT_AFTER);
            c.gtk_widget_add_controller(widget, event_controller_scroll);

            const event_controller_legacy = c.gtk_event_controller_legacy_new();
            _ = c.g_signal_connect_data(event_controller_legacy, "event", @as(c.GCallback, @ptrCast(&gtkButtonPress)), null, null, c.G_CONNECT_AFTER);
            c.gtk_widget_add_controller(widget, event_controller_legacy);

            const data = try lib.internal.lasting_allocator.create(EventUserData);
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

        fn getWindow(peer: *c.GtkWidget) *c.GtkWidget {
            var window = peer;
            while (c.gtk_widget_get_parent(window)) |parent| {
                window = parent;
            }
            return window;
        }

        fn gtkButtonPress(controller: *c.GtkEventControllerLegacy, event: *c.GdkEvent, _: usize) callconv(.C) c.gboolean {
            const event_type = c.gdk_event_get_event_type(event);
            if (event_type != c.GDK_BUTTON_PRESS and event_type != c.GDK_BUTTON_RELEASE)
                return 0;

            const peer = c.gtk_event_controller_get_widget(@ptrCast(controller));
            const window = getWindow(peer);
            const data = getEventUserData(peer);
            const pressed = switch (event_type) {
                c.GDK_BUTTON_PRESS => true,
                c.GDK_BUTTON_RELEASE => false,
                // don't send released button in case of GDK_2BUTTON_PRESS, GDK_3BUTTON_PRESS, ...
                else => return 0,
            };

            var x: f64 = undefined;
            std.debug.assert(c.gdk_event_get_axis(event, c.GDK_AXIS_X, &x) != 0);
            var y: f64 = undefined;
            std.debug.assert(c.gdk_event_get_axis(event, c.GDK_AXIS_Y, &y) != 0);

            const point: c.graphene_point_t = .{ .x = @floatCast(x), .y = @floatCast(y) };
            var out_point: c.graphene_point_t = undefined;
            _ = c.gtk_widget_compute_point(window, peer, &point, &out_point);

            if (x < 0 or y < 0) return 0;

            const button = switch (c.gdk_button_event_get_button(event)) {
                1 => MouseButton.Left,
                2 => MouseButton.Middle,
                3 => MouseButton.Right,
                else => @as(MouseButton, @enumFromInt(c.gdk_button_event_get_button(event))),
            };
            const mx = @as(i32, @intFromFloat(@floor(out_point.x)));
            const my = @as(i32, @intFromFloat(@floor(out_point.y)));

            if (data.class.mouseButtonHandler) |handler| {
                handler(button, pressed, mx, my, @intFromPtr(data));
            }
            if (data.user.mouseButtonHandler) |handler| {
                if (data.focusOnClick) {
                    _ = c.gtk_widget_grab_focus(peer);
                }
                handler(button, pressed, mx, my, data.userdata);
            }
            return 0;
        }

        fn gtkMouseMotion(controller: *c.GtkEventControllerMotion, x: f64, y: f64, _: usize) callconv(.C) c.gboolean {
            const peer = c.gtk_event_controller_get_widget(@ptrCast(controller));
            const data = getEventUserData(peer);

            const mx = @as(i32, @intFromFloat(@floor(x)));
            const my = @as(i32, @intFromFloat(@floor(y)));
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

        fn gtkMouseScroll(controller: *c.GtkEventControllerScroll, delta_x: f64, delta_y: f64, _: usize) callconv(.C) void {
            const peer = c.gtk_event_controller_get_widget(@ptrCast(controller));
            const data = getEventUserData(peer);
            const dx: f32 = @floatCast(delta_x);
            const dy: f32 = @floatCast(delta_y);

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
                if (!trait.isSingleItemPtr(@TypeOf(data))) {
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

        pub fn getX(self: *const T) c_int {
            return getXPosFromPeer(self.peer);
        }

        pub fn getY(self: *const T) c_int {
            return getYPosFromPeer(self.peer);
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
                @floatFromInt(requisition.width),
                @floatFromInt(requisition.height),
            );
        }
    };
}

pub inline fn getEventUserData(peer: *c.GtkWidget) *EventUserData {
    return @as(
        ?*EventUserData,
        @ptrCast(@alignCast(c.g_object_get_data(
            @as(*c.GObject, @ptrCast(peer)),
            "eventUserData",
        ))),
    ).?;
}

pub fn getXPosFromPeer(peer: PeerType) c_int {
    const data = getEventUserData(peer);
    return data.actual_x orelse 0;
}

pub fn getYPosFromPeer(peer: PeerType) c_int {
    const data = getEventUserData(peer);
    return data.actual_y orelse 0;
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
