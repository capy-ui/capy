![Capy](https://capy-ui.org/img/capy_big.png)

**As of now, Capy is NOT ready for use in production as I'm still making breaking changes**

---

[![Code Coverage](https://img.shields.io/codecov/c/github/capy-ui/capy?style=for-the-badge)](https://app.codecov.io/gh/capy-ui/capy)
[![MPL-2.0 License](https://img.shields.io/github/license/capy-ui/capy?style=for-the-badge)](https://github.com/capy-ui/capy/blob/master/LICENSE)

![the glorius software in action](https://raw.githubusercontent.com/zenith391/bottom-zig-gui/main/.github/screenshot.png)

## Introduction

Capy is a **GUI library for Zig**. It is mainly intended for creating applications using native controls from the operating system.
Capy is a declarative UI library aiming to be easy to write for and versatile.

It has been made with the goal to empower standalone UI applications, integration in games or any other rendering process is a non-goal.

## Features
- Use Zig for frontend and backend
- Accessibility: compatibility with almost all accessibility tools
- Cross-platform
- Uses the target OS toolkit
- Cross-compilable from any platform to any other platform
- *Tiny* executables - Every [example](https://github.com/capy-ui/capy/tree/master/examples)'s size < 2MB, which is smaller than 'hello world' in Go

## Usage

**Target Zig Version: `0.12.0-dev.2159+7916cf6f8`**

A simple application using capy:

```zig
const capy = @import("capy");
const std = @import("std");

pub fn main() !void {
    try capy.backend.init();

    var window = try capy.Window.init();
    try window.set(
        capy.column(.{ .spacing = 10 }, .{ // have 10px spacing between each column's element
            capy.row(.{ .spacing = 5 }, .{ // have 5px spacing between each row's element
                capy.button(.{ .label = "Save", .onclick = @ptrCast(&buttonClicked) }),
                capy.button(.{ .label = "Run",  .onclick = @ptrCast(&buttonClicked) })
            }),
            // Expanded means the widget will take all the space it can
            // in the parent container
            capy.expanded(
                capy.textArea(.{ .text = "Hello World!" })
            )
        })
    );

    window.setPreferredSize(800, 600);
    window.show();
    capy.runEventLoop();
}

fn buttonClicked(button: *capy.Button) !void {
    std.log.info("You clicked button with text {s}", .{button.getLabel()});
}
```

It is easy to add something like a button or a text area. The example can already be used to notice a widget's parameters are usually enclosed in anonymous
structs (`.{ .label = "Save" }`). You can also see that simply wrapping a widget with `capy.Expanded( ... )` will tell it to take all the space it can.

## Getting Started

*Note:* Capy targets **Zig master** so please try to get the latest version

If you're starting a new project, simply clone [capy-template](https://github.com/capy-ui/capy-template) and follow build instructions.

Otherwise or for more information, please look in the [docs](https://capy-ui.org/docs/getting-started/installation).

You can questions and receive updates on the [#capy-ui Matrix channel](https://matrix.to/#/#capy-ui:matrix.org).

## Contributing
Contributing can be as simple as opening an issue and detailling what bug you encountered or what feature you wish to have.  
If you want to help the project more directly, you can fork the project and then create a pull request.

## Supported platforms

A platform is considered supported only if it can be built to from every other OS.

### Desktop

✅ Windows x86_64  
✅ Windows i386

🏃 macOS M1  
🏃 macOS x86_64  

✅ Linux x86_64  
✅ Linux i386  
✅ Linux aarch64 (PinePhone, PineBook...)  

✅ FreeBSD x86_64  

### Mobile

🧪 Android  
🏃 iOS

### Web

✅ WebAssembly  

- ✅ Working and can be cross-compile from all platforms supported by Zig
- 🧪 Experimental
- 🏃 Planned

Note: As there's no "official" GUI library for Linux, GTK 4 has been chosen as it is the one
that works and can be configured on the most distros. It's also the reason Libadwaita won't
be adopted, as it's meant for GNOME and GNOME only by disallowing styling and integration
with other DEs.

