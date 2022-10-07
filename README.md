<h1 align="center">Capy: a GUI library for Zig</h1>
<h5 align="center">GUIs in Zig, but idiomatic</h5>

**As of now, Capy is NOT ready for use in production as I'm still making breaking changes**

---

![the glorius software in action](https://raw.githubusercontent.com/zenith391/bottom-zig-gui/main/.github/screenshot.png)

## Introduction

Capy is a **graphical user interface library for Zig**. It is mainly intended for creating applications using native controls from the operating system.
Capy is a declarative UI library aiming to be easy to write for and versatile.

It has been made with the goal to empower standalone UI applications, integration in games or any other rendering process is a non-goal.

## Usage

A simple application using capy:

```zig
const capy = @import("capy");
const std = @import("std");

pub fn main() !void {
    try capy.backend.init();

    var window = try capy.Window.init();
    try window.set(
        capy.Column(.{ .spacing = 10 }, .{ // have 10px spacing between each column's element
            capy.Row(.{ .spacing = 5 }, .{ // have 5px spacing between each row's element
                capy.Button(.{ .label = "Save", .onclick = buttonClicked }),
                capy.Button(.{ .label = "Run",  .onclick = buttonClicked })
            }),
            // Expanded means the widget will take all the space it can
            // in the parent container
            capy.Expanded(
                capy.TextArea(.{ .text = "Hello World!" })
            )
        })
    );

    window.resize(800, 600);
    window.show();
    capy.runEventLoop();
}

fn buttonClicked(button: *capy.Button_Impl) !void {
    std.log.info("You clicked button with text {s}", .{button.getLabel()});
}
```

It is easy to add something like a button or a text area. The example can already be used to notice a widget's parameters are usually enclosed in anonymous
structs (`.{ .label = "Save" }`). You can also see that simply wrapping a widget with `capy.Expanded( ... )` will tell it to take all the space it can.

## Installation

**If you're starting a new project,
simply clone [capy-template](https://github.com/capy-ui/capy-template)
and follow build instructions**

Otherwise if you're adding capy to an already existing project:  

Before proceeding, you must first install the [zigmod](https://github.com/nektro/zigmod) package manager.
Then, in the folder of your project,
you can execute the following commands:

```sh
zigmod init
```

In your `build.zig`, add:

```diff
diff --git a/usr/bin/ziglang/lib/zig/init-exe/build.zig b/build.zig
index 29b50b5..ccbb74b 100644
--- a/usr/bin/ziglang/lib/zig/init-exe/build.zig
+++ b/build.zig
@@ -1,6 +1,7 @@
 const std = @import("std");
+const deps = @import("deps.zig");

-pub fn build(b: *std.build.Builder) void {
+pub fn build(b: *std.build.Builder) !void {
     // Standard target options allows the person running `zig build` to choose
     // what target to build for. Here we do not override the defaults, which
     // means any target is allowed, and the default is native. Other options
@@ -11,7 +12,9 @@ pub fn build(b: *std.build.Builder) void {
     // between Debug, ReleaseSafe, ReleaseFast, and ReleaseSmall.
     const mode = b.standardReleaseOptions();

-    const exe = b.addExecutable("$", "src/main.zig");
+    const exe = b.addExecutable("capy-template", "src/main.zig");
+    const pathToCapy = ".zigmod/deps/git/github.com/capy-ui/capy/";
     exe.setTarget(target);
     exe.setBuildMode(mode);
+    try deps.imports.capy.install(exe, pathToCapy);
     exe.install();
```

And in your `zigmod.yml` file, add:

```diff
diff --git a/default_zigmod.yml b/zigmod.yml
index e39f6f1..4774adb 100644
--- a/default_zigmod.yml
+++ b/zigmod.yml
@@ -2,4 +2,6 @@ id: Random ID
 name: Your app name
 license: Your license
 description: A description.
+build_dependencies:
+    - src: git https://github.com/capy-ui/capy
 root_depedencies:
```

Finally, run

```sh
zigmod fetch
```

For more information, please look in the [wiki](https://github.com/capy-ui/capy/wiki/Installation)

## Supported platforms

A platform is considered supported only if it can be built from every other OS.

✅ Windows x86_64  
✅ Windows i386

✅ Linux x86_64  
✅ Linux i386  
✅ Linux aarch64 (PinePhone, PineBook...)  

✅ FreeBSD x86_64  

✅ WebAssembly  

🏃 macOS M1  
🏃 macOS x86_64  

- ✅ Working and can be cross-compile from all platforms supported by Zig
- 🏃 Planned

Note: As there's no "official" GUI library for Linux, GTK 3 has been chosen as it is the one
that works and can be configured on the most distros. It's also the reason Libadwaita won't
be adopted, as it's meant for GNOME and GNOME only by disallowing styling and integration
with other DEs.

Ask questions and receive updates on the [Matrix channel](https://matrix.to/#/#capy-ui:matrix.org).
