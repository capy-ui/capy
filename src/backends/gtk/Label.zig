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
        .label = @as(*c.GtkLabel, @ptrCast(self.peer)),
        .text = self.nullTerminated.?,
    };
    _ = c.g_idle_add(setText_uiThread, runOpts);
}
