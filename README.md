<a href="https://capy-ui.org">
    <p align="center">
        <picture>
            <source media="(prefers-color-scheme: dark)" srcset="https://capy-ui.org/img/capy_big2_dark.png">
            <img src="https://capy-ui.org/img/capy_big2.png" alt="Capy UI" height="200px">
        </picture>
    </p>
</a>

**As of now, Capy is NOT ready for use in production as I'm still making breaking changes**

**Capy targets Zig version `0.14.1`, the plan is to return to [Nominated Zig versions](https://machengine.org/docs/nominated-zig/)
once a new one is published**

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

## Getting Started

If you're starting a new project, simply clone [capy-template](https://github.com/capy-ui/capy-template) and follow build instructions.

Otherwise or for more information, please look in the [docs](https://capy-ui.org/docs/getting-started/installation).

You can ask questions and receive updates on the [#capy-ui Matrix channel](https://matrix.to/#/#capy-ui:matrix.org) or on the
Zig Discord Server (in the #gui-dev channel).

## Usage

A simple application using capy:

```zig
const capy = @import("capy");
const std = @import("std");
pub usingnamespace capy.cross_platform;

pub fn main() !void {
    try capy.init();

    var window = try capy.Window.init();
    try window.set(
        capy.column(.{ .spacing = 10 }, .{ // have 10px spacing between each column's element
            capy.row(.{ .spacing = 5 }, .{ // have 5px spacing between each row's element
                capy.button(.{ .label = "Save", .onclick = @ptrCast(&buttonClicked) }),
                capy.button(.{ .label = "Run",  .onclick = @ptrCast(&buttonClicked) })
            }),
            // 'expanded' means the widget will take all the space it can
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
    std.log.info("You clicked the button with text {s}", .{button.getLabel()});
}
```

It is easy to add something like a button or a text area. The example can already be used to notice a widget's parameters are usually enclosed in anonymous
structs (`.{ .label = "Save" }`). You can also see that simply wrapping a widget with `capy.Expanded( ... )` will tell it to take all the space it can.

## Contributing
Contributing can be as simple as opening an issue and detailling what bug you encountered or what feature you wish to have.  
If you want to help the project more directly, you can fork the project and then create a pull request.

## Supported platforms

A platform is considered supported only if it can be built to from every other OS.

Legends:
- ✅ Working and can be cross-compile from all platforms supported by Zig
- 🧪 Experimental
- 🏃 Planned

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

Note: As there's no "official" GUI library for Linux, GTK 4 has been chosen as it is the one
that works and can be configured on the most distros. It's also the reason Libadwaita won't
be adopted, as it's meant for GNOME and GNOME only by disallowing styling and integration
with other DEs.



## Supported components
For now, not every platform supports the same components. So here's a list of the ones that are supported:

|                  |win32|macOS|GTK|Android|wasm|
|------------------|-----|-----|---|-----|-----|
|Button            |✅|✅|✅|✅|✅|
|Canvas            |❌|❌|✅|✅|✅|
|CheckBox          |✅|❌|✅|❌|❌|
|Dropdown          |✅|❌|✅|❌|❌|
|Image             |❌|❌|✅|❌|✅|
|Label             |✅|✅|✅|✅|✅|
|Menu              |❌|❌|❌|❌|❌|
|Navigation        |❌|❌|❌|❌|❌|
|NavigationSidebar |❌|❌|✅|❌|❌|
|Scrollable        |✅|❌|✅|❌|❌|
|Slider            |✅|❌|✅|❌|✅|
|Tabs              |✅|❌|✅|❌|❌|
|TextArea          |✅|❌|✅|❌|❌|
|TextField         |✅|❌|✅|✅|✅|
|Window            |✅|✅|✅|✅|✅
