const std = @import("std");
const shared = @import("../shared.zig");
const lib = @import("../../main.zig");
const common = @import("common.zig");
// const c = @cImport({
// @cInclude("gtk/gtk.h");
// });
const c = @import("gtk.zig");

pub const EventFunctions = shared.EventFunctions(@This());

// Supported GTK version
pub const GTK_VERSION = std.SemanticVersion.Range{
    .min = std.SemanticVersion.parse("4.0.0") catch unreachable,
    .max = std.SemanticVersion.parse("4.15.0") catch unreachable,
};

pub const Capabilities = .{ .useEventLoop = true };

var hasInit: bool = false;

pub fn init() common.BackendError!void {
    if (!hasInit) {
        hasInit = true;
        if (c.gtk_init_check() == 0) {
            return common.BackendError.InitializationError;
        }
    }
}

pub fn showNativeMessageDialog(msgType: shared.MessageType, comptime fmt: []const u8, args: anytype) void {
    const msg = std.fmt.allocPrintZ(lib.internal.scratch_allocator, fmt, args) catch {
        std.log.err("Could not launch message dialog, original text: " ++ fmt, args);
        return;
    };
    defer lib.internal.scratch_allocator.free(msg);

    const cType = @as(c_uint, @intCast(switch (msgType) {
        .Information => c.GTK_MESSAGE_INFO,
        .Warning => c.GTK_MESSAGE_WARNING,
        .Error => c.GTK_MESSAGE_ERROR,
    }));

    if (comptime GTK_VERSION.min.order(.{ .major = 4, .minor = 10, .patch = 0 }) != .lt) {
        // GTK 4.10 deprecated MessageDialog and introduced AlertDialog
        const dialog = c.gtk_alert_dialog_new("%s", msg.ptr);
        c.gtk_alert_dialog_show(dialog, null);
        // TODO: wait for the dialog using a lock and the gtk_alert_dialog_choose method
    } else {
        const dialog = c.gtk_message_dialog_new(null, c.GTK_DIALOG_DESTROY_WITH_PARENT, cType, c.GTK_BUTTONS_CLOSE, msg.ptr);
        c.gtk_window_set_modal(@ptrCast(dialog), 1);
        c.gtk_widget_show(@ptrCast(dialog));
        // TODO: wait for the dialog using a lock and the ::response signal
        // c.gtk_widget_destroy(dialog);
    }
}

pub const PeerType = *c.GtkWidget;

// pub const Button = @import("../../flat/button.zig").FlatButton;
pub const Monitor = @import("Monitor.zig");
pub const Window = @import("Window.zig");
pub const Button = @import("Button.zig");
pub const CheckBox = @import("CheckBox.zig");
pub const Slider = @import("Slider.zig");
pub const Label = @import("Label.zig");
pub const TextArea = @import("TextArea.zig");
pub const TextField = @import("TextField.zig");
pub const Canvas = @import("Canvas.zig");
pub const Container = @import("Container.zig");
pub const TabContainer = @import("TabContainer.zig");
pub const ScrollView = @import("ScrollView.zig");
pub const ImageData = @import("ImageData.zig");
pub const NavigationSidebar = @import("NavigationSidebar.zig");
pub const AudioGenerator = @import("AudioGenerator.zig");

// downcasting to [*]u8 due to translate-c bugs which won't even accept
// pointer to an event.
extern fn gdk_event_new(type: c_int) [*]align(8) u8;
extern fn gtk_main_do_event(event: [*c]u8) void;

pub fn postEmptyEvent() void {
    // TODO: implement postEmptyEvent()
}

pub fn runOnUIThread() void {
    // TODO
}

pub fn runStep(step: shared.EventLoopStep) bool {
    const context = c.g_main_context_default();
    _ = c.g_main_context_iteration(context, @intFromBool(step == .Blocking));

    if (GTK_VERSION.min.order(.{ .major = 4, .minor = 0, .patch = 0 }) != .lt) {
        return c.g_list_model_get_n_items(c.gtk_window_get_toplevels()) > 0;
    } else {
        return Window.activeWindows.load(.acquire) != 0;
    }
}
