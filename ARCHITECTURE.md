# Capy Architecture Guide

This document is intended for contributors (human or AI) who need to understand
how Capy is structured before making changes. It covers the cross-platform
abstraction, backend contract, widget system, and key design decisions.

---

## Overview

Capy is a **cross-platform GUI library for Zig** that uses each platform's native
toolkit. Unlike frameworks that draw their own widgets (like Flutter or Electron),
Capy creates real native controls -- NSButton on macOS, GtkButton on Linux,
HWND-based controls on Windows, DOM elements on WASM.

```
                          ┌─────────────────────────┐
                          │     User Application    │
                          │    (examples/*.zig)     │
                          └────────────┬────────────┘
                                       │
                          ┌────────────▼─────────────┐
                          │      src/capy.zig        │
                          │  (public API surface)    │
                          └────────────┬─────────────┘
                                       │
              ┌────────────────────────▼────────────────────────┐
              │              src/internal.zig                   │
              │  Widget trait system (All/Widgeting/Events)     │
              │  + src/containers.zig (layout engine)           │
              │  + src/data.zig (reactive Atom/ListAtom)        │
              └────────────────────────┬────────────────────────┘
                                       │
                          ┌────────────▼─────────────┐
                          │     src/backend.zig      │
                          │  (compile-time dispatch) │
                          └────────────┬─────────────┘
                                       │
          ┌──────────┬─────────┬───────┴────┬──────────┬──────────┐
          ▼          ▼         ▼            ▼          ▼          ▼
       macOS       GTK      Win32       Android     WASM       GLES
      (AppKit)   (GTK 4)   (Win32)     (Android)  (Browser)  (OpenGL)
```

---

## Directory Structure

```
capy/
├── build.zig              # Build system -- builds library + all examples
├── build.zig.zon          # Package manifest (deps: zig-objc, zigimg)
├── flake.nix              # Nix flake for reproducible dev environment
├── src/
│   ├── capy.zig           # Public API: re-exports components, containers, data, etc.
│   ├── backend.zig        # Compile-time backend selection based on target OS
│   ├── internal.zig       # Widget trait system (All, Widgeting, Events mixins)
│   ├── containers.zig     # Layout engine (Column, Row, Grid, Stack, Border)
│   ├── data.zig           # Reactive primitives (Atom, ListAtom, bindings)
│   ├── image.zig          # Image loading (zigimg PNG decoder)
│   ├── assets.zig         # Asset loading (file://, asset:// URI schemes)
│   ├── http.zig           # HTTP client abstraction
│   ├── async.zig          # Async primitives (currently stubbed)
│   ├── fuzz.zig           # Property-based testing / fuzzing utilities
│   ├── trait.zig          # Comptime type introspection helpers
│   ├── monitor.zig        # Multi-monitor abstraction
│   ├── list.zig           # List widget (virtual scrolling)
│   ├── components/        # Cross-platform widget definitions
│   │   ├── Button.zig
│   │   ├── Label.zig
│   │   ├── TextField.zig
│   │   ├── TextArea.zig
│   │   ├── Canvas.zig
│   │   ├── Image.zig
│   │   ├── CheckBox.zig
│   │   ├── Dropdown.zig
│   │   ├── Slider.zig
│   │   ├── Scrollable.zig
│   │   ├── Tabs.zig
│   │   ├── Navigation.zig
│   │   ├── NavigationSidebar.zig
│   │   └── Alignment.zig
│   ├── backends/
│   │   ├── macos/         # AppKit via zig-objc runtime bridging
│   │   ├── gtk/           # GTK 4 via C FFI
│   │   ├── win32/         # Win32 API
│   │   ├── wasm/          # Browser DOM via JS interop
│   │   ├── android/       # Android NDK
│   │   └── gles/          # OpenGL ES (experimental)
│   ├── flat/              # Custom-drawn widget implementations
│   └── dev_tools/         # Development inspector tools
├── examples/              # Example applications
└── assets/                # Shared assets (images, etc.)
```

---

## Backend Contract

Each backend must provide a set of types and functions that the framework expects.
`src/backend.zig` selects the backend at compile time:

```zig
const backend = switch (builtin.os.tag) {
    .windows => @import("backends/win32/backend.zig"),
    .macos   => @import("backends/macos/backend.zig"),
    .linux, .freebsd => @import("backends/gtk/backend.zig"),
    .freestanding => if (builtin.cpu.arch == .wasm32)
        @import("backends/wasm/backend.zig") else ...,
    else => @compileError("unsupported platform"),
};
```

### Required Types

Every backend must export these types (some are optional and checked with `@hasDecl`):

| Type | Description |
|------|-------------|
| `Window` | Top-level window with title, size, menu |
| `Container` | Generic view that holds child widgets |
| `Canvas` | Drawing surface with CoreGraphics/Cairo/D2D/Canvas2D |
| `Button` | Push button with label and click handler |
| `Label` | Static text display |
| `TextField` | Single-line text input |
| `PeerType` | The underlying native handle type |
| `DrawContext` / `DrawContextImpl` | 2D drawing API |

Optional types (checked with `@hasDecl`):
`TextArea`, `CheckBox`, `Dropdown`, `Slider`, `ScrollView`, `TabContainer`,
`NavigationSidebar`, `ImageData`, `Monitor`, `Http`

### Required Widget Methods

Each widget type must provide:

```zig
pub fn create() !Self;          // Construct the native widget
pub fn setupEvents(*Self);      // Wire up event handlers
pub fn setUserData(*Self, usize); // Store framework userdata pointer
pub fn setCallback(*Self, Callbacks); // Set event handler function pointers
pub fn getWidth(*Self) u32;
pub fn getHeight(*Self) u32;
pub fn requestDraw(*Self) !void; // Trigger a redraw
pub fn deinit(*Self) void;       // Clean up native resources
```

---

## Widget Trait System (`src/internal.zig`)

The widget trait system is how cross-platform widget structs acquire their
common functionality. It uses Zig's comptime generics.

### `All(T)` -- The Full Widget Interface

`All(T)` combines `Widgeting(T)` (property management, display, cloning) with
`Events(T)` (handler registration). It returns a struct full of functions that
are re-exported by each widget.

```zig
// In src/components/Button.zig:
const _all = @import("../internal.zig").All(@This());
pub const WidgetData = _all.WidgetData;
pub const addClickHandler = _all.addClickHandler;
pub const addDrawHandler = _all.addDrawHandler;
// ... etc
```

### Why Explicit Re-exports?

Zig 0.15.2 removed `pub usingnamespace`. Previously, widgets could do
`pub usingnamespace All(Self)` to import everything. Now each symbol must be
explicitly listed. This is verbose but makes the public API surface of each
widget completely explicit and grep-able.

---

## Reactive Data System (`src/data.zig`)

Capy uses a reactive data model inspired by signals/atoms:

### `Atom(T)`

A thread-safe observable value. When set, it notifies all listeners.

```zig
var count = Atom(u32).of(0);
count.addChangeListener(myCallback);
count.set(42);  // triggers myCallback
```

Key features:
- `Mutex`-protected reads and writes
- Change listeners (linked list of callbacks)
- Bindings between atoms (one-way and two-way)
- `dependOn` for derived/computed atoms
- Animation support (interpolation over time)

### `ListAtom(T)`

An observable list with append, pop, set, swap-remove operations.
Uses `RwLock` for concurrent read access. Includes `map` for
creating derived lists.

### Linked List Compat

`data.zig` contains a `SinglyLinkedList(T)` wrapper that recreates the pre-0.15
generic linked list API on top of Zig 0.15's intrusive `std.SinglyLinkedList`.
This is used for change listener lists and binding lists.

---

## Layout Engine (`src/containers.zig`)

Layout is computed by the framework, not the native toolkit. The engine supports:

- **Column** -- vertical stack
- **Row** -- horizontal stack
- **Grid** -- N-column grid with configurable spacing
- **Stack** -- overlapping layers
- **Border** -- padding around a child

Layout uses a callback-based system where the layout function receives
`Callbacks` with `moveResize` and `getSize` function pointers. This allows
the same layout logic to work both for real layout (moving native widgets)
and for preferred-size computation (accumulating bounding boxes).

### `BoundedArray` Compat

`containers.zig` contains a local `BoundedArray(T, capacity)` reimplementation
since `std.BoundedArray` was removed in Zig 0.15.

### Float-to-Int Safety

A `saturatingFloatToU32` helper handles NaN and overflow safely, since Zig 0.15
made `@intFromFloat` a safety-checked operation that panics on bad values.

---

## macOS Backend Deep Dive

The macOS backend is the most architecturally interesting because it bridges
Zig and Objective-C at runtime with zero ObjC source files.

### Key Design: Runtime Objective-C Bridging

Instead of writing Objective-C code and linking it, the backend uses `zig-objc`
to interact with the Objective-C runtime directly:

```zig
// Look up a class
const NSButton = objc.getClass("NSButton").?;

// Send a message (equivalent to [NSButton alloc])
const btn = NSButton.msgSend(objc.Object, "alloc", .{});

// Call a method with arguments
btn.msgSend(void, "setTitle:", .{AppKit.nsString("Click me")});
```

### Custom Class Registration

When Capy needs to override methods (like `drawRect:` on a view), it creates
a new Objective-C class at runtime:

```zig
const cls = objc.allocateClassPair(NSViewClass, "CapyCanvasView") orelse return error;
_ = cls.addMethod("drawRect:", &drawRectImpl);
_ = cls.addMethod("isFlipped", &isFlippedImpl);
cls.addIvar("capy_event_data");  // store Zig pointer in ObjC ivar
cls.registerClassPair();
```

The `capy_event_data` ivar stores a pointer to Zig-allocated `EventUserData`,
which holds all the event handlers. When macOS calls `drawRect:`, the ObjC
method implementation reads this ivar to find the Zig callback.

### Coordinate System

macOS uses bottom-left origin by default. Capy uses top-left. The backend handles
this by:
1. Custom views return `isFlipped = true`
2. Canvas drawing applies `CGContextTranslateCTM` + `CGContextScaleCTM(1, -1)`

### AppKit.zig

A hand-written "header file" of `extern "c"` declarations for CoreGraphics,
CoreText, and CoreFoundation. Types use `extern struct` for C ABI compatibility.
This is intentionally minimal -- only functions actually used by the backend are
declared.

---

## Image Loading (`src/image.zig`)

Images are loaded via zigimg (PNG decoder). The flow:

1. `ImageData.fromFile` or `ImageData.fromBuffer` receives raw bytes
2. `readFromStream` decodes via `zigimg.formats.png.load()`
3. Pixel bytes are **duplicated** into Capy's own allocation (to avoid
   shared ownership with zigimg's internal buffers)
4. zigimg's Image is safely deinited via `defer img.deinit(allocator)`
5. The backend creates a native image handle (CGImage on macOS, etc.)

**Important:** The bytes duplication in step 3 is critical. Without it, either
the zigimg buffer leaks (if you skip `img.deinit()`) or you get a use-after-free
(if you deinit zigimg while ImageData still references its buffer).

---

## Asset System (`src/assets.zig`)

Assets are loaded via URI schemes:
- `asset:///path` -- relative to the `assets/` directory
- `file:///path` -- absolute filesystem path

The asset system handles URI parsing, path resolution, and provides a
`readAllAlloc` method for loading entire files into memory.

---

## Build System (`build.zig`)

The build system:
1. Defines the `capy` module with platform-appropriate dependencies
2. Links platform frameworks (AppKit, CoreGraphics, etc. on macOS; GTK on Linux)
3. Builds all example applications as separate executables
4. Provides a `test` step that runs the library's test suite

### Adding a New Example

Add a new entry to the `examples` array in `build.zig`. The build system will
automatically create a build step for it.

### Adding a New Backend

1. Create `src/backends/yourplatform/backend.zig`
2. Implement all required types (see Backend Contract above)
3. Add a case to `src/backend.zig`'s platform switch
4. Add framework linking in `build.zig`

---

## Testing

Tests are embedded in source files using Zig's `test` blocks and `decltest`.
Run with:

```bash
zig build test --summary all
```

The test suite covers:
- Reactive data types (Atom, ListAtom, bindings, map)
- Image loading and pixel verification
- Asset URI parsing
- Text layout metrics
- Property-based fuzzing utilities
- Layout computation

Tests use `std.testing.allocator` (which is a GeneralPurposeAllocator in test
mode) to detect memory leaks. Any leaked allocation will cause the test to fail.

---

## Common Pitfalls

### Memory Ownership

Capy uses explicit ownership. When a function returns allocated data, the caller
is responsible for freeing it. Watch for:
- Image pixel data: zigimg allocates internally, Capy must dupe and free
- Native handles: each backend must release its own resources in `deinit`
- Linked list nodes: allocated with `global_allocator`, freed during deinit

### `usingnamespace` Removal

If you add a new method to `All(T)` in `internal.zig`, you must also add the
corresponding `pub const newMethod = _all.newMethod;` line to **every widget**
that uses `All`. This is the most common source of "missing member" errors.

### Backend Optionality

Not every backend supports every widget. Use `@hasDecl(backend, "CheckBox")` to
check at compile time. The framework gracefully degrades -- it won't try to
create a widget type that the backend doesn't provide.

### Layout vs. Native Sizing

Layout is computed by Capy, not the native toolkit. The native widget is just
positioned via `setFrame:` (macOS) / `gtk_fixed_move` (GTK) / `SetWindowPos`
(Win32). This means preferred sizes must be calculated by querying the native
widget, not by Capy guessing.
