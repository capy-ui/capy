const std = @import("std");
const c = @import("gtk.zig");
const lib = @import("../../capy.zig");
const common = @import("common.zig");

const TextField = @This();

peer: *c.GtkWidget,
// duplicate text to keep the same behaviour as other backends
dup_text: std.ArrayList(u8),

pub usingnamespace common.Events(TextField);

fn gtkTextChanged(peer: *c.GtkWidget, userdata: usize) callconv(.C) void {
    _ = userdata;
    const data = common.getEventUserData(peer);
    if (data.user.changedTextHandler) |handler| {
        handler(data.userdata);
    }
}

pub fn create() common.BackendError!TextField {
    const textField = c.gtk_entry_new() orelse return common.BackendError.UnknownError;
    try TextField.setupEvents(textField);
    _ = c.g_signal_connect_data(textField, "changed", @as(c.GCallback, @ptrCast(&gtkTextChanged)), null, @as(c.GClosureNotify, null), c.G_CONNECT_AFTER);
    return TextField{ .peer = textField, .dup_text = std.ArrayList(u8).init(lib.internal.lasting_allocator) };
}

pub fn setText(self: *TextField, text: []const u8) void {
    var view = std.unicode.Utf8View.init(text) catch return;
    var iterator = view.iterator();
    var numChars: c_int = 0;
    while (iterator.nextCodepoint() != null) {
        numChars += 1;
    }

    const buffer = c.gtk_entry_get_buffer(@as(*c.GtkEntry, @ptrCast(self.peer)));
    self.dup_text.clearRetainingCapacity();
    self.dup_text.appendSlice(text) catch return;
    self.dup_text.append(0) catch return; // add sentinel so it becomes a NUL-terminated UTF-8 string

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
}

pub fn _deinit(self: *const TextField) void {
    self.dup_text.deinit();
}
