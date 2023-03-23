const std = @import("std");
const capy = @import("capy");

pub usingnamespace capy.cross_platform;

pub fn main() !void {
    try capy.init();

    var window = try capy.Window.init();

    var monospace = capy.DataWrapper(bool).of(false);
    var text = capy.DataWrapper([]const u8).of("");

    var text_length = capy.DataWrapper(usize).of(undefined);
    try text_length.dependOn(.{&text}, &struct {
        fn callback(txt: []const u8) usize {
            return txt.len;
        }
    }.callback);

    var label_text = try capy.FormatDataWrapper(capy.internal.lasting_allocator, "Text length: {d}", .{&text_length});
    defer label_text.deinit();

    try window.set(capy.Column(.{ .spacing = 0 }, .{
        capy.Expanded(capy.TextArea(.{})
            .bind("monospace", &monospace)
            .bind("text", &text)),
        capy.Label(.{ .text = "TODO: cursor info" })
            .bind("text", label_text),
        // TODO: move into menu
        capy.CheckBox(.{ .label = "Monospaced" })
            .bind("checked", &monospace),
    }));

    // TODO: hotkeys for actions (Ctrl+S, Ctrl+C) plus corresponding Cmd+C on macOS
    window.setMenuBar(capy.MenuBar(.{
        capy.Menu(.{ .label = "File" }, .{
            capy.MenuItem(.{ .label = "New File" }),
            capy.MenuItem(.{ .label = "Open File.." }),
            capy.MenuItem(.{ .label = "Save" }),
            // TODO: capy.MenuSeperator ?
            capy.MenuItem(.{ .label = "Quit" }),
        }),
        capy.Menu(.{ .label = "Edit" }, .{
            capy.MenuItem(.{ .label = "Find" }),
            capy.MenuItem(.{ .label = "Copy" }),
            capy.MenuItem(.{ .label = "Paste" }),
        }),
        capy.Menu(.{ .label = "View" }, .{
            // TODO: togglemenuitem ?
            capy.MenuItem(.{ .label = "Monospace" }),
        }),
    }));

    window.setTitle("Notepad");
    window.resize(800, 600);
    window.show();

    capy.runEventLoop();
}
