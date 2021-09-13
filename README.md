# zgt

**As of now, zgt is NOT ready for use in production as I'm still making breaking changes**

---

## Introduction

zgt is a **graphical user interface library for Zig**. It is mainly intended for creating applications using native controls from the operating system.

## Usage

**zgt can be used as any other library** using the Zig build package system. It only requires adding this code to your `build.zig` file (it also manages backend-specific configuration):

```zig
try @import("zgt/build.zig").install(exe, "./path/to/zgt");
```

A simple application using zgt:

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

fn buttonClicked(button: *zgt.Button_Impl) !void {
    std.log.info("You clicked button with text {s}", .{button.getLabel()});
}
```

### Goals

- Create the OpenGL ES backend, which would be the equivalent to other 'lightweight' GUIs
