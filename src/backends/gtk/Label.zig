const std = @import("std");
const c = @import("gtk.zig");
const lib = @import("../../capy.zig");
const common = @import("common.zig");

const Label = @This();

peer: *c.GtkWidget,
/// Temporary value invalidated once setText_uiThread is called
nullTerminated: ?[:0]const u8 = null,

pub usingnamespace common.Events(Label);

pub fn create() common.BackendError!Label {
    const label = c.gtk_label_new("") orelse return common.BackendError.UnknownError;
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
    defer lib.internal.allocator.free(nullTerminated);
    defer lib.internal.allocator.destroy(runOpts);

    c.gtk_label_set_text(runOpts.label, runOpts.text);
    return c.G_SOURCE_REMOVE;
}

pub fn setText(self: *Label, text: []const u8) void {
    self.nullTerminated = lib.internal.allocator.dupeZ(u8, text) catch unreachable;

    // It must be run in UI thread otherwise set_text might crash randomly
    const runOpts = lib.internal.allocator.create(RunOpts) catch unreachable;
    runOpts.* = .{
        .label = @as(*c.GtkLabel, @ptrCast(self.peer)),
        .text = self.nullTerminated.?,
    };
    _ = c.g_idle_add(setText_uiThread, runOpts);
}

pub fn setFont(self: *Label, font: lib.Font) void {
    const attr_list = c.pango_attr_list_new().?;

    const font_description = c.pango_font_description_new().?;
    if (font.family) |family| {
        const copy = lib.internal.allocator.dupeZ(u8, family) catch @panic("OOM");
        // The NUL-terminated string is copied by GTK, so we can free it quickly
        defer lib.internal.allocator.free(copy);
        c.pango_font_description_set_family(font_description, copy);
    }
    if (font.size) |size| {
        c.pango_font_description_set_size(font_description, @intFromFloat(size * @as(f64, c.PANGO_SCALE)));
    }

    const attribute = c.pango_attr_font_desc_new(font_description);
    c.pango_attr_list_insert(attr_list, attribute);
    c.gtk_label_set_attributes(@ptrCast(self.peer), attr_list);
}
