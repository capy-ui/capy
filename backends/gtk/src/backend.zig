const std = @import("std");
const c = @cImport({
    @cInclude("gtk/gtk.h");
});

const GtkError = error {
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

pub fn showNativeMessageDialog(msgType: MessageType, comptime fmt: []const u8, args: anytype) void {
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
    Click
};

const HandlerList = std.ArrayList(fn(data: usize) void);

pub const Button = struct {
    peer: *c.GtkWidget,
    data: usize = 0,
    clickHandler: ?fn(data: usize) void = null,
    registeredClick: bool = false,

    export fn clicked(peer: *c.GtkWidget, self: *Button) void {
        if (self.clickHandler) |handler| {
            handler(self.data);
        }
    }

    pub fn create() GtkError!Button {
        const button = c.gtk_button_new_with_label("") orelse return GtkError.UnknownError;
        c.gtk_widget_show(button);
        return Button {
            .peer = button
        };
    }

    pub fn setCallback(self: *Button, eType: EventType, cb: fn(data: usize) void) !void {
        switch (eType) {
            .Click => {
                if (!self.registeredClick) {
                    _ = c.g_signal_connect_data(self.peer, "clicked", @ptrCast(c.GCallback, Button.clicked),
                        self, @as(c.GClosureNotify, null), @intToEnum(c.GConnectFlags, 0));
                    self.registeredClick = true;
                }
                self.clickHandler = cb;
            }
        }
    }

    pub fn setLabel(self: *const Button, label: [:0]const u8) void {
        c.gtk_button_set_label(@ptrCast(*c.GtkButton, self.peer), label);
    }

    pub fn getLabel(self: *const Button) [:0]const u8 {
        const label = c.gtk_button_get_label(@ptrCast(*c.GtkButton, self.peer));
        return label[0..std.mem.lenZ(label) :0];
    }

};

pub const Label = struct {
    peer: *c.GtkWidget,
    data: usize = 0,
    clickHandler: ?fn(data: usize) void = null,
    registeredClick: bool = false,

    pub fn create() GtkError!Label {
        const label = c.gtk_label_new("") orelse return GtkError.UnknownError;
        c.gtk_widget_show(label);
        return Label {
            .peer = label
        };
    }

    pub fn setCallback(self: *Label, eType: EventType, cb: fn(data: usize) void) !void {
        switch (eType) {
            .Click => {
                if (!self.registeredClick) {
                    _ = c.g_signal_connect_data(self.peer, "clicked", @ptrCast(c.GCallback, clicked),
                        self, @as(c.GClosureNotify, null), @intToEnum(c.GConnectFlags, 0));
                    self.registeredClick = true;
                }
                self.clickHandler = cb;
            }
        }
    }

    pub fn setAlignment(self: *Label, alignment: f32) void {
        c.gtk_label_set_xalign(@ptrCast(*c.GtkLabel, self.peer), alignment);
    }

    pub fn setText(self: *Label, text: [:0]const u8) void {
        c.gtk_label_set_text(@ptrCast(*c.GtkLabel, self.peer), text);
    }

    pub fn getText(self: *Label) [:0]const u8 {
        const text = c.gtk_label_get_text(@ptrCast(*c.GtkLabel, self.peer)).?;
        return text[0..std.mem.lenZ(text) :0];
    }

};

pub const TextArea = struct {
    /// This is not actually the GtkTextView but this is the GtkScrolledWindow
    peer: *c.GtkWidget,
    textView: *c.GtkWidget,
    data: usize = 0,
    clickHandler: ?fn(data: usize) void = null,
    registeredClick: bool = false,

    pub fn create() GtkError!TextArea {
        const textArea = c.gtk_text_view_new() orelse return GtkError.UnknownError;
        const scrolledWindow = c.gtk_scrolled_window_new(null, null) orelse return GtkError.UnknownError;
        c.gtk_container_add(@ptrCast(*c.GtkContainer, scrolledWindow), textArea);
        c.gtk_widget_show(textArea);
        c.gtk_widget_show(scrolledWindow);
        return TextArea {
            .peer = scrolledWindow,
            .textView = textArea
        };
    }

    pub fn setCallback(self: *TextArea, eType: EventType, cb: fn(data: usize) void) !void {
        switch (eType) {
            .Click => {
                if (!self.registeredClick) {
                    _ = c.g_signal_connect_data(self.peer, "clicked", @ptrCast(c.GCallback, clicked),
                        self, @as(c.GClosureNotify, null), @intToEnum(c.GConnectFlags, 0));
                    self.registeredClick = true;
                }
                self.clickHandler = cb;
            }
        }
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
        return text[0..std.mem.lenZ(text) :0];
    }

};

pub const TextField = struct {
    peer: *c.GtkWidget,
    data: usize = 0,
    clickHandler: ?fn(data: usize) void = null,
    registeredClick: bool = false,

    pub fn create() GtkError!TextField {
        const textField = c.gtk_entry_new() orelse return GtkError.UnknownError;
        c.gtk_widget_show(textField);
        return TextField {
            .peer = textField
        };
    }

    pub fn setCallback(self: *TextField, eType: EventType, cb: fn(data: usize) void) !void {
        switch (eType) {
            .Click => {
                if (!self.registeredClick) {
                    _ = c.g_signal_connect_data(self.peer, "clicked", @ptrCast(c.GCallback, clicked),
                        self, @as(c.GClosureNotify, null), @intToEnum(c.GConnectFlags, 0));
                    self.registeredClick = true;
                }
                self.clickHandler = cb;
            }
        }
    }

    pub fn setText(self: *TextField, text: []const u8) void {
        const buffer = c.gtk_entry_get_buffer(@ptrCast(*c.GtkEntry, self.peer));
        c.gtk_entry_buffer_set_text(buffer, text.ptr, @intCast(c_int, text.len));
    }

    pub fn getText(self: *TextField) [:0]const u8 {
        const buffer = c.gtk_entry_get_buffer(@ptrCast(*c.GtkTextView, self.peer));
        const text = c.gtk_entry_buffer_get_text(buffer);
        return text[0..std.mem.lenZ(text) :0];
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
