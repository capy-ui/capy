const std = @import("std");
const c = @cImport({
    @cInclude("gtk/gtk.h");
});

const GtkError = std.mem.Allocator.Error || error {
    UnknownError,
    InitializationError
};

pub const Capabilities = .{
    .useEventLoop = true
};

pub const public = struct {

    pub fn main() !void {
        if (c.gtk_init_check(0, null) == 0) {
            return GtkError.InitializationError;
        }
        try @import("root").run();
    }

};

pub const MessageType = enum {
    Information,
    Warning,
    Error
};

pub fn showNativeMessageDialog(msgType: MessageType, comptime fmt: []const u8, args: anytype) callconv(.Inline) void {
    const msg = std.fmt.allocPrintZ(std.heap.page_allocator, fmt, args) catch {
        std.log.err("Could not launch message dialog, original text: " ++ fmt, args);
        return;
    };
    defer std.heap.page_allocator.free(msg);

    const cType = switch (msgType) {
        .Information => c.GtkMessageType.GTK_MESSAGE_INFO,
        .Warning => c.GtkMessageType.GTK_MESSAGE_WARNING,
        .Error => c.GtkMessageType.GTK_MESSAGE_ERROR
    };

    const dialog = c.gtk_message_dialog_new(
        null,
        c.GtkDialogFlags.GTK_DIALOG_DESTROY_WITH_PARENT,
        cType,
        c.GtkButtonsType.GTK_BUTTONS_CLOSE,
        msg
    );
    _ = c.gtk_dialog_run(@ptrCast(*c.GtkDialog, dialog));
    c.gtk_widget_destroy(dialog);
}

pub const PeerType = *c.GtkWidget;

pub const Window = struct {
    peer: *c.GtkWidget,

    pub fn create() GtkError!Window {
        const window = c.gtk_window_new(.GTK_WINDOW_TOPLEVEL) orelse return GtkError.UnknownError;
        const screen = c.gtk_window_get_screen(@ptrCast(*c.GtkWindow, window));
        //std.log.info("{d}", .{c.gdk_screen_get_resolution(screen)});
        return Window {
            .peer = window
        };
    }

    pub fn resize(self: *Window, width: c_int, height: c_int) void {
        c.gtk_window_resize(@ptrCast(*c.GtkWindow, self.peer), width, height);
    }

    pub fn setChild(self: *Window, peer: anytype) void {
        c.gtk_container_add(@ptrCast(*c.GtkContainer, self.peer), peer);
    }

    pub fn show(self: *Window) void {
        c.gtk_widget_show(self.peer);
    }

    pub fn close(self: *Window) void {
        c.gtk_window_close(@ptrCast(*c.GtkWindow, self.peer));
    }

};

pub const EventType = enum {
    Click,
    Draw,
    MouseButton,
    Scroll,
    TextChanged
};

pub const MouseButton = enum(c_uint) {
    Left = 1,
    Middle = 2,
    Right = 3,
    _
};

/// user data used for handling events
const EventUserData = struct {
    /// Only works for buttons
    clickHandler: ?fn(data: usize) void = null,
    mouseButtonHandler: ?fn(button: MouseButton, pressed: bool, x: f64, y: f64, data: usize) void = null,
    scrollHandler: ?fn(dx: f64, dy: f64, data: usize) void = null,
    /// Only works for canvas (althought technically it isn't required to)
    drawHandler: ?fn(ctx: Canvas.DrawContext, data: usize) void = null,
    changedTextHandler: ?fn(data: usize) void = null,
    userdata: usize = 0
};

fn getEventUserData(peer: *c.GtkWidget) callconv(.Inline) *EventUserData {
    return @ptrCast(*EventUserData, 
        @alignCast(@alignOf(EventUserData),
        c.g_object_get_data(@ptrCast(*c.GObject, peer), "eventUserData").?));
}

export fn gtkButtonPress(peer: *c.GtkWidget, event: *c.GdkEventButton, userdata: usize) void {
    const data = getEventUserData(peer);
    if (data.mouseButtonHandler) |handler| {
        const pressed = switch (event.type) {
            c.GdkEventType.GDK_BUTTON_PRESS => true,
            c.GdkEventType.GDK_BUTTON_RELEASE => false,
            // don't send released button in case of GDK_2BUTTON_PRESS, GDK_3BUTTON_PRESS, ...
            else => return
        };

        handler(@intToEnum(MouseButton, event.button), pressed, event.x, event.y, data.userdata);
    }
}

/// Temporary hack until translate-c can translate this struct
const GdkEventScroll = extern struct {
    type: c.GdkEventType,
    window: *c.GdkWindow,
    send_event: c.gint8,
    time: c.guint32,
    x: c.gdouble,
    y: c.gdouble,
    state: c.guint,
    direction: c.GdkScrollDirection,
    device: *c.GdkDevice,
    x_root: c.gdouble,
    y_root: c.gdouble,
    delta_x: c.gdouble,
    delta_y: c.gdouble,
    is_stop: c.guint
};

export fn gtkMouseScroll(peer: *c.GtkWidget, event: *GdkEventScroll, userdata: usize) void {
    const data = getEventUserData(peer);
    if (data.scrollHandler) |handler| {
        const dx: c.gdouble = switch (event.direction) {
            c.GdkScrollDirection.GDK_SCROLL_LEFT => -1,
            c.GdkScrollDirection.GDK_SCROLL_RIGHT => 1,
            else => event.delta_x
        };

        const dy: c.gdouble = switch (event.direction) {
            c.GdkScrollDirection.GDK_SCROLL_UP => -1,
            c.GdkScrollDirection.GDK_SCROLL_DOWN => 1,
            else => event.delta_y
        };

        handler(dx, dy, data.userdata);
    }
}

pub fn Events(comptime T: type) type {
    return struct {
        const Self = @This();

        pub fn setupEvents(widget: *c.GtkWidget) GtkError!void {
            _ = c.g_signal_connect_data(widget, "button-press-event", @ptrCast(c.GCallback, gtkButtonPress),
                null, @as(c.GClosureNotify, null), c.GConnectFlags.G_CONNECT_AFTER);
            _ = c.g_signal_connect_data(widget, "button-release-event", @ptrCast(c.GCallback, gtkButtonPress),
                null, @as(c.GClosureNotify, null), c.GConnectFlags.G_CONNECT_AFTER);
            _ = c.g_signal_connect_data(widget, "scroll-event", @ptrCast(c.GCallback, gtkMouseScroll),
                null, @as(c.GClosureNotify, null), c.GConnectFlags.G_CONNECT_AFTER);
            c.gtk_widget_add_events(widget,
                c.GDK_SCROLL_MASK | c.GDK_BUTTON_PRESS_MASK
                | c.GDK_BUTTON_RELEASE_MASK);

            const allocator = std.heap.page_allocator; // TODO: global allocator
            var data = try allocator.create(EventUserData);
            data.* = EventUserData {}; // ensure that it uses default values
            c.g_object_set_data(@ptrCast(*c.GObject, widget), "eventUserData", data);
        }

        pub fn setUserData(self: *T, data: anytype) callconv(.Inline) void {
            comptime {
                if (!std.meta.trait.isSingleItemPtr(@TypeOf(data))) {
                    @compileError(std.fmt.comptimePrint("Expected single item pointer, got {s}", .{@typeName(@TypeOf(data))}));
                }
            }

            getEventUserData(self.peer).userdata = @ptrToInt(data);
        }

        pub fn setCallback(self: *T, comptime eType: EventType, cb: anytype) callconv(.Inline) !void {
            const data = getEventUserData(self.peer);
            switch (eType) {
                .Click       => data.clickHandler       = cb,
                .Draw        => data.drawHandler        = cb,
                .MouseButton => data.mouseButtonHandler = cb,
                .Scroll      => data.scrollHandler      = cb,
                .TextChanged => data.changedTextHandler = cb,
            }
        }

        /// Requests a redraw
        pub fn requestDraw(self: *T) !void {
            c.gtk_widget_queue_draw(self.peer);
        }

    };
}

const HandlerList = std.ArrayList(fn(data: usize) void);

pub const Button = struct {
    peer: *c.GtkWidget,

    pub usingnamespace Events(Button);

    export fn gtkClicked(peer: *c.GtkWidget, userdata: usize) void {
        const data = getEventUserData(peer);

        if (data.clickHandler) |handler| {
            handler(data.userdata);
        }
    }

    pub fn create() GtkError!Button {
        const button = c.gtk_button_new_with_label("") orelse return GtkError.UnknownError;
        c.gtk_widget_show(button);
        try Button.setupEvents(button);
        _ = c.g_signal_connect_data(button, "clicked", @ptrCast(c.GCallback, gtkClicked),
            null, @as(c.GClosureNotify, null), @intToEnum(c.GConnectFlags, 0));
        return Button {
            .peer = button
        };
    }

    pub fn setLabel(self: *const Button, label: [:0]const u8) void {
        c.gtk_button_set_label(@ptrCast(*c.GtkButton, self.peer), label);
    }

    pub fn getLabel(self: *const Button) [:0]const u8 {
        const label = c.gtk_button_get_label(@ptrCast(*c.GtkButton, self.peer));
        return std.mem.spanZ(label);
    }

};

pub const Label = struct {
    peer: *c.GtkWidget,

    pub usingnamespace Events(Label);

    pub fn create() GtkError!Label {
        const label = c.gtk_label_new("") orelse return GtkError.UnknownError;
        c.gtk_widget_show(label);
        try Label.setupEvents(label);
        return Label {
            .peer = label
        };
    }

    pub fn setAlignment(self: *Label, alignment: f32) void {
        c.gtk_label_set_xalign(@ptrCast(*c.GtkLabel, self.peer), alignment);
    }

    pub fn setText(self: *Label, text: [:0]const u8) void {
        c.gtk_label_set_text(@ptrCast(*c.GtkLabel, self.peer), text);
    }

    pub fn getText(self: *Label) [:0]const u8 {
        const text = c.gtk_label_get_text(@ptrCast(*c.GtkLabel, self.peer)).?;
        return std.mem.spanZ(text);
    }

};

pub const TextArea = struct {
    /// This is not actually the GtkTextView but this is the GtkScrolledWindow
    peer: *c.GtkWidget,
    textView: *c.GtkWidget,

    pub usingnamespace Events(TextArea);

    pub fn create() GtkError!TextArea {
        const textArea = c.gtk_text_view_new() orelse return GtkError.UnknownError;
        const scrolledWindow = c.gtk_scrolled_window_new(null, null) orelse return GtkError.UnknownError;
        c.gtk_container_add(@ptrCast(*c.GtkContainer, scrolledWindow), textArea);
        c.gtk_widget_show(textArea);
        c.gtk_widget_show(scrolledWindow);
        try TextArea.setupEvents(textArea);
        return TextArea {
            .peer = scrolledWindow,
            .textView = textArea
        };
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
        return std.mem.spanZ(text);
    }

};

pub const TextField = struct {
    peer: *c.GtkWidget,

    pub usingnamespace Events(TextField);

    export fn gtkTextChanged(peer: *c.GtkWidget, userdata: usize) void {
        const data = getEventUserData(peer);
        if (data.changedTextHandler) |handler| {
            handler(data.userdata);
        }
    }

    pub fn create() GtkError!TextField {
        const textField = c.gtk_entry_new() orelse return GtkError.UnknownError;
        c.gtk_widget_show(textField);
        try setupEvents(textField);
        _ = c.g_signal_connect_data(textField, "changed", @ptrCast(c.GCallback, gtkTextChanged),
                null, @as(c.GClosureNotify, null), c.GConnectFlags.G_CONNECT_AFTER);
        return TextField {
            .peer = textField
        };
    }

    pub fn setText(self: *TextField, text: []const u8) void {
        const buffer = c.gtk_entry_get_buffer(@ptrCast(*c.GtkEntry, self.peer));
        c.gtk_entry_buffer_set_text(buffer, text.ptr, @intCast(c_int, text.len));
    }

    pub fn getText(self: *TextField) [:0]const u8 {
        const buffer = c.gtk_entry_get_buffer(@ptrCast(*c.GtkEntry, self.peer));
        const text = c.gtk_entry_buffer_get_text(buffer);
        const length = c.gtk_entry_buffer_get_length(buffer);
        return text[0..length :0];
    }

};

pub const Canvas = struct {
    peer: *c.GtkWidget,

    pub usingnamespace Events(Canvas);

    pub const DrawContext = struct {
        cr: *c.cairo_t,
        widget: *c.GtkWidget,

        pub const Font = struct {
            face: [:0]const u8,
            size: f64,
        };

        pub const TextLayout = struct {
            _layout: *c.PangoLayout,
            _context: *c.PangoContext,
            /// If null, no text wrapping is applied, otherwise the text is wrapping as if this was the maximum width.
            wrap: ?f64 = null,

            pub fn setFont(self: *TextLayout, font: Font) void {
                const fontDescription = c.pango_font_description_from_string(font.face) orelse unreachable;
                c.pango_font_description_set_size(fontDescription,
                    @floatToInt(c_int, @floor(font.size * @as(f64, c.PANGO_SCALE))));
                c.pango_layout_set_font_description(self._layout, fontDescription);
                c.pango_font_description_free(fontDescription);
            }

            pub fn deinit(self: *TextLayout) void {
                c.g_object_unref(self._layout);
                c.g_object_unref(self._context);
            }

            pub fn init() TextLayout {
                const context = c.gdk_pango_context_get().?;
                return TextLayout {
                    ._context = context,
                    ._layout = c.pango_layout_new(context).?
                };
            }
        };

        pub fn setColor(self: *const DrawContext, r: f64, g: f64, b: f64) void {
            self.setColorRGBA(r, g, b, 1);
        }

        pub fn setColorRGBA(self: *const DrawContext, r: f64, g: f64, b: f64, a: f64) void {
            const color = c.GdkRGBA { .red = r, .green = g, .blue = b, .alpha = a };
            c.gdk_cairo_set_source_rgba(self.cr, &color);
        }

        /// Add a rectangle to the current path
        pub fn rectangle(self: *const DrawContext, x: f64, y: f64, w: f64, h: f64) void {
            c.cairo_rectangle(self.cr, x, y, w, h);
        }

        pub fn clear(self: *const DrawContext, x: f64, y: f64, w: f64, h: f64) void {
            const styleContext = c.gtk_widget_get_style_context(self.widget);
            c.gtk_render_background(styleContext, self.cr, x, y, w, h);
        }

        pub fn text(self: *const DrawContext, x: f64, y: f64, layout: TextLayout, str: []const u8) void {
            const pangoLayout = layout._layout;
            var inkRect: c.PangoRectangle = undefined;
            c.pango_layout_get_pixel_extents(pangoLayout, null, &inkRect);

            const dx = @intToFloat(f64, inkRect.x);
            const dy = @intToFloat(f64, inkRect.y);
            c.cairo_move_to(self.cr, x + dx, y + dy);
            c.pango_layout_set_width(pangoLayout,
                if (layout.wrap) |w| @floatToInt(c_int, @floor(w*@as(f64, c.PANGO_SCALE)))
                else -1
            );
            c.pango_layout_set_text(pangoLayout, str.ptr, @intCast(c_int, str.len));
            c.pango_cairo_update_layout(self.cr, pangoLayout);
            c.pango_cairo_show_layout(self.cr, pangoLayout);
        }

        /// Fill the current path and reset the path.
        pub fn fill(self: *const DrawContext) void {
            c.cairo_fill(self.cr);
        }
    };

    export fn gtkCanvasDraw(peer: *c.GtkWidget, cr: *c.cairo_t, userdata: usize) c_int {
        const data = getEventUserData(peer);
        if (data.drawHandler) |handler| {
            handler(DrawContext { .cr = cr, .widget = peer }, data.userdata);
        }
        return 0; // propagate the event further
    }

    pub fn create() GtkError!Canvas {
        const canvas = c.gtk_drawing_area_new() orelse return GtkError.UnknownError;
        c.gtk_widget_show(canvas);
        try setupEvents(canvas);
        _ = c.g_signal_connect_data(canvas, "draw", @ptrCast(c.GCallback, gtkCanvasDraw),
                null, @as(c.GClosureNotify, null), @intToEnum(c.GConnectFlags, 0));
        return Canvas {
            .peer = canvas
        };
    }

};

pub const Stack = struct {
    peer: *c.GtkWidget,

    pub usingnamespace Events(Canvas);

    pub fn create() GtkError!Stack {
        const layout = c.gtk_overlay_new() orelse return GtkError.UnknownError;
        c.gtk_widget_show(layout);
        return Stack {
            .peer = layout
        };
    }

    pub fn add(self: *const Stack, peer: PeerType) void {
        c.gtk_overlay_add_overlay(@ptrCast(*c.GtkOverlay, self.peer), peer);
    }
};

pub const Row = struct {
    peer: *c.GtkWidget,
    expand: bool = false,

    pub usingnamespace Events(Canvas);

    pub fn create() GtkError!Row {
        const layout = c.gtk_box_new(c.GtkOrientation.GTK_ORIENTATION_HORIZONTAL, 0) orelse return GtkError.UnknownError;
        c.gtk_widget_show(layout);
        return Row {
            .peer = layout
        };
    }

    pub fn add(self: *const Row, peer: PeerType, fill: bool) void {
        c.gtk_box_pack_start(@ptrCast(*c.GtkBox, self.peer), peer,
            @boolToInt(self.expand or fill), @boolToInt(fill), 0);
    }
};

pub const Column = struct {
    peer: *c.GtkWidget,
    expand: bool = false,

    pub usingnamespace Events(Canvas);

    pub fn create() GtkError!Column {
        const layout = c.gtk_box_new(c.GtkOrientation.GTK_ORIENTATION_VERTICAL, 0) orelse return GtkError.UnknownError;
        c.gtk_widget_show(layout);
        return Column {
            .peer = layout
        };
    }

    pub fn add(self: *const Column, peer: PeerType, fill: bool) void {
        c.gtk_box_pack_start(@ptrCast(*c.GtkBox, self.peer), peer,
            @boolToInt(self.expand or fill), @boolToInt(fill), 0);
    }
};

pub fn run() void {
    c.gtk_main();
}
