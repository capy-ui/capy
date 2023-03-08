const std = @import("std");
const capy = @import("capy");

pub usingnamespace capy.cross_platform;

pub fn main() !void {
    try capy.init();

    var window = try capy.Window.init();
    try window.set(capy.Column(.{ .spacing = 0 }, .{
        capy.Expanded(capy.TextArea(.{})),
        capy.Label(.{ .text = "TODO: cursor info" }),
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
    }));

    window.setTitle("Notepad");
    window.resize(800, 600);
    window.show();

    capy.runEventLoop();
}
