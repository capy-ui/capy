const std = @import("std");
const shared = @import("../shared.zig");
const lib = @import("../../main.zig");
pub const c = @cImport({
    @cInclude("gtk/gtk.h");
});
const wbin_new = @import("windowbin.zig").wbin_new;

const EventType = shared.BackendEventType;
const BackendError = shared.BackendError;

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

pub const MessageType = enum { Information, Warning, Error };

pub fn showNativeMessageDialog(msgType: MessageType, comptime fmt: []const u8, args: anytype) void {
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

    const dialog = c.gtk_message_dialog_new(null, c.GTK_DIALOG_DESTROY_WITH_PARENT, cType, c.GTK_BUTTONS_CLOSE, msg);
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

    pub usingnamespace Events(Window);

    pub fn create() BackendError!Window {
        const window = c.gtk_window_new(c.GTK_WINDOW_TOPLEVEL) orelse return error.UnknownError;
        //const screen = c.gtk_window_get_screen(@ptrCast(*c.GtkWindow, window));
        //std.log.info("{d} dpi", .{c.gdk_screen_get_resolution(screen)});
        const wbin = wbin_new() orelse unreachable;
        c.gtk_container_add(@ptrCast(*c.GtkContainer, window), wbin);
        c.gtk_widget_show(wbin);

        _ = c.g_signal_connect_data(window, "hide", @ptrCast(c.GCallback, gtkWindowHidden), null, null, c.G_CONNECT_AFTER);
        randomWindow = window;
        return Window{ .peer = window, .wbin = wbin };
    }

    pub fn resize(self: *Window, width: c_int, height: c_int) void {
        c.gtk_window_resize(@ptrCast(*c.GtkWindow, self.peer), width, height);
    }

    pub fn setChild(self: *Window, peer: ?*c.GtkWidget) void {
        c.gtk_container_add(@ptrCast(*c.GtkContainer, self.wbin), peer);
    }

    pub fn show(self: *Window) void {
        c.gtk_widget_show(self.peer);
        _ = activeWindows.fetchAdd(1, .Release);
    }

    pub fn close(self: *Window) void {
        c.gtk_window_close(@ptrCast(*c.GtkWindow, self.peer));
    }
};

pub const MouseButton = enum(c_uint) {
    Left = 1,
    Middle = 2,
    Right = 3,
    _,

    /// Returns the ID of the pressed or released finger or null if it is a mouse.
    pub fn getFingerId(self: MouseButton) ?u8 {
        _ = self;
        return null;
    }
};

// zig fmt: off
const EventFunctions = struct {
    /// Only works for buttons
    clickHandler: ?fn (data: usize) void = null,
    mouseButtonHandler: ?fn (button: MouseButton, pressed: bool, x: u32, y: u32, data: usize) void = null,
    // TODO: Mouse object with pressed buttons and more data
    mouseMotionHandler: ?fn(x: u32, y: u32, data: usize) void = null,
    keyTypeHandler: ?fn (str: []const u8, data: usize) void = null,
    // TODO: dx and dy are in pixels, not in lines
    scrollHandler: ?fn (dx: f32, dy: f32, data: usize) void = null,
    resizeHandler: ?fn (width: u32, height: u32, data: usize) void = null,
    /// Only works for canvas (althought technically it isn't required to)
    drawHandler: ?fn (ctx: *Canvas.DrawContext, data: usize) void = null,
    changedTextHandler: ?fn (data: usize) void = null,
};

/// user data used for handling events
pub const EventUserData = struct {
    user: EventFunctions = .{},
    class: EventFunctions = .{},
    userdata: usize = 0,
    classUserdata: usize = 0,
    peer: PeerType,
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
            _ = c.g_signal_connect_data(widget, "button-press-event", @ptrCast(c.GCallback, gtkButtonPress), null, null, c.G_CONNECT_AFTER);
            _ = c.g_signal_connect_data(widget, "button-release-event", @ptrCast(c.GCallback, gtkButtonPress), null, null, c.G_CONNECT_AFTER);
            _ = c.g_signal_connect_data(widget, "motion-notify-event", @ptrCast(c.GCallback, gtkMouseMotion), null, null, c.G_CONNECT_AFTER);
            _ = c.g_signal_connect_data(widget, "scroll-event", @ptrCast(c.GCallback, gtkMouseScroll), null, null, c.G_CONNECT_AFTER);
            _ = c.g_signal_connect_data(widget, "size-allocate", @ptrCast(c.GCallback, gtkSizeAllocate), null, null, c.G_CONNECT_AFTER);
            if (T != Canvas)
                _ = c.g_signal_connect_data(widget, "key-press-event", @ptrCast(c.GCallback, gtkKeyPress), null, null, c.G_CONNECT_AFTER);
            c.gtk_widget_add_events(widget, c.GDK_SCROLL_MASK | c.GDK_BUTTON_PRESS_MASK | c.GDK_BUTTON_RELEASE_MASK | c.GDK_KEY_PRESS_MASK | c.GDK_POINTER_MOTION_MASK);

            var data = try lib.internal.lasting_allocator.create(EventUserData);
            data.* = EventUserData{ .peer = widget }; // ensure that it uses default values
            c.g_object_set_data(@ptrCast(*c.GObject, widget), "eventUserData", data);
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
            if (str.len != 0) {
                if (data.class.keyTypeHandler) |handler| {
                    handler(str, @ptrToInt(data));
                    if (data.user.keyTypeHandler == null) return 1;
                }
                if (data.user.keyTypeHandler) |handler| {
                    handler(str, data.userdata);
                    return 1;
                }
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

            const button = @intToEnum(MouseButton, event.button);
            const mx = @floatToInt(u32, @floor(event.x));
            const my = @floatToInt(u32, @floor(event.y));

            if (data.class.mouseButtonHandler) |handler| {
                handler(button, pressed, mx, my, @ptrToInt(data));
            }
            if (data.user.mouseButtonHandler) |handler| {
                c.gtk_widget_grab_focus(peer); // seems to be necessary for the canvas
                handler(button, pressed, mx, my, data.userdata);
            }
            return 0;
        }

        fn gtkMouseMotion(peer: *c.GtkWidget, event: *c.GdkEventMotion, userdata: usize) callconv(.C) c.gboolean {
            _ = userdata;
            const data = getEventUserData(peer);

            const mx = @floatToInt(u32, @floor(event.x));
            const my = @floatToInt(u32, @floor(event.y));
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
            std.log.info("peer = {} width = {d}", .{ self, self.getWidth() });
            const data = getEventUserData(self.peer);
            lib.internal.lasting_allocator.destroy(data);
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
    };
}

const HandlerList = std.ArrayList(fn (data: usize) void);

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
        const button = c.gtk_button_new_with_label("") orelse return error.UnknownError;
        c.gtk_widget_show(button);
        try Button.setupEvents(button);
        _ = c.g_signal_connect_data(button, "clicked", @ptrCast(c.GCallback, gtkClicked), null, @as(c.GClosureNotify, null), 0);
        return Button{ .peer = button };
    }

    pub fn setLabel(self: *const Button, label: [:0]const u8) void {
        c.gtk_button_set_label(@ptrCast(*c.GtkButton, self.peer), label);
    }

    pub fn getLabel(self: *const Button) [:0]const u8 {
        const label = c.gtk_button_get_label(@ptrCast(*c.GtkButton, self.peer));
        return std.mem.span(label);
    }
};

pub const Label = struct {
    peer: *c.GtkWidget,

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

    pub fn setText(self: *Label, text: [:0]const u8) void {
        c.gtk_label_set_text(@ptrCast(*c.GtkLabel, self.peer), text);
    }

    pub fn getText(self: *Label) [:0]const u8 {
        const text = c.gtk_label_get_text(@ptrCast(*c.GtkLabel, self.peer)).?;
        return std.mem.span(text);
    }
};

pub const TextArea = struct {
    /// This is not actually the GtkTextView but this is the GtkScrolledWindow
    peer: *c.GtkWidget,
    textView: *c.GtkWidget,

    pub usingnamespace Events(TextArea);

    pub fn create() BackendError!TextArea {
        const textArea = c.gtk_text_view_new() orelse return BackendError.UnknownError;
        const scrolledWindow = c.gtk_scrolled_window_new(null, null) orelse return BackendError.UnknownError;
        c.gtk_container_add(@ptrCast(*c.GtkContainer, scrolledWindow), textArea);
        c.gtk_widget_show(textArea);
        c.gtk_widget_show(scrolledWindow);
        try TextArea.setupEvents(textArea);
        return TextArea{ .peer = scrolledWindow, .textView = textArea };
    }

    pub fn setText(self: *TextArea, text: []const u8) void {
        const buffer = c.gtk_text_view_get_buffer(@ptrCast(*c.GtkTextView, self.textView));
        c.gtk_text_buffer_set_text(buffer, text.ptr, @intCast(c_int, text.len));
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
        _ = c.g_signal_connect_data(textField, "changed", @ptrCast(c.GCallback, gtkTextChanged), null, @as(c.GClosureNotify, null), c.G_CONNECT_AFTER);
        return TextField{ .peer = textField };
    }

    pub fn setText(self: *TextField, text: []const u8) void {
        var view = std.unicode.Utf8View.initUnchecked(text);
        var iterator = view.iterator();
        var numChars: c_int = 0;
        while (iterator.nextCodepoint() != null) {
            numChars += 1;
        }

        const buffer = c.gtk_entry_get_buffer(@ptrCast(*c.GtkEntry, self.peer));
        c.gtk_entry_buffer_set_text(buffer, text.ptr, numChars);
    }

    pub fn getText(self: *TextField) [:0]const u8 {
        const buffer = c.gtk_entry_get_buffer(@ptrCast(*c.GtkEntry, self.peer));
        const text = c.gtk_entry_buffer_get_text(buffer);
        const length = c.gtk_entry_buffer_get_bytes(buffer);
        return text[0..length :0];
    }
};

pub const Canvas = struct {
    peer: *c.GtkWidget,
    controller: *c.GtkEventController,

    pub usingnamespace Events(Canvas);

    pub const DrawContext = struct {
        cr: *c.cairo_t,
        widget: *c.GtkWidget,

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
                const fontDescription = c.pango_font_description_from_string(font.face) orelse unreachable;
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

        pub fn setColor(self: *DrawContext, r: f32, g: f32, b: f32) void {
            self.setColorRGBA(r, g, b, 1);
        }

        pub fn setColorRGBA(self: *DrawContext, r: f32, g: f32, b: f32, a: f32) void {
            const color = c.GdkRGBA{ .red = r, .green = g, .blue = b, .alpha = a };
            c.gdk_cairo_set_source_rgba(self.cr, &color);
        }

        /// Add a rectangle to the current path
        pub fn rectangle(self: *DrawContext, x: u32, y: u32, w: u32, h: u32) void {
            c.cairo_rectangle(self.cr, @intToFloat(f64, x), @intToFloat(f64, y), @intToFloat(f64, w), @intToFloat(f64, h));
        }

        pub fn ellipse(self: *DrawContext, x: u32, y: u32, w: f32, h: f32) void {
            if (w == h) { // if it is a circle, we can use something slightly faster
                c.cairo_arc(self.cr, @intToFloat(f64, x), @intToFloat(f64, y), w, 0, 2 * std.math.pi);
                return;
            }
            var matrix: c.cairo_matrix_t = undefined;
            c.cairo_get_matrix(self.cr, &matrix);
            const scale = w + h;
            c.cairo_scale(self.cr, w / scale, h / scale);
            c.cairo_arc(self.cr, @intToFloat(f64, x), @intToFloat(f64, y), scale, 0, 2 * std.math.pi);
            c.cairo_set_matrix(self.cr, &matrix);
        }

        pub fn clear(self: *DrawContext, x: u32, y: u32, w: u32, h: u32) void {
            const styleContext = c.gtk_widget_get_style_context(self.widget);
            c.gtk_render_background(styleContext, self.cr, @intToFloat(f64, x), @intToFloat(f64, y), @intToFloat(f64, w), @intToFloat(f64, h));
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

        pub fn line(self: *DrawContext, x1: u32, y1: u32, x2: u32, y2: u32) void {
            c.cairo_move_to(self.cr, @intToFloat(f64, x1), @intToFloat(f64, y1));
            c.cairo_line_to(self.cr, @intToFloat(f64, x2), @intToFloat(f64, y2));
            c.cairo_stroke(self.cr);
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
        _ = data;
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
            if (data.user.keyTypeHandler == null) return 1;
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
        c.gtk_widget_set_can_focus(canvas, 1);
        try Canvas.setupEvents(canvas);
        _ = c.g_signal_connect_data(canvas, "draw", @ptrCast(c.GCallback, gtkCanvasDraw), null, @as(c.GClosureNotify, null), 0);

        const controller = c.gtk_event_controller_key_new(canvas).?;
        _ = c.g_signal_connect_data(controller, "key-pressed", @ptrCast(c.GCallback, gtkImKeyPress), null, null, c.G_CONNECT_AFTER);
        return Canvas{ .peer = canvas, .controller = controller };
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

    pub fn move(self: *const Container, peer: PeerType, x: u32, y: u32) void {
        c.gtk_fixed_move(@ptrCast(*c.GtkFixed, self.container), peer, @intCast(c_int, x), @intCast(c_int, y));
    }

    pub fn resize(self: *const Container, peer: PeerType, w: u32, h: u32) void {
        _ = w;
        _ = h;
        _ = peer;
        _ = self;

        // temporary fix and should be replaced by a proper way to resize down
        //c.gtk_widget_set_size_request(peer, std.math.max(@intCast(c_int, w) - 5, 0), std.math.max(@intCast(c_int, h) - 5, 0));
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
        return c.gtk_notebook_insert_page(@ptrCast(*c.GtkNotebook, self.peer), peer, null, position);
    }

    pub fn setLabel(self: *const TabContainer, position: usize, text: [:0]const u8) void {
        const child = c.gtk_notebook_get_nth_page(@ptrCast(*c.GtkNotebook, self.peer), @intCast(c_int, position));
        c.gtk_notebook_set_tab_label_text(@ptrCast(*c.GtkNotebook, self.peer), child, text);
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

    pub fn setChild(self: *ScrollView, peer: PeerType) void {
        // TODO: remove old widget if there was one
        c.gtk_container_add(@ptrCast(*c.GtkContainer, self.peer), peer);
    }
};

pub const ImageData = struct {
    peer: *c.GdkPixbuf,

    pub fn from(width: usize, height: usize, stride: usize, cs: lib.Colorspace, bytes: []const u8) !ImageData {
        const pixbuf = c.gdk_pixbuf_new_from_data(bytes.ptr, c.GDK_COLORSPACE_RGB, @boolToInt(cs == .RGBA), 8, @intCast(c_int, width), @intCast(c_int, height), @intCast(c_int, stride), null, null) orelse return BackendError.UnknownError;

        return ImageData{ .peer = pixbuf };
    }
};

pub const Image = struct {
    peer: *c.GtkWidget,

    pub usingnamespace Events(Image);

    pub fn create() BackendError!Image {
        const image = c.gtk_image_new() orelse return BackendError.UnknownError;
        c.gtk_widget_show(image);
        try Image.setupEvents(image);
        return Image{ .peer = image };
    }

    pub fn setData(self: *Image, data: ImageData) void {
        c.gtk_image_set_from_pixbuf(@ptrCast(*c.GtkImage, self.peer), data.peer);
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
