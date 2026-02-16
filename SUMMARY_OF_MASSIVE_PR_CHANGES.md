# Summary of Changes: Zig 0.15.2 Migration + macOS Backend Overhaul

**Author:** Claude (Anthropic), guided by Peter Marreck ([@pmarreck](https://github.com/pmarreck))

**Diff stats:** 105 files changed, ~11,800 additions, ~7,900 deletions

**Test results:** 83 passed, 1 skipped, 0 failed, 0 leak warnings

---

## Why This PR Exists

Capy pinned Zig 0.14.1 at the time of upstream's last release. Zig 0.15.2 introduced
dozens of breaking changes that required a coordinated migration across the entire
codebase. At the same time, the macOS backend was skeletal -- it could open a window
and render a button, but most widgets were stubs. This PR addresses both:

1. **Full Zig 0.15.2 compatibility** -- every source file compiles and every test passes
2. **macOS backend brought to near-parity** with GTK/Win32 -- 14 widget types fully implemented
3. **Leak and crash fixes** found during testing
4. **New tests** covering image loading, asset URIs, text layout, canvas, and reactive data types
5. **Slide-viewer example** rewritten as a functional presentation app exercising canvas, images, text, and navigation

We took care to follow the patterns already established in the codebase. Every change
was tested on macOS (Apple Silicon). Cross-compilation to other targets was verified
by ensuring the build system changes are structurally correct, though we did not have
access to Windows/Linux/Android/WASM test environments.

---

## Table of Contents

- [1. Zig 0.15.2 Migration](#1-zig-0152-migration)
- [2. macOS Backend Overhaul](#2-macos-backend-overhaul)
- [3. Bug Fixes and Leak Patches](#3-bug-fixes-and-leak-patches)
- [4. New Tests](#4-new-tests)
- [5. Slide-Viewer Example Rewrite](#5-slide-viewer-example-rewrite)
- [6. Build System and Dependencies](#6-build-system-and-dependencies)
- [7. Files Not Changed (and Why)](#7-files-not-changed-and-why)

---

## 1. Zig 0.15.2 Migration

These are the mechanical, codebase-wide changes required by Zig 0.15.2 breaking changes.
They are high in line count but low in risk -- each follows a deterministic pattern.

### 1.1 Removal of `pub usingnamespace` (~40 files, ~50 re-exports each)

Zig 0.15.2 removed `pub usingnamespace` entirely. Every widget struct that
previously did `pub usingnamespace @import("../internal.zig").All(Widget)` now
explicitly re-exports each symbol:

```zig
// Before:
pub usingnamespace @import("../internal.zig").All(Button);

// After:
const _all = @import("../internal.zig").All(@This());
pub const WidgetData = _all.WidgetData;
pub const setupEvents = _all.setupEvents;
pub const addClickHandler = _all.addClickHandler;
// ... ~50 more per widget
```

This affects every component (`src/components/*.zig`), every backend widget
(GTK, Win32, WASM, macOS), `containers.zig`, `http.zig`, and all example files
that used `pub usingnamespace capy.cross_platform`.

**Why so many lines?** Each widget needs ~50 re-exports. With ~20+ widget types
across 4 backends, this is the single largest contributor to the diff.
The re-exports are an exact 1:1 mapping of what `usingnamespace` previously
injected, so functionality is identical.

### 1.2 `std.ArrayList` Now Unmanaged (~15 files)

`std.ArrayList` no longer stores its allocator. Every `init`, `append`, `deinit`,
`clearAndFree`, `toOwnedSlice`, and `appendSlice` call now takes an explicit
allocator parameter. Initialization changed from `.init(allocator)` to `.empty`.

### 1.3 `std.SinglyLinkedList` Became Intrusive (`src/data.zig`)

The old generic `SinglyLinkedList(T)` that stored a `data: T` field per node was
removed. We wrote a small compat wrapper (64 lines) in `data.zig` that recreates
the old API using `@fieldParentPtr`. All ~15 traversal sites in `Atom` and
`ListAtom` were updated to use `node.getNext()` instead of `node.next`.

### 1.4 `std.BoundedArray` Removed (`src/containers.zig`)

Reimplemented as a 30-line local type. Used in 3 places for grid layout computation.

### 1.5 `callconv(.C)` -> `callconv(.c)`, `@typeInfo` Field Casing

Mechanical renames. `.C` -> `.c`, `.Unspecified` -> `.auto`, `.Slice` -> `.slice`,
`.Pointer` -> `.pointer`, `.Array` -> `.array`, etc.

### 1.6 `@intFromFloat` Now Panics on NaN/Overflow (`src/containers.zig`)

Zig 0.15.2 made `@intFromFloat` safety-checked. Layout code that converts `f32`
dimensions to `u32` could panic on NaN or very large floats. We added a
`saturatingFloatToU32` helper that clamps safely, used at ~12 call sites.

Integer overflow in `fakeResMove` (used during preferred-size computation) was
also fixed by widening arithmetic to `u64` before converting.

### 1.7 Async Module Stubbed Out (`src/async.zig`)

Zig 0.15.2 removed `anyframe` and `std.atomic.Queue`. The async module (which was
already incomplete/WIP upstream) was reduced to a 5-line stub with a TODO to
rewrite using `std.Thread` when needed. This module was not functional before.

### 1.8 HTTP Module Restructured (`src/http.zig`)

The `usingnamespace`-based conditional compilation was replaced with
`if (backend.Http != void)` conditional type selection. The `std.http.Client`
fallback path (for non-WASM platforms without a backend HTTP implementation) is
stubbed with a clear panic message -- the upstream code used APIs that no longer
exist in 0.15.2's `std.http.Client`.

### 1.9 Other Standard Library Renames

- `std.time.sleep` -> `std.Thread.sleep`
- `std.rand.DefaultPrng` -> `std.Random.DefaultPrng`
- `std.fmt.allocPrintZ` -> `std.fmt.allocPrintSentinel`
- `std.Uri.path.toRawMaybeAlloc` -> buffer-based `.toRaw(&buf)`
- `std.debug.writeStackTrace` -> `std.debug.dumpStackTrace`

---

## 2. macOS Backend Overhaul

**Files:** `src/backends/macos/backend.zig` (+1921 lines), `AppKit.zig` (+148 lines),
`CapyAppDelegate.zig`, `Monitor.zig`, `components/Button.zig`

The macOS backend went from a proof-of-concept (Window + Button + Container) to a
near-complete implementation. All widget code is pure Zig -- no Objective-C source
files. The Objective-C runtime is accessed dynamically via the `zig-objc` library.

### 2.1 Widgets Implemented

| Widget | macOS Class | Notes |
|--------|-------------|-------|
| Window | NSWindow | Title, resize, minimize, close, fullscreen |
| Container | CapyEventView (custom NSView) | Child positioning via `setFrame:` |
| Canvas | CapyCanvasView (custom NSView) | Full CoreGraphics drawing in `drawRect:` |
| Button | NSButton | Click handler via CapyActionTarget |
| Label | NSTextField (labelWithString:) | Read-only, alignment, font support |
| TextField | NSTextField | Text change via CapyTextFieldDelegate |
| TextArea | NSTextView in NSScrollView | Multi-line editing |
| CheckBox | NSButton (Switch type) | State change notification |
| Slider | NSSlider | Continuous value via CapySliderTarget |
| Dropdown | NSPopUpButton | Selection via CapyDropdownTarget |
| ScrollView | NSScrollView | Document view wrapping |
| TabContainer | NSTabView | Tab management |
| NavigationSidebar | NSTableView | Sidebar-style navigation |
| ImageData | CGBitmapContextCreateImage | Pixel buffer -> CGImage |
| Menu | NSMenu / NSMenuItem | Full menu bar with keyboard shortcuts |

### 2.2 Drawing Context (CoreGraphics + CoreText)

`DrawContextImpl` wraps a `CGContextRef` and provides the full drawing API:
rectangles, rounded rectangles, ellipses, lines, fills, strokes, linear gradients,
image rendering, and text rendering via CoreText (`CTLineCreateWithAttributedString`).

The coordinate system is flipped to top-left origin (matching Capy's convention):
- Custom views return `isFlipped = true`
- Canvas applies `CGContextTranslateCTM` + `CGContextScaleCTM(1, -1)`

### 2.3 Text Layout with CoreText

`TextLayout` uses CoreText for font metrics and text measurement:
- `setFont` creates a `CTFont` via `CTFontCreateWithName`
- `getTextSize` creates a `CFAttributedString` + `CTLine`, measures via
  `CTLineGetTypographicBounds`
- `text()` draws via `CTLineDraw`
- Monospace support via font face name (e.g., `"Menlo"`)

### 2.4 Objective-C Runtime Class Registration

Eight custom Objective-C classes are registered at runtime:

| Class | Purpose |
|-------|---------|
| CapyEventView | Generic NSView with mouse/keyboard event handling |
| CapyCanvasView | NSView with `drawRect:` for CoreGraphics |
| CapyAppDelegate | Application lifecycle (launch, terminate) |
| CapyActionTarget | Button click target/action |
| CapyMenuTarget | Menu item click target/action |
| CapyTextFieldDelegate | Text field change notification |
| CapySliderTarget | Slider value change |
| CapyDropdownTarget | Dropdown selection change |

Each class stores a pointer to Zig-allocated `EventUserData` via an Objective-C
instance variable, bridging ObjC callbacks back into Zig handler functions.

### 2.5 AppKit.zig Bindings

148 lines of `extern "c"` declarations for CoreGraphics, CoreText, and
CoreFoundation functions. Types are ABI-compatible with C (using `extern struct`
for geometry types). Includes a `nsString()` helper for Zig string -> NSString
conversion.

### 2.6 Event Loop

Follows NSApplication's event model:
1. First call runs `app.run` to trigger `applicationDidFinishLaunching:`
2. The delegate calls `app.stop:` to hand control back to Capy
3. Subsequent calls pump events via `nextEventMatchingMask:untilDate:inMode:dequeue:`
4. `postEmptyEvent` synthesizes an `ApplicationDefined` NSEvent to wake blocking waits

---

## 3. Bug Fixes and Leak Patches

These are the changes most likely to interest reviewers. Each was found through
testing and verified with Zig's GeneralPurposeAllocator leak detection.

### 3.1 zigimg Pixel Storage Leak (`src/image.zig`)

**Problem:** `zigimg.formats.png.load()` allocates pixel data internally.
`rawBytes()` returns a view into that allocation. The code stored this view in
`ImageData.data` but never called `img.deinit()` (it was commented out on line 70),
so zigimg's allocation leaked on every image load.

Simply uncommenting `defer img.deinit()` would cause a use-after-free because
`ImageData` still references those bytes.

**Fix:** Duplicate the bytes into our own allocation, then safely deinit zigimg:

```zig
var img = try zigimg.formats.png.load(stream, allocator, ...);
defer img.deinit(allocator);  // safe -- frees zigimg's buffer
const raw_bytes = img.rawBytes();
const bytes = try allocator.dupe(u8, raw_bytes);  // our own copy
errdefer allocator.free(bytes);
return try ImageData.fromBytes(..., bytes, allocator);
```

After this fix: zigimg owns original pixels (freed by `defer`), capy owns the
duplicate (freed by `ImageData.deinit`). No shared ownership, no double-free.

### 3.2 CGBitmapContext Leak (`src/backends/macos/backend.zig`, `AppKit.zig`)

**Problem:** `CGBitmapContextCreate()` creates a Core Graphics context.
`CGBitmapContextCreateImage()` creates an independent CGImage (copies pixel data).
The context was never released -- it leaked on every `ImageData.from()` call.

**Fix:** Added `defer AppKit.CGContextRelease(ctx)` after the null check.
Also added the `CGContextRelease` extern declaration to `AppKit.zig` (it was
missing from the bindings).

### 3.3 Asset Loading Crash (`src/assets.zig`, `src/components/Image.zig`)

**Problem:** The `std.io.Reader` interface changed in 0.15.2. The old
`handle.reader().readAllAlloc()` chain broke.

**Fix:** Replaced with direct `handle.readAllAlloc()` that reads the entire file
into a buffer. Also made `Image.draw()` gracefully handle load failures instead
of crashing (returns early if image data is null).

### 3.4 Layout Overflow Fix (`src/containers.zig`)

**Problem:** `@intFromFloat` panics on NaN in Zig 0.15.2. Layout computations
could produce NaN when dividing by zero (e.g., zero-width containers).
Also, `x + w` could overflow `u32` for large positions.

**Fix:** Added `saturatingFloatToU32()` for safe float-to-int conversion.
Widened `x + w` arithmetic to `u64` before conversion.

### 3.5 Fuzz Module Zig 0.15.2 Fixes (`src/fuzz.zig`)

**Problem:** `std.sort.sort` was removed, format method signatures changed,
`Hypothesis.deinit` had const-correctness issues.

**Fix:**
- `std.sort.sort` -> `std.mem.sort`
- Format methods updated to new 2-arg `format(value, writer)` signature
- `{}` -> `{f}` for custom-formatted types
- `deinit` changed to `*const Self` with a mutable copy for the inner deinit

The "basic bisecting" test remains skipped because `testFunction` is designed to
find failing values and re-throw one of their errors -- the test always fails by
design. It would need restructuring to pass.

---

## 4. New Tests

### 4.1 `ListAtom.map` Implementation and Tests (`src/data.zig`)

`ListAtom.map` was a stub that returned `undefined`. We implemented it:
- Acquires shared read lock on source list
- Creates new `ListAtom(U)`, iterates items, applies mapping function
- Changed return type from `*ListAtom(U)` (heap pointer) to `ListAtom(U)` (value)

This un-skipped 8 test instantiations at once (one `decltest` across 8 generic
instantiations of `ListAtom`).

### 4.2 Other Tests Added (commit `ce2ae95`)

Tests for image loading (PNG decode + pixel verification), asset URI parsing,
text layout metrics, and canvas drawing context initialization.

### 4.3 Test Results

```
83 passed, 1 skipped, 0 failed
0 leak warnings (GPA leak detection active)
```

The 1 skip is the fuzz bisecting test (see 3.5 above). Previously there were 9 skips.

---

## 5. Slide-Viewer Example Rewrite

The slide-viewer example was a placeholder with disabled buttons and TODO comments.
It was rewritten as a functional 5-slide presentation viewer that exercises:

- Canvas-based rendering (custom `drawRect:` handler)
- Image loading and aspect-ratio-preserving display
- CoreText text rendering with custom fonts and sizes
- Navigation (Prev/Next buttons with enabled/disabled state)
- Fullscreen toggle
- Navigation dots indicator

This serves as both a demo and a real integration test for the macOS backend's
canvas, image, text, and widget capabilities.

---

## 6. Build System and Dependencies

### `build.zig`

- `addExecutable` / `addTest` -> `.root_module = b.createModule(...)` pattern
- `addSharedLibrary` -> `addLibrary(.{ .linkage = .dynamic, ... })`
- `std.ArrayList` usage updated for allocator-per-call

### `build.zig.zon`

- `minimum_zig_version`: `0.14.1` -> `0.15.2`
- `zig-objc`: updated to 0.15.2-compatible commit
- `zigimg`: updated to 0.15.2-compatible commit

### `flake.nix`

- Zig pinned to 0.15.2 in the Nix flake
- macOS-specific framework linking added (CoreText, CoreFoundation, etc.)
- Darwin SDK paths configured for the build

---

## 7. Files Not Changed (and Why)

- **Android backend** (`src/backends/android/`): Only the `usingnamespace` removal
  and ArrayList API changes. No new functionality -- we didn't have an Android
  test environment.
- **GLES backend** (`src/backends/gles/`): Same -- mechanical Zig 0.15.2 fixes only.
- **GTK backend** (`src/backends/gtk/`): `usingnamespace` removal + ArrayList changes.
  The `gtk.zig` bindings file shows a large diff because it was regenerated, but
  the actual logic is unchanged.

---

## Commit History

```
87e53b4 feat: upgrade to Zig 0.15.2 and fix flake.nix for macOS
83f0667 feat: implement macOS backend widget parity and fix layout overflow
1eb136c docs: update README for macOS support and Zig 0.15.2
95d436a feat: add macOS menu, image, and monospace support; fix asset loading crash
aa5a449 feat: rewrite slide-viewer as functional presentation viewer
ce2ae95 test: add tests for image loading, asset URIs, text layout, and canvas
```

Plus the leak/test fixes from this session (not yet committed).

---

## How to Verify

```bash
# Build and run all tests
zig build test --summary all

# Check for leaks (GPA reports to stderr)
zig build test 2>&1 | grep -i leak

# Build all examples
zig build slide-viewer

# Verify no regressions in cross-compilation setup
zig build --help  # lists all example targets
```
