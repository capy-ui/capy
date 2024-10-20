const std = @import("std");
const capy = @import("capy");

pub usingnamespace capy.cross_platform;

pub fn main() !void {
    try capy.init();

    var window = try capy.Window.init();

    // Whether the font is monospaced
    var monospace = capy.Atom(bool).alloc(false);
    defer monospace.deinit();

    // The context of the text area
    var text = capy.Atom([]const u8).alloc("");
    defer text.deinit();

    const text_length = try capy.Atom(usize).derived(.{text}, &struct {
        fn callback(txt: []const u8) usize {
            return txt.len;
        }
    }.callback);

    var label_text = try capy.FormattedAtom(capy.internal.lasting_allocator, "Text length: {d}", .{text_length});
    defer label_text.deinit();

    try window.set(capy.column(.{ .spacing = 0 }, .{
        // By binding the atoms, we know the text area's text and the 'text' variable are always 'synchronized',
        // or bound. Same goes for the 'monospace' property.
        capy.expanded(
            capy.textArea(.{})
                .bind("monospace", monospace)
                .bind("text", text),
        ),
        capy.label(.{ .text = "" })
            .bind("text", label_text),
        // TODO: move into menu
        capy.checkBox(.{ .label = "Monospaced" })
            .bind("checked", monospace),
    }));

    // TODO: hotkeys for actions (Ctrl+S, Ctrl+C) plus corresponding Cmd+C on macOS
    window.setMenuBar(capy.menuBar(.{
        capy.menu(.{ .label = "File" }, .{
            capy.menuItem(.{ .label = "New File" }),
            capy.menuItem(.{ .label = "Open File.." }),
            capy.menuItem(.{ .label = "Save" }),
            // TODO: capy.menuSeperator ?
            capy.menuItem(.{ .label = "Quit" }),
        }),
        capy.menu(.{ .label = "Edit" }, .{
            capy.menuItem(.{ .label = "Find" }),
            capy.menuItem(.{ .label = "Copy" }),
            capy.menuItem(.{ .label = "Paste" }),
        }),
        capy.menu(.{ .label = "View" }, .{
            // TODO: togglemenuitem ?
            capy.menuItem(.{ .label = "Monospace" }),
        }),
    }));

    window.setTitle("Notepad");
    window.setPreferredSize(800, 600);
    window.show();

    capy.runEventLoop();
}
