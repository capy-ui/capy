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
    Draw
};

/// user data used for handling events
const EventUserData = struct {
    clickHandler: ?fn(data: usize) void = null,
    drawHandler: ?fn(ctx: Canvas.DrawContext, data: usize) void = null,
    userdata: usize = 0
};

fn getEventUserData(peer: *c.GtkWidget) callconv(.Inline) *EventUserData {
    return @ptrCast(*EventUserData, 
        @alignCast(@alignOf(EventUserData),
        c.g_object_get_data(@ptrCast(*c.GObject, peer), "eventUserData").?));
}

export fn gtkClicked(peer: *c.GtkWidget, userdata: usize) void {
    const data = getEventUserData(peer);

    if (data.clickHandler) |handler| {
        handler(data.userdata);
    }
}

pub fn Events(comptime T: type) type {
    return struct {
        const Self = @This();

        pub fn setupEvents(widget: *c.GtkWidget) GtkError!void {
            _ = c.g_signal_connect_data(widget, "clicked", @ptrCast(c.GCallback, gtkClicked),
                null, @as(c.GClosureNotify, null), @intToEnum(c.GConnectFlags, 0));

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
                .Click => data.clickHandler = cb,
                .Draw  => data.drawHandler  = cb
            }
        }

    };
}

const HandlerList = std.ArrayList(fn(data: usize) void);

pub const Button = struct {
    peer: *c.GtkWidget,

    pub usingnamespace Events(Button);

    pub fn create() GtkError!Button {
        const button = c.gtk_button_new_with_label("") orelse return GtkError.UnknownError;
        c.gtk_widget_show(button);
        try Button.setupEvents(button);
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

    pub fn create() GtkError!TextField {
        const textField = c.gtk_entry_new() orelse return GtkError.UnknownError;
        c.gtk_widget_show(textField);
        try setupEvents(textField);
        return TextField {
            .peer = textField
        };
    }

    pub fn setText(self: *TextField, text: []const u8) void {
        const buffer = c.gtk_entry_get_buffer(@ptrCast(*c.GtkEntry, self.peer));
        c.gtk_entry_buffer_set_text(buffer, text.ptr, @intCast(c_int, text.len));
    }

    pub fn getText(self: *TextField) [:0]const u8 {
        const buffer = c.gtk_entry_get_buffer(@ptrCast(*c.GtkTextView, self.peer));
        const text = c.gtk_entry_buffer_get_text(buffer);
        return std.mem.spanZ(text);
    }

};

pub const Canvas = struct {
    peer: *c.GtkWidget,

    pub usingnamespace Events(Canvas);

    pub const DrawContext = struct {
        cr: *c.cairo_t,

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

        /// Fill the current path and reset the path.
        pub fn fill(self: *const DrawContext) void {
            c.cairo_fill(self.cr);
        }
    };

    export fn gtkCanvasDraw(peer: *c.GtkWidget, cr: *c.cairo_t, userdata: usize) c_int {
        const data = getEventUserData(peer);
        if (data.drawHandler) |handler| {
            handler(DrawContext { .cr = cr }, data.userdata);
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
