const std = @import("std");
const shared = @import("../shared.zig");
const lib = @import("../../capy.zig");
const common = @import("common.zig");
// const c = @cImport({
// @cInclude("gtk/gtk.h");
// });
const c = @import("gtk.zig");

pub const EventFunctions = shared.EventFunctions(@This());
pub const EventUserData = common.EventUserData;
pub const getEventUserData = common.getEventUserData;

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
    const msg = std.fmt.allocPrintSentinel(lib.internal.allocator, fmt, args, 0) catch {
        std.log.err("Could not launch message dialog, original text: " ++ fmt, args);
        return;
    };
    defer lib.internal.allocator.free(msg);

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

/// Opens a native file/directory selection dialog.
/// Returns the selected path, or null if cancelled.
/// Caller owns returned memory (allocated with lib.internal.allocator).
pub fn openFileDialog(options: shared.FileDialogOptions) ?[:0]const u8 {
    if (comptime GTK_VERSION.min.order(.{ .major = 4, .minor = 10, .patch = 0 }) != .lt) {
        // Modern GTK 4.10+ API: GtkFileDialog
        const dialog = c.gtk_file_dialog_new() orelse return null;
        c.gtk_file_dialog_set_title(dialog, options.title.ptr);
        c.gtk_file_dialog_set_modal(dialog, 1);

        // Set file filters
        if (!options.select_directories and options.filters.len > 0) {
            // Create a GListStore of GtkFileFilter
            const store = c.g_list_store_new(c.gtk_file_filter_get_type());
            for (options.filters) |f| {
                const filter = c.gtk_file_filter_new();
                c.gtk_file_filter_set_name(filter, f.name.ptr);
                // Parse semicolon-separated patterns
                var iter = std.mem.splitScalar(u8, std.mem.sliceTo(f.pattern, 0), ';');
                while (iter.next()) |pat| {
                    if (pat.len > 0) {
                        // Need null-terminated pattern
                        const pat_z = lib.internal.allocator.allocSentinel(u8, pat.len, 0) catch continue;
                        defer lib.internal.allocator.free(pat_z);
                        @memcpy(pat_z, pat);
                        c.gtk_file_filter_add_pattern(filter, pat_z.ptr);
                    }
                }
                c.g_list_store_append(store, @ptrCast(filter));
            }
            c.gtk_file_dialog_set_filters(dialog, @ptrCast(store));
        }

        // Use synchronous approach with GMainLoop
        const ResultData = struct {
            path: ?[:0]const u8 = null,
            done: bool = false,
        };
        var result_data = ResultData{};

        const callback = struct {
            fn cb(source: ?*c.GObject, async_result: ?*c.GAsyncResult, user_data: ?*anyopaque) callconv(.c) void {
                const data: *ResultData = @ptrCast(@alignCast(user_data));
                var err: ?*c.GError = null;
                const gfile = if (@TypeOf(source) != void)
                    c.gtk_file_dialog_open_finish(@ptrCast(source), async_result, &err)
                else
                    null;
                if (gfile) |file| {
                    const cpath = c.g_file_get_path(file);
                    if (cpath) |p| {
                        const len = std.mem.len(p);
                        const owned = lib.internal.allocator.allocSentinel(u8, len, 0) catch {
                            c.g_free(p);
                            data.done = true;
                            return;
                        };
                        @memcpy(owned, p[0..len]);
                        data.path = owned;
                        c.g_free(p);
                    }
                    c.g_object_unref(@ptrCast(file));
                }
                data.done = true;
            }

            fn cb_folder(source: ?*c.GObject, async_result: ?*c.GAsyncResult, user_data: ?*anyopaque) callconv(.c) void {
                const data: *ResultData = @ptrCast(@alignCast(user_data));
                var err: ?*c.GError = null;
                const gfile = if (@TypeOf(source) != void)
                    c.gtk_file_dialog_select_folder_finish(@ptrCast(source), async_result, &err)
                else
                    null;
                if (gfile) |file| {
                    const cpath = c.g_file_get_path(file);
                    if (cpath) |p| {
                        const len = std.mem.len(p);
                        const owned = lib.internal.allocator.allocSentinel(u8, len, 0) catch {
                            c.g_free(p);
                            data.done = true;
                            return;
                        };
                        @memcpy(owned, p[0..len]);
                        data.path = owned;
                        c.g_free(p);
                    }
                    c.g_object_unref(@ptrCast(file));
                }
                data.done = true;
            }
        };

        if (options.select_directories) {
            c.gtk_file_dialog_select_folder(dialog, null, null, callback.cb_folder, @ptrCast(&result_data));
        } else {
            c.gtk_file_dialog_open(dialog, null, null, callback.cb, @ptrCast(&result_data));
        }

        // Spin the GTK main loop until dialog completes
        while (!result_data.done) {
            _ = c.g_main_context_iteration(null, 1);
        }

        return result_data.path;
    } else {
        // Older GTK < 4.10: Use GtkFileChooserNative
        const action: c_uint = if (options.select_directories)
            c.GTK_FILE_CHOOSER_ACTION_SELECT_FOLDER
        else
            c.GTK_FILE_CHOOSER_ACTION_OPEN;

        const dialog = c.gtk_file_chooser_native_new(
            options.title.ptr,
            null,
            action,
            "Open",
            "Cancel",
        ) orelse return null;

        // Add filters
        if (!options.select_directories and options.filters.len > 0) {
            for (options.filters) |f| {
                const filter = c.gtk_file_filter_new();
                c.gtk_file_filter_set_name(filter, f.name.ptr);
                var iter = std.mem.splitScalar(u8, std.mem.sliceTo(f.pattern, 0), ';');
                while (iter.next()) |pat| {
                    if (pat.len > 0) {
                        const pat_z = lib.internal.allocator.allocSentinel(u8, pat.len, 0) catch continue;
                        defer lib.internal.allocator.free(pat_z);
                        @memcpy(pat_z, pat);
                        c.gtk_file_filter_add_pattern(filter, pat_z.ptr);
                    }
                }
                c.gtk_file_chooser_add_filter(@ptrCast(dialog), filter);
            }
        }

        // Show and run synchronously
        const response = c.gtk_native_dialog_run(@ptrCast(dialog));
        defer c.g_object_unref(@ptrCast(dialog));

        if (response == c.GTK_RESPONSE_ACCEPT) {
            const gfile = c.gtk_file_chooser_get_file(@ptrCast(dialog));
            if (gfile) |file| {
                defer c.g_object_unref(@ptrCast(file));
                const cpath = c.g_file_get_path(file);
                if (cpath) |p| {
                    defer c.g_free(p);
                    const len = std.mem.len(p);
                    const owned = lib.internal.allocator.allocSentinel(u8, len, 0) catch return null;
                    @memcpy(owned, p[0..len]);
                    return owned;
                }
            }
        }

        return null;
    }
}

/// Returns true if the system is currently in dark mode.
pub fn isDarkMode() bool {
    const settings = c.gtk_settings_get_default() orelse return false;
    var dark: c.gboolean = 0;
    c.g_object_get(
        @as(*c.GObject, @ptrCast(settings)),
        "gtk-application-prefer-dark-theme",
        &dark,
        @as(?*anyopaque, null),
    );
    if (dark != 0) return true;

    // Also check the theme name for "dark" (case-insensitive)
    var theme_name: ?[*:0]const u8 = null;
    c.g_object_get(
        @as(*c.GObject, @ptrCast(settings)),
        "gtk-theme-name",
        &theme_name,
        @as(?*anyopaque, null),
    );
    if (theme_name) |name| {
        // Simple case-insensitive substring search for "dark"
        var i: usize = 0;
        const name_slice = std.mem.span(name);
        while (i + 4 <= name_slice.len) : (i += 1) {
            const ch = [4]u8{
                std.ascii.toLower(name_slice[i]),
                std.ascii.toLower(name_slice[i + 1]),
                std.ascii.toLower(name_slice[i + 2]),
                std.ascii.toLower(name_slice[i + 3]),
            };
            if (std.mem.eql(u8, &ch, "dark")) return true;
        }
    }
    return false;
}

pub const PeerType = *c.GtkWidget;

// pub const Button = @import("../../flat/button.zig").FlatButton;
pub const Monitor = @import("Monitor.zig");
pub const Window = @import("Window.zig");
pub const Button = @import("Button.zig");
pub const CheckBox = @import("CheckBox.zig");
pub const RadioButton = @import("RadioButton.zig");
pub const Dropdown = @import("Dropdown.zig");
pub const Table = @import("Table.zig");
pub const Slider = @import("Slider.zig");
pub const ProgressBar = @import("ProgressBar.zig");
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

    return c.g_list_model_get_n_items(c.gtk_window_get_toplevels()) > 0;
}
