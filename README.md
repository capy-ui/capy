# zgt

Zig GUI Toolkit

**As of now, zgt is NOT ready for use in production as i'm still making breaking changes**

Example of using zgt:

```zig
const zgt = @import("zgt");
const std = @import("std");

pub fn main() !void {
    try zgt.backend.init();
    
    var window = try zgt.Window.init();
    try window.set(
        zgt.Column(.{}, .{
            zgt.Row(.{}, .{
                zgt.Button(.{ .label = "Save", .onclick = buttonClicked }),
                zgt.Button(.{ .label = "Run",  .onclick = buttonClicked })
            }),
            // Expanded means the widget will take all the space it can
            // in the parent container
            zgt.Expanded(
                zgt.TextArea(.{ .text = "Hello World!" })
            )
        })
    );

    window.resize(800, 600);
    window.show();
    zgt.runEventLoop();
}

fn buttonClicked(button: *Button_Impl) !void {
    std.log.info("You clicked button with text {s}", .{button.getLabel()});
}
```
