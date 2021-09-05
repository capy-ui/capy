const std = @import("std");
pub const c = @cImport({
    @cInclude("gtk/gtk.h");
});
const wbin_new = @import("windowbin.zig").wbin_new;

const GtkError = std.mem.Allocator.Error || error {
    UnknownError,
    InitializationError
};

pub const Capabilities = .{
    .useEventLoop = true
};

pub const public = struct {

    pub fn main() !void {
        try init();
        try @import("root").run();
    }

};

pub fn init() !void {
    if (c.gtk_init_check(0, null) == 0) {
        return GtkError.InitializationError;
    }
}

pub const MessageType = enum {
    Information,
    Warning,
    Error
};

pub fn showNativeMessageDialog(msgType: MessageType, comptime fmt: []const u8, args: anytype) void {
    const msg = std.fmt.allocPrintZ(std.heap.page_allocator, fmt, args) catch {
        std.log.err("Could not launch message dialog, original text: " ++ fmt, args);
        return;
    };
    defer std.heap.page_allocator.free(msg);

    const cType = @intCast(c_uint, switch (msgType) {
        .Information => c.GTK_MESSAGE_INFO,
        .Warning => c.GTK_MESSAGE_WARNING,
        .Error => c.GTK_MESSAGE_ERROR
    });

    const dialog = c.gtk_message_dialog_new(
        null,
        c.GTK_DIALOG_DESTROY_WITH_PARENT,
        cType,
        c.GTK_BUTTONS_CLOSE,
        msg
    );
    _ = c.gtk_dialog_run(@ptrCast(*c.GtkDialog, dialog));
    c.gtk_widget_destroy(dialog);
}

pub const PeerType = *c.GtkWidget;

pub const Window = struct {
    peer: *c.GtkWidget,
    wbin: *c.GtkWidget,

    pub fn create() GtkError!Window {
        const window = c.gtk_window_new(c.GTK_WINDOW_TOPLEVEL) orelse return GtkError.UnknownError;
        //const screen = c.gtk_window_get_screen(@ptrCast(*c.GtkWindow, window));
        //std.log.info("{d}", .{c.gdk_screen_get_resolution(screen)});
        const wbin = wbin_new() orelse unreachable;
        c.gtk_container_add(@ptrCast(*c.GtkContainer, window), wbin);
        c.gtk_widget_show(wbin);
        return Window {
            .peer = window,
            .wbin = wbin
        };
    }

    pub fn resize(self: *Window, width: c_int, height: c_int) void {
        c.gtk_window_resize(@ptrCast(*c.GtkWindow, self.peer), width, height);
    }

    pub fn setChild(self: *Window, peer: anytype) void {
        c.gtk_container_add(@ptrCast(*c.GtkContainer, self.wbin), peer);
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
    TextChanged,
    Resize
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
    resizeHandler: ?fn(width: u32, height: u32, data: usize) void = null,
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

export fn gtkSizeAllocate(peer: *c.GtkWidget, allocation: *c.GdkRectangle, userdata: usize) void {
    _ = userdata;
    const data = getEventUserData(peer);
    if (data.resizeHandler) |handler| {
        handler(@intCast(u32, allocation.width), @intCast(u32, allocation.height), data.userdata);
    }
}

export fn gtkButtonPress(peer: *c.GtkWidget, event: *c.GdkEventButton, userdata: usize) void {
    _ = userdata;
    const data = getEventUserData(peer);
    if (data.mouseButtonHandler) |handler| {
        const pressed = switch (event.type) {
            c.GDK_BUTTON_PRESS => true,
            c.GDK_BUTTON_RELEASE => false,
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
    _ = userdata;
    const data = getEventUserData(peer);
    if (data.scrollHandler) |handler| {
        const dx: c.gdouble = switch (event.direction) {
            c.GDK_SCROLL_LEFT => -1,
            c.GDK_SCROLL_RIGHT => 1,
            else => event.delta_x
        };

        const dy: c.gdouble = switch (event.direction) {
            c.GDK_SCROLL_UP => -1,
            c.GDK_SCROLL_DOWN => 1,
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
                null, @as(c.GClosureNotify, null), c.G_CONNECT_AFTER);
            _ = c.g_signal_connect_data(widget, "button-release-event", @ptrCast(c.GCallback, gtkButtonPress),
                null, @as(c.GClosureNotify, null), c.G_CONNECT_AFTER);
            _ = c.g_signal_connect_data(widget, "scroll-event", @ptrCast(c.GCallback, gtkMouseScroll),
                null, @as(c.GClosureNotify, null), c.G_CONNECT_AFTER);
            _ = c.g_signal_connect_data(widget, "size-allocate", @ptrCast(c.GCallback, gtkSizeAllocate),
                null, @as(c.GClosureNotify, null), c.G_CONNECT_AFTER);
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
                .Resize      => data.resizeHandler      = cb
            }
        }

        /// Requests a redraw
        pub fn requestDraw(self: *T) !void {
            c.gtk_widget_queue_draw(self.peer);
        }

        pub fn getWidth(self: *const T) c_int {
            return c.gtk_widget_get_allocated_width(self.peer);
        }

        pub fn getHeight(self: *const T) c_int {
            return c.gtk_widget_get_allocated_height(self.peer);
        }

    };
}

const HandlerList = std.ArrayList(fn(data: usize) void);

pub const Button = struct {
    peer: *c.GtkWidget,

    pub usingnamespace Events(Button);

    export fn gtkClicked(peer: *c.GtkWidget, userdata: usize) void {
        _ = userdata;
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
            null, @as(c.GClosureNotify, null), 0);
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
        _ = userdata;
        const data = getEventUserData(peer);
        if (data.changedTextHandler) |handler| {
            handler(data.userdata);
        }
    }

    pub fn create() GtkError!TextField {
        const textField = c.gtk_entry_new() orelse return GtkError.UnknownError;
        c.gtk_widget_show(textField);
        try TextField.setupEvents(textField);
        _ = c.g_signal_connect_data(textField, "changed", @ptrCast(c.GCallback, gtkTextChanged),
                null, @as(c.GClosureNotify, null), c.G_CONNECT_AFTER);
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

        pub const TextSize = struct {
            width: u32,
            height: u32
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

            pub fn getTextSize(self: *TextLayout, str: []const u8) TextSize {
                var width: c_int = undefined;
                var height: c_int = undefined;
                c.pango_layout_set_text(self._layout, str.ptr, @intCast(c_int, str.len));
                c.pango_layout_get_pixel_size(self._layout, &width, &height);

                return TextSize {
                    .width = @intCast(u32, width),
                    .height = @intCast(u32, height)
                };
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
        pub fn rectangle(self: *const DrawContext, x: u32, y: u32, w: u32, h: u32) void {
            c.cairo_rectangle(self.cr, @intToFloat(f64, x), @intToFloat(f64, y),
                @intToFloat(f64, w), @intToFloat(f64, h));
        }

        pub fn clear(self: *const DrawContext, x: u32, y: u32, w: u32, h: u32) void {
            const styleContext = c.gtk_widget_get_style_context(self.widget);
            c.gtk_render_background(styleContext, self.cr, @intToFloat(f64, x), @intToFloat(f64, y),
                @intToFloat(f64, w), @intToFloat(f64, h));
        }

        pub fn text(self: *const DrawContext, x: u32, y: u32, layout: TextLayout, str: []const u8) void {
            const pangoLayout = layout._layout;
            var inkRect: c.PangoRectangle = undefined;
            c.pango_layout_get_pixel_extents(pangoLayout, null, &inkRect);

            const dx = @intToFloat(f64, inkRect.x);
            const dy = @intToFloat(f64, inkRect.y);
            c.cairo_move_to(self.cr, @intToFloat(f64, x) + dx, @intToFloat(f64, y) + dy);
            c.pango_layout_set_width(pangoLayout,
                if (layout.wrap) |w| @floatToInt(c_int, @floor(w*@as(f64, c.PANGO_SCALE)))
                else -1
            );
            c.pango_layout_set_text(pangoLayout, str.ptr, @intCast(c_int, str.len));
            c.pango_layout_set_single_paragraph_mode(pangoLayout, 1); // used for coherence with other backends
            c.pango_cairo_update_layout(self.cr, pangoLayout);
            c.pango_cairo_show_layout(self.cr, pangoLayout);
        }

        pub fn line(self: *const DrawContext, x1: i32, y1: i32, x2: i32, y2: i32) void {
            c.cairo_move_to(self.cr, @intToFloat(f64, x1), @intToFloat(f64, y1));
            c.cairo_line_to(self.cr, @intToFloat(f64, x2), @intToFloat(f64, y2));
        }

        /// Stroke the current path and reset the path.
        pub fn stroke(self: *const DrawContext) void {
            c.cairo_stroke(self.cr);
        }

        /// Fill the current path and reset the path.
        pub fn fill(self: *const DrawContext) void {
            c.cairo_fill(self.cr);
        }
    };

    export fn gtkCanvasDraw(peer: *c.GtkWidget, cr: *c.cairo_t, userdata: usize) c_int {
        _ = userdata;
        const data = getEventUserData(peer);
        if (data.drawHandler) |handler| {
            handler(DrawContext { .cr = cr, .widget = peer }, data.userdata);
        }
        return 0; // propagate the event further
    }

    pub fn create() GtkError!Canvas {
        const canvas = c.gtk_drawing_area_new() orelse return GtkError.UnknownError;
        c.gtk_widget_show(canvas);
        try Canvas.setupEvents(canvas);
        _ = c.g_signal_connect_data(canvas, "draw", @ptrCast(c.GCallback, gtkCanvasDraw),
                null, @as(c.GClosureNotify, null), 0);
        return Canvas {
            .peer = canvas
        };
    }

};

pub const Container = struct {
    peer: *c.GtkWidget,

    pub usingnamespace Events(Container);

    pub fn create() GtkError!Container {
        const layout = c.gtk_fixed_new() orelse return GtkError.UnknownError;
        c.gtk_widget_show(layout);
        try Container.setupEvents(layout);
        return Container {
            .peer = layout
        };
    }

    pub fn add(self: *const Container, peer: PeerType) void {
        c.gtk_fixed_put(@ptrCast(*c.GtkFixed, self.peer), peer, 0, 0);
    }

    pub fn move(self: *const Container, peer: PeerType, x: u32, y: u32) void {
        c.gtk_fixed_move(@ptrCast(*c.GtkFixed, self.peer), peer, @intCast(c_int, x), @intCast(c_int, y));
    }

    pub fn resize(self: *const Container, peer: PeerType, w: u32, h: u32) void {
        _ = w; _ = h;
        _ = peer;
        _ = self;

        // temporary fix and should be replaced by a proper way to resize down
        c.gtk_widget_set_size_request(peer, @intCast(c_int, w) - 5, @intCast(c_int, h) - 5);
        c.gtk_container_resize_children(@ptrCast(*c.GtkContainer, self.peer));
    }
};

pub fn run() void {
    c.gtk_main();
}
