const std = @import("std");
const c = @import("gtk.zig");
const lib = @import("../../main.zig");
const common = @import("common.zig");

const TextArea = @This();

/// This is not actually the GtkTextView but this is the GtkScrolledWindow
peer: *c.GtkWidget,
textView: *c.GtkWidget,

pub usingnamespace common.Events(TextArea);

fn gtkTextChanged(peer: *c.GtkWidget, userdata: usize) callconv(.C) void {
    _ = userdata;
    const data = common.getEventUserData(peer);
    if (data.user.changedTextHandler) |handler| {
        handler(data.userdata);
    }
}

pub fn create() common.BackendError!TextArea {
    const textArea = c.gtk_text_view_new() orelse return common.BackendError.UnknownError;
    const scrolledWindow = c.gtk_scrolled_window_new() orelse return common.BackendError.UnknownError;
    c.gtk_scrolled_window_set_child(@ptrCast(scrolledWindow), textArea);
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
