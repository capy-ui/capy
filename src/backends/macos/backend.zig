const std = @import("std");
const shared = @import("../shared.zig");
const lib = @import("../../capy.zig");
const objc = @import("objc");
const AppKit = @import("AppKit.zig");
const CapyAppDelegate = @import("CapyAppDelegate.zig");
const trait = @import("../../trait.zig");

const nil = objc.Object.fromId(@as(?*anyopaque, null));

const EventFunctions = shared.EventFunctions(@This());
const EventType = shared.BackendEventType;
const BackendError = shared.BackendError;
const MouseButton = shared.MouseButton;

pub const Monitor = @import("Monitor.zig");

pub const PeerType = GuiWidget;

pub const Button = @import("components/Button.zig");

const atomicValue = std.atomic.Value;
var activeWindows = atomicValue(usize).init(0);
var hasInit: bool = false;
var finishedLaunching = false;
var initPool: *objc.AutoreleasePool = undefined;

pub fn init() BackendError!void {
    if (!hasInit) {
        hasInit = true;
        initPool = objc.AutoreleasePool.init();
        const NSApplication = objc.getClass("NSApplication").?;
        const app = NSApplication.msgSend(objc.Object, "sharedApplication", .{});
        app.msgSend(void, "setActivationPolicy:", .{AppKit.NSApplicationActivationPolicy.Regular});
        app.msgSend(void, "activateIgnoringOtherApps:", .{@as(u8, @intFromBool(true))});
        app.msgSend(void, "setDelegate:", .{CapyAppDelegate.get()});

        // Set up default menu bar with Quit item (Cmd+Q)
        setupDefaultMenuBar(app);
    }
}

fn setupDefaultMenuBar(app: objc.Object) void {
    const NSMenu = objc.getClass("NSMenu") orelse return;
    const NSMenuItem = objc.getClass("NSMenuItem") orelse return;

    // Main menu bar
    const menubar = NSMenu.msgSend(objc.Object, "alloc", .{}).msgSend(objc.Object, "init", .{});
    app.msgSend(void, "setMainMenu:", .{menubar.value});

    // Application menu item (container in the menu bar)
    const app_menu_item = NSMenuItem.msgSend(objc.Object, "alloc", .{}).msgSend(objc.Object, "init", .{});
    menubar.msgSend(void, "addItem:", .{app_menu_item.value});

    // Application submenu
    const app_menu = NSMenu.msgSend(objc.Object, "alloc", .{}).msgSend(objc.Object, "init", .{});

    // "Quit" with Cmd+Q - use separateWithTag to create, then set properties
    const quit_item = NSMenuItem.msgSend(objc.Object, "alloc", .{}).msgSend(objc.Object, "init", .{});
    quit_item.msgSend(void, "setTitle:", .{AppKit.nsString("Quit")});
    quit_item.setProperty("action", objc.sel("terminate:"));
    quit_item.msgSend(void, "setKeyEquivalent:", .{AppKit.nsString("q")});
    app_menu.msgSend(void, "addItem:", .{quit_item.value});

    app_menu_item.msgSend(void, "setSubmenu:", .{app_menu.value});
}

pub fn showNativeMessageDialog(msgType: shared.MessageType, comptime fmt: []const u8, args: anytype) void {
    const msg = std.fmt.allocPrintSentinel(lib.internal.allocator, fmt, args, 0) catch {
        std.log.err("Could not launch message dialog, original text: " ++ fmt, args);
        return;
    };
    defer lib.internal.allocator.free(msg);

    const pool = objc.AutoreleasePool.init();
    defer pool.deinit();

    const NSAlert = objc.getClass("NSAlert").?;
    const alert = NSAlert.msgSend(objc.Object, "alloc", .{}).msgSend(objc.Object, "init", .{});

    alert.msgSend(void, "setMessageText:", .{AppKit.nsString("Message")});
    alert.msgSend(void, "setInformativeText:", .{AppKit.nsString(msg)});
    alert.msgSend(void, "setAlertStyle:", .{@as(AppKit.NSUInteger, switch (msgType) {
        .Information => AppKit.NSAlertStyle.Informational,
        .Warning => AppKit.NSAlertStyle.Warning,
        .Error => AppKit.NSAlertStyle.Critical,
    })});
    alert.msgSend(void, "addButtonWithTitle:", .{AppKit.nsString("OK")});
    _ = alert.msgSend(i64, "runModal", .{});
}

/// Opens a native file/directory selection dialog.
/// Returns the selected path, or null if cancelled.
/// Caller owns returned memory (allocated with lib.internal.allocator).
pub fn openFileDialog(options: shared.FileDialogOptions) ?[:0]const u8 {
    const pool = objc.AutoreleasePool.init();
    defer pool.deinit();

    const NSOpenPanel = objc.getClass("NSOpenPanel").?;
    const panel = NSOpenPanel.msgSend(objc.Object, "openPanel", .{});

    // Set title
    panel.msgSend(void, "setTitle:", .{AppKit.nsString(options.title)});

    // Configure file vs directory mode
    if (options.select_directories) {
        panel.msgSend(void, "setCanChooseFiles:", .{@as(objc.c.BOOL, false)});
        panel.msgSend(void, "setCanChooseDirectories:", .{@as(objc.c.BOOL, true)});
    } else {
        panel.msgSend(void, "setCanChooseFiles:", .{@as(objc.c.BOOL, true)});
        panel.msgSend(void, "setCanChooseDirectories:", .{@as(objc.c.BOOL, false)});
    }

    panel.msgSend(void, "setAllowsMultipleSelection:", .{@as(objc.c.BOOL, options.allow_multiple)});

    // Set file type filters using UTType (macOS 11+)
    if (!options.select_directories and options.filters.len > 0) {
        // Check if any filter is a wildcard (e.g. "*.*" or "*") — if so, allow all files
        var has_wildcard = false;
        for (options.filters) |filter| {
            const pat_str = std.mem.sliceTo(filter.pattern, 0);
            if (std.mem.eql(u8, pat_str, "*.*") or std.mem.eql(u8, pat_str, "*")) {
                has_wildcard = true;
                break;
            }
        }

        if (!has_wildcard) {
            const NSMutableArray = objc.getClass("NSMutableArray").?;
            const UTType = objc.getClass("UTType").?;
            const types_array = NSMutableArray.msgSend(objc.Object, "array", .{});

            for (options.filters) |filter| {
                // Parse semicolon-separated patterns like "*.png;*.jpg"
                var iter = std.mem.splitScalar(u8, std.mem.sliceTo(filter.pattern, 0), ';');
                while (iter.next()) |pat| {
                    // Strip leading "*." to get extension
                    const ext = if (std.mem.startsWith(u8, pat, "*."))
                        pat[2..]
                    else
                        pat;
                    if (ext.len == 0) continue;
                    if (std.mem.eql(u8, ext, "*")) continue;

                    // Create null-terminated extension string
                    const ext_z = lib.internal.allocator.allocSentinel(u8, ext.len, 0) catch continue;
                    defer lib.internal.allocator.free(ext_z);
                    @memcpy(ext_z, ext);

                    const ut_type = UTType.msgSend(objc.Object, "typeWithFilenameExtension:", .{AppKit.nsString(ext_z)});
                    if (ut_type.value != 0) {
                        types_array.msgSend(void, "addObject:", .{ut_type});
                    }
                }
            }

            // Only set content types if we have specific ones
            const arr_count = types_array.msgSend(u64, "count", .{});
            if (arr_count > 0) {
                panel.msgSend(void, "setAllowedContentTypes:", .{types_array});
            }
        }
    }

    // Run modal dialog (blocks until user responds)
    const result = panel.msgSend(i64, "runModal", .{});

    // NSModalResponseOK = 1
    if (result == 1) {
        const urls = panel.msgSend(objc.Object, "URLs", .{});
        const count = urls.msgSend(u64, "count", .{});
        if (count > 0) {
            const first_url = urls.msgSend(objc.Object, "objectAtIndex:", .{@as(u64, 0)});
            const path_nsstring = first_url.msgSend(objc.Object, "path", .{});
            const cstr = path_nsstring.msgSend([*:0]const u8, "UTF8String", .{});
            // UTF8String returns a temporary pointer - must copy to owned buffer
            const len = std.mem.len(cstr);
            const owned = lib.internal.allocator.allocSentinel(u8, len, 0) catch return null;
            @memcpy(owned, cstr[0..len]);
            return owned;
        }
    }

    return null;
}

/// Returns true if the system is currently in dark mode.
pub fn isDarkMode() bool {
    const pool = objc.AutoreleasePool.init();
    defer pool.deinit();

    const NSApp = objc.getClass("NSApplication").?.msgSend(objc.Object, "sharedApplication", .{});
    const appearance = NSApp.msgSend(objc.Object, "effectiveAppearance", .{});
    const name = appearance.msgSend(objc.Object, "name", .{});
    const dark_str = objc.getClass("NSString").?.msgSend(objc.Object, "alloc", .{})
        .msgSend(objc.Object, "initWithUTF8String:", .{@as([*:0]const u8, "Dark")});
    return name.msgSend(objc.c.BOOL, "containsString:", .{dark_str});
}

/// user data used for handling events
pub const EventUserData = struct {
    user: EventFunctions = .{},
    class: EventFunctions = .{},
    userdata: usize = 0,
    classUserdata: usize = 0,
    peer: objc.Object,
    focusOnClick: bool = false,
    actual_x: ?u31 = null,
    actual_y: ?u31 = null,
    actual_width: ?u31 = null,
    actual_height: ?u31 = null,
};

pub const GuiWidget = struct {
    object: objc.Object,
    data: *EventUserData,
};

pub inline fn getEventUserData(peer: GuiWidget) *EventUserData {
    return peer.data;
}

// ---------------------------------------------------------------------------
// ObjC runtime helpers
// ---------------------------------------------------------------------------

/// Retrieve the EventUserData pointer stored in an ObjC view's "capy_event_data" ivar.
fn getEventDataFromIvar(view: objc.Object) ?*EventUserData {
    const data_obj = view.getInstanceVariable("capy_event_data");
    if (@intFromPtr(data_obj.value) == 0) return null;
    return @as(*EventUserData, @ptrFromInt(@intFromPtr(data_obj.value)));
}

/// Store an EventUserData pointer in a view's "capy_event_data" ivar.
fn setEventDataIvar(view: objc.Object, data: *EventUserData) void {
    view.setInstanceVariable("capy_event_data", objc.Object{ .value = @ptrFromInt(@intFromPtr(data)) });
}

// ---------------------------------------------------------------------------
// CapyEventView - custom NSView subclass for event handling
// ---------------------------------------------------------------------------

var cachedCapyEventView: ?objc.Class = null;

fn getCapyEventViewClass() !objc.Class {
    if (cachedCapyEventView) |cls| return cls;

    const NSViewClass = objc.getClass("NSView").?;
    const CapyEventView = objc.allocateClassPair(NSViewClass, "CapyEventView") orelse return error.InitializationError;

    // Add ivar to store EventUserData pointer
    if (!CapyEventView.addIvar("capy_event_data")) return error.InitializationError;

    // isFlipped -> YES (top-left origin)
    _ = CapyEventView.addMethod("isFlipped", struct {
        fn imp(_: objc.c.id, _: objc.c.SEL) callconv(.c) u8 {
            return @intFromBool(true);
        }
    }.imp);

    // acceptsFirstResponder -> YES
    _ = CapyEventView.addMethod("acceptsFirstResponder", struct {
        fn imp(_: objc.c.id, _: objc.c.SEL) callconv(.c) u8 {
            return @intFromBool(true);
        }
    }.imp);

    // mouseDown:
    _ = CapyEventView.addMethod("mouseDown:", struct {
        fn imp(self_id: objc.c.id, _: objc.c.SEL, event_id: objc.c.id) callconv(.c) void {
            handleMouseButton(self_id, event_id, .Left, true);
        }
    }.imp);

    // mouseUp:
    _ = CapyEventView.addMethod("mouseUp:", struct {
        fn imp(self_id: objc.c.id, _: objc.c.SEL, event_id: objc.c.id) callconv(.c) void {
            handleMouseButton(self_id, event_id, .Left, false);
        }
    }.imp);

    // rightMouseDown:
    _ = CapyEventView.addMethod("rightMouseDown:", struct {
        fn imp(self_id: objc.c.id, _: objc.c.SEL, event_id: objc.c.id) callconv(.c) void {
            handleMouseButton(self_id, event_id, .Right, true);
        }
    }.imp);

    // rightMouseUp:
    _ = CapyEventView.addMethod("rightMouseUp:", struct {
        fn imp(self_id: objc.c.id, _: objc.c.SEL, event_id: objc.c.id) callconv(.c) void {
            handleMouseButton(self_id, event_id, .Right, false);
        }
    }.imp);

    // mouseMoved:
    _ = CapyEventView.addMethod("mouseMoved:", struct {
        fn imp(self_id: objc.c.id, _: objc.c.SEL, event_id: objc.c.id) callconv(.c) void {
            handleMouseMotion(self_id, event_id);
        }
    }.imp);

    // mouseDragged:
    _ = CapyEventView.addMethod("mouseDragged:", struct {
        fn imp(self_id: objc.c.id, _: objc.c.SEL, event_id: objc.c.id) callconv(.c) void {
            handleMouseMotion(self_id, event_id);
        }
    }.imp);

    // rightMouseDragged:
    _ = CapyEventView.addMethod("rightMouseDragged:", struct {
        fn imp(self_id: objc.c.id, _: objc.c.SEL, event_id: objc.c.id) callconv(.c) void {
            handleMouseMotion(self_id, event_id);
        }
    }.imp);

    // scrollWheel:
    _ = CapyEventView.addMethod("scrollWheel:", struct {
        fn imp(self_id: objc.c.id, _: objc.c.SEL, event_id: objc.c.id) callconv(.c) void {
            handleScrollWheel(self_id, event_id);
        }
    }.imp);

    // keyDown:
    _ = CapyEventView.addMethod("keyDown:", struct {
        fn imp(self_id: objc.c.id, _: objc.c.SEL, event_id: objc.c.id) callconv(.c) void {
            handleKeyEvent(self_id, event_id);
        }
    }.imp);

    // keyUp:
    _ = CapyEventView.addMethod("keyUp:", struct {
        fn imp(self_id: objc.c.id, _: objc.c.SEL, event_id: objc.c.id) callconv(.c) void {
            handleKeyUpEvent(self_id, event_id);
        }
    }.imp);

    // flagsChanged:
    _ = CapyEventView.addMethod("flagsChanged:", struct {
        fn imp(self_id: objc.c.id, _: objc.c.SEL, event_id: objc.c.id) callconv(.c) void {
            handleFlagsChanged(self_id, event_id);
        }
    }.imp);

    // setFrameSize: override - call super then fire resize handler
    _ = CapyEventView.addMethod("setFrameSize:", struct {
        fn imp(self_id: objc.c.id, _: objc.c.SEL, size: AppKit.CGSize) callconv(.c) void {
            // Call super
            const self_obj = objc.Object{ .value = self_id };
            const SuperClass = objc.getClass("NSView").?;
            self_obj.msgSendSuper(SuperClass, void, "setFrameSize:", .{size});

            const data = getEventDataFromIvar(self_obj) orelse return;
            const w: u32 = @intFromFloat(@max(size.width, 0));
            const h: u32 = @intFromFloat(@max(size.height, 0));
            data.actual_width = @intCast(@min(w, std.math.maxInt(u31)));
            data.actual_height = @intCast(@min(h, std.math.maxInt(u31)));
            if (data.class.resizeHandler) |handler|
                handler(w, h, @intFromPtr(data));
            if (data.user.resizeHandler) |handler|
                handler(w, h, data.userdata);
        }
    }.imp);

    objc.registerClassPair(CapyEventView);
    cachedCapyEventView = CapyEventView;
    return CapyEventView;
}

// ---------------------------------------------------------------------------
// CapyCanvasView - custom NSView subclass for Canvas (events + drawRect:)
// ---------------------------------------------------------------------------

var cachedCapyCanvasView: ?objc.Class = null;

fn getCapyCanvasViewClass() !objc.Class {
    if (cachedCapyCanvasView) |cls| return cls;

    const NSViewClass = objc.getClass("NSView").?;
    const CapyCanvasView = objc.allocateClassPair(NSViewClass, "CapyCanvasView") orelse return error.InitializationError;

    if (!CapyCanvasView.addIvar("capy_event_data")) return error.InitializationError;

    // isFlipped -> YES
    _ = CapyCanvasView.addMethod("isFlipped", struct {
        fn imp(_: objc.c.id, _: objc.c.SEL) callconv(.c) u8 {
            return @intFromBool(true);
        }
    }.imp);

    // acceptsFirstResponder -> YES
    _ = CapyCanvasView.addMethod("acceptsFirstResponder", struct {
        fn imp(_: objc.c.id, _: objc.c.SEL) callconv(.c) u8 {
            return @intFromBool(true);
        }
    }.imp);

    // mouseDown:
    _ = CapyCanvasView.addMethod("mouseDown:", struct {
        fn imp(self_id: objc.c.id, _: objc.c.SEL, event_id: objc.c.id) callconv(.c) void {
            handleMouseButton(self_id, event_id, .Left, true);
        }
    }.imp);

    // mouseUp:
    _ = CapyCanvasView.addMethod("mouseUp:", struct {
        fn imp(self_id: objc.c.id, _: objc.c.SEL, event_id: objc.c.id) callconv(.c) void {
            handleMouseButton(self_id, event_id, .Left, false);
        }
    }.imp);

    // rightMouseDown:
    _ = CapyCanvasView.addMethod("rightMouseDown:", struct {
        fn imp(self_id: objc.c.id, _: objc.c.SEL, event_id: objc.c.id) callconv(.c) void {
            handleMouseButton(self_id, event_id, .Right, true);
        }
    }.imp);

    // rightMouseUp:
    _ = CapyCanvasView.addMethod("rightMouseUp:", struct {
        fn imp(self_id: objc.c.id, _: objc.c.SEL, event_id: objc.c.id) callconv(.c) void {
            handleMouseButton(self_id, event_id, .Right, false);
        }
    }.imp);

    // mouseMoved:
    _ = CapyCanvasView.addMethod("mouseMoved:", struct {
        fn imp(self_id: objc.c.id, _: objc.c.SEL, event_id: objc.c.id) callconv(.c) void {
            handleMouseMotion(self_id, event_id);
        }
    }.imp);

    // mouseDragged:
    _ = CapyCanvasView.addMethod("mouseDragged:", struct {
        fn imp(self_id: objc.c.id, _: objc.c.SEL, event_id: objc.c.id) callconv(.c) void {
            handleMouseMotion(self_id, event_id);
        }
    }.imp);

    // scrollWheel:
    _ = CapyCanvasView.addMethod("scrollWheel:", struct {
        fn imp(self_id: objc.c.id, _: objc.c.SEL, event_id: objc.c.id) callconv(.c) void {
            handleScrollWheel(self_id, event_id);
        }
    }.imp);

    // keyDown:
    _ = CapyCanvasView.addMethod("keyDown:", struct {
        fn imp(self_id: objc.c.id, _: objc.c.SEL, event_id: objc.c.id) callconv(.c) void {
            handleKeyEvent(self_id, event_id);
        }
    }.imp);

    // keyUp:
    _ = CapyCanvasView.addMethod("keyUp:", struct {
        fn imp(self_id: objc.c.id, _: objc.c.SEL, event_id: objc.c.id) callconv(.c) void {
            handleKeyUpEvent(self_id, event_id);
        }
    }.imp);

    // flagsChanged:
    _ = CapyCanvasView.addMethod("flagsChanged:", struct {
        fn imp(self_id: objc.c.id, _: objc.c.SEL, event_id: objc.c.id) callconv(.c) void {
            handleFlagsChanged(self_id, event_id);
        }
    }.imp);

    // setFrameSize: override
    _ = CapyCanvasView.addMethod("setFrameSize:", struct {
        fn imp(self_id: objc.c.id, _: objc.c.SEL, size: AppKit.CGSize) callconv(.c) void {
            const self_obj = objc.Object{ .value = self_id };
            const SuperClass = objc.getClass("NSView").?;
            self_obj.msgSendSuper(SuperClass, void, "setFrameSize:", .{size});
            const data = getEventDataFromIvar(self_obj) orelse return;
            const w: u32 = @intFromFloat(@max(size.width, 0));
            const h: u32 = @intFromFloat(@max(size.height, 0));
            data.actual_width = @intCast(@min(w, std.math.maxInt(u31)));
            data.actual_height = @intCast(@min(h, std.math.maxInt(u31)));
            if (data.class.resizeHandler) |handler|
                handler(w, h, @intFromPtr(data));
            if (data.user.resizeHandler) |handler|
                handler(w, h, data.userdata);
        }
    }.imp);

    // drawRect: override - the core of Canvas rendering
    _ = CapyCanvasView.addMethod("drawRect:", struct {
        fn imp(self_id: objc.c.id, _: objc.c.SEL, _: AppKit.CGRect) callconv(.c) void {
            const self_obj = objc.Object{ .value = self_id };
            const data = getEventDataFromIvar(self_obj) orelse return;

            // Get the current CGContext
            const NSGraphicsContext = objc.getClass("NSGraphicsContext").?;
            const gfx_ctx = NSGraphicsContext.msgSend(objc.Object, "currentContext", .{});
            if (gfx_ctx.value == null) return;
            const cg_context = gfx_ctx.msgSend(AppKit.CGContextRef, "CGContext", .{});
            if (cg_context == null) return;

            // isFlipped=YES gives top-left origin (matching GTK/Win32); no manual flip needed
            AppKit.CGContextSaveGState(cg_context);

            const draw_ctx_impl = Canvas.DrawContextImpl{ .cg_context = cg_context };
            var draw_ctx = @import("../../backend.zig").DrawContext{ .impl = draw_ctx_impl };

            if (data.class.drawHandler) |handler|
                handler(&draw_ctx, @intFromPtr(data));
            if (data.user.drawHandler) |handler|
                handler(&draw_ctx, data.userdata);

            AppKit.CGContextRestoreGState(cg_context);
        }
    }.imp);

    objc.registerClassPair(CapyCanvasView);
    cachedCapyCanvasView = CapyCanvasView;
    return CapyCanvasView;
}

// ---------------------------------------------------------------------------
// CapyActionTarget - ObjC class for target/action pattern (buttons, etc.)
// ---------------------------------------------------------------------------

var cachedCapyActionTarget: ?objc.Class = null;

fn getCapyActionTargetClass() !objc.Class {
    if (cachedCapyActionTarget) |cls| return cls;

    const NSObjectClass = objc.getClass("NSObject").?;
    const CapyActionTarget = objc.allocateClassPair(NSObjectClass, "CapyActionTarget") orelse return error.InitializationError;

    if (!CapyActionTarget.addIvar("capy_event_data")) return error.InitializationError;

    _ = CapyActionTarget.addMethod("action:", struct {
        fn imp(self_id: objc.c.id, _: objc.c.SEL, _: objc.c.id) callconv(.c) void {
            const self_obj = objc.Object{ .value = self_id };
            const data = getEventDataFromIvar(self_obj) orelse return;
            if (data.class.clickHandler) |handler|
                handler(@intFromPtr(data));
            if (data.user.clickHandler) |handler|
                handler(data.userdata);
        }
    }.imp);

    objc.registerClassPair(CapyActionTarget);
    cachedCapyActionTarget = CapyActionTarget;
    return CapyActionTarget;
}

/// Create a CapyActionTarget instance wired to the given EventUserData.
pub fn createActionTarget(data: *EventUserData) !objc.Object {
    const cls = try getCapyActionTargetClass();
    const target = cls.msgSend(objc.Object, "alloc", .{}).msgSend(objc.Object, "init", .{});
    setEventDataIvar(target, data);
    return target;
}

// --- Menu support ---

var cachedCapyMenuTarget: ?objc.Class = null;

fn getCapyMenuTargetClass() !objc.Class {
    if (cachedCapyMenuTarget) |cls| return cls;

    const NSObjectClass = objc.getClass("NSObject").?;
    const CapyMenuTarget = objc.allocateClassPair(NSObjectClass, "CapyMenuTarget") orelse return error.InitializationError;

    // Add an ivar to store the callback function pointer
    if (!CapyMenuTarget.addIvar("capy_menu_callback")) return error.InitializationError;

    _ = CapyMenuTarget.addMethod("menuAction:", struct {
        fn imp(self_id: objc.c.id, _: objc.c.SEL, _: objc.c.id) callconv(.c) void {
            const self_obj = objc.Object{ .value = self_id };
            const raw = self_obj.getInstanceVariable("capy_menu_callback");
            const cb_ptr = @intFromPtr(raw.value);
            if (cb_ptr == 0) return;
            const callback: *const fn () void = @ptrFromInt(cb_ptr);
            callback();
        }
    }.imp);

    objc.registerClassPair(CapyMenuTarget);
    cachedCapyMenuTarget = CapyMenuTarget;
    return CapyMenuTarget;
}

fn createMenuItemFromConfig(item: lib.MenuItem, menu_target_cls: objc.Class) objc.Object {
    const NSMenuItem = objc.getClass("NSMenuItem").?;
    const NSMenu = objc.getClass("NSMenu").?;

    const ns_item = NSMenuItem.msgSend(objc.Object, "alloc", .{}).msgSend(objc.Object, "init", .{});
    ns_item.msgSend(void, "setTitle:", .{AppKit.nsString(item.config.label)});

    if (item.items.len > 0) {
        // This is a submenu
        const submenu = NSMenu.msgSend(objc.Object, "alloc", .{}).msgSend(objc.Object, "init", .{});
        submenu.msgSend(void, "setTitle:", .{AppKit.nsString(item.config.label)});
        for (item.items) |sub_item| {
            const child = createMenuItemFromConfig(sub_item, menu_target_cls);
            submenu.msgSend(void, "addItem:", .{child.value});
        }
        ns_item.msgSend(void, "setSubmenu:", .{submenu.value});
    } else if (item.config.onClick) |callback| {
        // Leaf menu item with a click handler
        const target = menu_target_cls.msgSend(objc.Object, "alloc", .{}).msgSend(objc.Object, "init", .{});
        // Store callback function pointer in the ivar
        target.setInstanceVariable("capy_menu_callback", objc.Object{ .value = @ptrFromInt(@intFromPtr(callback)) });
        ns_item.msgSend(void, "setTarget:", .{target.value});
        ns_item.setProperty("action", objc.sel("menuAction:"));
    }

    return ns_item;
}

// ---------------------------------------------------------------------------
// CapyTextFieldDelegate - for text change notifications on NSTextField
// ---------------------------------------------------------------------------

var cachedCapyTextFieldDelegate: ?objc.Class = null;

fn getCapyTextFieldDelegateClass() !objc.Class {
    if (cachedCapyTextFieldDelegate) |cls| return cls;

    const NSObjectClass = objc.getClass("NSObject").?;
    const cls = objc.allocateClassPair(NSObjectClass, "CapyTextFieldDelegate") orelse return error.InitializationError;

    if (!cls.addIvar("capy_event_data")) return error.InitializationError;

    // controlTextDidChange:
    _ = cls.addMethod("controlTextDidChange:", struct {
        fn imp(self_id: objc.c.id, _: objc.c.SEL, _: objc.c.id) callconv(.c) void {
            const self_obj = objc.Object{ .value = self_id };
            const data = getEventDataFromIvar(self_obj) orelse return;
            if (data.class.changedTextHandler) |handler|
                handler(@intFromPtr(data));
            if (data.user.changedTextHandler) |handler|
                handler(data.userdata);
        }
    }.imp);

    objc.registerClassPair(cls);
    cachedCapyTextFieldDelegate = cls;
    return cls;
}

// ---------------------------------------------------------------------------
// Slider action target (fires propertyChangeHandler)
// ---------------------------------------------------------------------------

var cachedCapySliderTarget: ?objc.Class = null;

fn getCapySliderTargetClass() !objc.Class {
    if (cachedCapySliderTarget) |cls| return cls;

    const NSObjectClass = objc.getClass("NSObject").?;
    const cls = objc.allocateClassPair(NSObjectClass, "CapySliderTarget") orelse return error.InitializationError;
    if (!cls.addIvar("capy_event_data")) return error.InitializationError;

    _ = cls.addMethod("sliderAction:", struct {
        fn imp(self_id: objc.c.id, _: objc.c.SEL, sender_id: objc.c.id) callconv(.c) void {
            const self_obj = objc.Object{ .value = self_id };
            const data = getEventDataFromIvar(self_obj) orelse return;
            const sender = objc.Object{ .value = sender_id };
            const value: f32 = @floatCast(sender.getProperty(AppKit.CGFloat, "doubleValue"));
            if (data.class.propertyChangeHandler) |handler|
                handler("value", @ptrCast(&value), @intFromPtr(data));
            if (data.user.propertyChangeHandler) |handler|
                handler("value", @ptrCast(&value), data.userdata);
        }
    }.imp);

    objc.registerClassPair(cls);
    cachedCapySliderTarget = cls;
    return cls;
}

// ---------------------------------------------------------------------------
// Dropdown action target (fires propertyChangeHandler)
// ---------------------------------------------------------------------------

var cachedCapyDropdownTarget: ?objc.Class = null;

fn getCapyDropdownTargetClass() !objc.Class {
    if (cachedCapyDropdownTarget) |cls| return cls;

    const NSObjectClass = objc.getClass("NSObject").?;
    const cls = objc.allocateClassPair(NSObjectClass, "CapyDropdownTarget") orelse return error.InitializationError;
    if (!cls.addIvar("capy_event_data")) return error.InitializationError;

    _ = cls.addMethod("dropdownAction:", struct {
        fn imp(self_id: objc.c.id, _: objc.c.SEL, sender_id: objc.c.id) callconv(.c) void {
            const self_obj = objc.Object{ .value = self_id };
            const data = getEventDataFromIvar(self_obj) orelse return;
            const sender = objc.Object{ .value = sender_id };
            const index: i64 = sender.getProperty(i64, "indexOfSelectedItem");
            if (index < 0) return;
            const idx: usize = @intCast(index);
            if (data.class.propertyChangeHandler) |handler|
                handler("selected", @ptrCast(&idx), @intFromPtr(data));
            if (data.user.propertyChangeHandler) |handler|
                handler("selected", @ptrCast(&idx), data.userdata);
        }
    }.imp);

    objc.registerClassPair(cls);
    cachedCapyDropdownTarget = cls;
    return cls;
}

// ---------------------------------------------------------------------------
// Shared event handler implementations
// ---------------------------------------------------------------------------

fn handleMouseButton(self_id: objc.c.id, event_id: objc.c.id, button: MouseButton, pressed: bool) void {
    const self_obj = objc.Object{ .value = self_id };
    const data = getEventDataFromIvar(self_obj) orelse return;
    const event_obj = objc.Object{ .value = event_id };

    // Get location in the view's coordinate system
    const location_in_window = event_obj.getProperty(AppKit.CGPoint, "locationInWindow");
    const location = self_obj.msgSend(AppKit.CGPoint, "convertPoint:fromView:", .{ location_in_window, @as(objc.c.id, null) });

    const mx: i32 = @intFromFloat(@floor(location.x));
    const my: i32 = @intFromFloat(@floor(location.y));

    if (data.class.mouseButtonHandler) |handler|
        handler(button, pressed, mx, my, @intFromPtr(data));
    if (data.user.mouseButtonHandler) |handler| {
        if (data.focusOnClick) {
            (objc.Object{ .value = self_id }).msgSend(void, "becomeFirstResponder", .{});
        }
        handler(button, pressed, mx, my, data.userdata);
    }
}

fn handleMouseMotion(self_id: objc.c.id, event_id: objc.c.id) void {
    const self_obj = objc.Object{ .value = self_id };
    const data = getEventDataFromIvar(self_obj) orelse return;
    const event_obj = objc.Object{ .value = event_id };

    const location_in_window = event_obj.getProperty(AppKit.CGPoint, "locationInWindow");
    const location = self_obj.msgSend(AppKit.CGPoint, "convertPoint:fromView:", .{ location_in_window, @as(objc.c.id, null) });

    const mx: i32 = @intFromFloat(@floor(location.x));
    const my: i32 = @intFromFloat(@floor(location.y));

    if (data.class.mouseMotionHandler) |handler|
        handler(mx, my, @intFromPtr(data));
    if (data.user.mouseMotionHandler) |handler|
        handler(mx, my, data.userdata);
}

fn handleScrollWheel(self_id: objc.c.id, event_id: objc.c.id) void {
    const self_obj = objc.Object{ .value = self_id };
    const data = getEventDataFromIvar(self_obj) orelse return;
    const event_obj = objc.Object{ .value = event_id };
    const dx: f32 = @floatCast(event_obj.getProperty(AppKit.CGFloat, "scrollingDeltaX"));
    const dy: f32 = @floatCast(event_obj.getProperty(AppKit.CGFloat, "scrollingDeltaY"));
    if (data.class.scrollHandler) |handler|
        handler(dx, dy, @intFromPtr(data));
    if (data.user.scrollHandler) |handler|
        handler(dx, dy, data.userdata);
}

fn handleKeyEvent(self_id: objc.c.id, event_id: objc.c.id) void {
    const self_obj = objc.Object{ .value = self_id };
    const data = getEventDataFromIvar(self_obj) orelse return;
    const event_obj = objc.Object{ .value = event_id };

    // Get characters as UTF-8
    const chars_nsstring = event_obj.getProperty(objc.Object, "characters");
    if (chars_nsstring.value != null) {
        const utf8 = chars_nsstring.msgSend([*:0]const u8, "UTF8String", .{});
        const str = std.mem.sliceTo(utf8, 0);
        if (str.len > 0) {
            if (data.class.keyTypeHandler) |handler|
                handler(str, @intFromPtr(data));
            if (data.user.keyTypeHandler) |handler|
                handler(str, data.userdata);
        }
    }

    const keycode: u16 = event_obj.getProperty(u16, "keyCode");
    if (data.class.keyPressHandler) |handler|
        handler(keycode, @intFromPtr(data));
    if (data.user.keyPressHandler) |handler|
        handler(keycode, data.userdata);
}

fn handleKeyUpEvent(self_id: objc.c.id, event_id: objc.c.id) void {
    const self_obj = objc.Object{ .value = self_id };
    const data = getEventDataFromIvar(self_obj) orelse return;
    const event_obj = objc.Object{ .value = event_id };
    const keycode: u16 = event_obj.getProperty(u16, "keyCode");
    if (data.class.keyReleaseHandler) |handler|
        handler(keycode, @intFromPtr(data));
    if (data.user.keyReleaseHandler) |handler|
        handler(keycode, data.userdata);
}

fn handleFlagsChanged(self_id: objc.c.id, event_id: objc.c.id) void {
    const self_obj = objc.Object{ .value = self_id };
    const data = getEventDataFromIvar(self_obj) orelse return;
    const event_obj = objc.Object{ .value = event_id };
    const keycode: u16 = event_obj.getProperty(u16, "keyCode");
    if (data.class.keyPressHandler) |handler|
        handler(keycode, @intFromPtr(data));
    if (data.user.keyPressHandler) |handler|
        handler(keycode, data.userdata);
}

/// Add an NSTrackingArea to a view for mouse motion events.
fn addTrackingArea(view: objc.Object) void {
    const NSTrackingArea = objc.getClass("NSTrackingArea") orelse return;
    const opts = AppKit.NSTrackingAreaOptions.MouseMoved |
        AppKit.NSTrackingAreaOptions.MouseEnteredAndExited |
        AppKit.NSTrackingAreaOptions.ActiveAlways |
        AppKit.NSTrackingAreaOptions.InVisibleRect;
    const tracking_area = NSTrackingArea.msgSend(objc.Object, "alloc", .{})
        .msgSend(objc.Object, "initWithRect:options:owner:userInfo:", .{
        AppKit.CGRect.make(0, 0, 0, 0), // InVisibleRect makes this auto-update
        opts,
        view,
        @as(objc.c.id, null),
    });
    view.msgSend(void, "addTrackingArea:", .{tracking_area});
}

// ---------------------------------------------------------------------------
// Events mixin
// ---------------------------------------------------------------------------

pub fn Events(comptime T: type) type {
    return struct {
        const Self = @This();

        pub fn setupEvents(peer: GuiWidget) BackendError!void {
            peer.data.* = EventUserData{ .peer = peer.object };

            // If this is one of our custom views, store EventUserData in its ivar
            // and add a tracking area for mouse motion
            const class_name_ptr = objc.c.object_getClassName(peer.object.value);
            const class_name = std.mem.sliceTo(class_name_ptr, 0);
            if (std.mem.eql(u8, class_name, "CapyEventView") or
                std.mem.eql(u8, class_name, "CapyCanvasView"))
            {
                setEventDataIvar(peer.object, peer.data);
                addTrackingArea(peer.object);
            }
        }

        pub fn setUserData(self: *T, data: anytype) void {
            comptime {
                if (!trait.isSingleItemPtr(@TypeOf(data))) {
                    @compileError(std.fmt.comptimePrint("Expected single item pointer, got {s}", .{@typeName(@TypeOf(data))}));
                }
            }

            getEventUserData(self.peer).userdata = @intFromPtr(data);
        }

        pub inline fn setCallback(self: *T, comptime eType: EventType, cb: anytype) !void {
            const data = &getEventUserData(self.peer).user;
            switch (eType) {
                .Click => data.clickHandler = cb,
                .Draw => data.drawHandler = cb,
                .MouseButton => data.mouseButtonHandler = cb,
                .MouseMotion => data.mouseMotionHandler = cb,
                .Scroll => data.scrollHandler = cb,
                .TextChanged => data.changedTextHandler = cb,
                .Resize => data.resizeHandler = cb,
                .KeyType => data.keyTypeHandler = cb,
                .KeyPress => data.keyPressHandler = cb,
                .KeyRelease => data.keyReleaseHandler = cb,
                .PropertyChange => data.propertyChangeHandler = cb,
            }
        }

        pub fn setOpacity(self: *const T, opacity: f32) void {
            self.peer.object.msgSend(void, "setAlphaValue:", .{@as(AppKit.CGFloat, @floatCast(opacity))});
        }

        pub fn getX(self: *const T) c_int {
            const data = getEventUserData(self.peer);
            return data.actual_x orelse 0;
        }

        pub fn getY(self: *const T) c_int {
            const data = getEventUserData(self.peer);
            return data.actual_y orelse 0;
        }

        pub fn getWidth(self: *const T) u32 {
            const data = getEventUserData(self.peer);
            if (data.actual_width) |w| return w;
            const frame = self.peer.object.getProperty(AppKit.CGRect, "frame");
            return @intFromFloat(@max(frame.size.width, 0));
        }

        pub fn getHeight(self: *const T) u32 {
            const data = getEventUserData(self.peer);
            if (data.actual_height) |h| return h;
            const frame = self.peer.object.getProperty(AppKit.CGRect, "frame");
            return @intFromFloat(@max(frame.size.height, 0));
        }

        pub fn getPreferredSize(self: *const T) lib.Size {
            if (@hasDecl(T, "getPreferredSize_impl")) {
                return self.getPreferredSize_impl();
            }
            // Try NSView's intrinsicContentSize (returns -1 for no intrinsic size)
            const size = self.peer.object.msgSend(AppKit.CGSize, "intrinsicContentSize", .{});
            if (size.width >= 0 and size.height >= 0) {
                return lib.Size.init(
                    @max(@as(f32, @floatCast(size.width)), 20),
                    @max(@as(f32, @floatCast(size.height)), 16),
                );
            }
            return lib.Size.init(100, 100);
        }

        pub fn requestDraw(self: *T) !void {
            // setNeedsDisplay: must be called from the main thread on macOS.
            // When called from a background thread (e.g. animation loops),
            // dispatch via performSelectorOnMainThread: instead.
            const NSThread = objc.getClass("NSThread").?;
            const is_main = NSThread.msgSend(u8, "isMainThread", .{}) != 0;
            if (is_main) {
                self.peer.object.msgSend(void, "setNeedsDisplay:", .{@as(u8, 1)});
            } else {
                // display takes no arguments, so performSelectorOnMainThread: works cleanly
                self.peer.object.msgSend(void, "performSelectorOnMainThread:withObject:waitUntilDone:", .{
                    objc.sel("display"),
                    @as(?*anyopaque, null),
                    @as(u8, 0), // NO — don't block the background thread
                });
            }
        }

        pub fn deinit(self: *const T) void {
            const peer = self.peer;
            lib.internal.allocator.destroy(peer.data);
        }
    };
}

// ---------------------------------------------------------------------------
// Helpers for Container size tracking (mirrors GTK's widgetSizeChanged)
// ---------------------------------------------------------------------------

pub fn widgetSizeChanged(peer: GuiWidget, width: u32, height: u32) void {
    const data = getEventUserData(peer);
    data.actual_width = @intCast(@min(width, std.math.maxInt(u31)));
    data.actual_height = @intCast(@min(height, std.math.maxInt(u31)));
    if (data.class.resizeHandler) |handler|
        handler(width, height, @intFromPtr(data));
    if (data.user.resizeHandler) |handler|
        handler(width, height, data.userdata);
}

// ---------------------------------------------------------------------------
// Window helpers
// ---------------------------------------------------------------------------

/// Recursively find the maximum extent (x+width, y+height) of all subviews.
fn maxSubviewExtent(view: objc.Object) struct { width: AppKit.CGFloat, height: AppKit.CGFloat } {
    const subviews = view.msgSend(objc.Object, "subviews", .{});
    const count: usize = @intCast(subviews.msgSend(u64, "count", .{}));

    var max_w: AppKit.CGFloat = 0;
    var max_h: AppKit.CGFloat = 0;

    for (0..count) |i| {
        const subview = subviews.msgSend(objc.Object, "objectAtIndex:", .{@as(u64, @intCast(i))});
        const frame = subview.getProperty(AppKit.CGRect, "frame");

        // This subview's own extent
        const extent_w = frame.origin.x + frame.size.width;
        const extent_h = frame.origin.y + frame.size.height;
        max_w = @max(max_w, extent_w);
        max_h = @max(max_h, extent_h);

        // Check children recursively
        const child_extent = maxSubviewExtent(subview);
        max_w = @max(max_w, frame.origin.x + child_extent.width);
        max_h = @max(max_h, frame.origin.y + child_extent.height);
    }

    return .{ .width = max_w, .height = max_h };
}

/// Recursively collect interactive (focusable) controls from the view hierarchy.
/// A view is considered interactive if it's an editable NSTextField, NSButton,
/// NSSlider, or NSPopUpButton. Container views and labels are skipped.
/// Views are collected in subview order (which matches layout insertion order:
/// top-to-bottom for columns, left-to-right for rows).
fn collectFocusableViews(view: objc.Object, out: *std.ArrayList(objc.Object)) void {
    const subviews = view.msgSend(objc.Object, "subviews", .{});
    const count: usize = @intCast(subviews.msgSend(u64, "count", .{}));

    for (0..count) |i| {
        const subview = subviews.msgSend(objc.Object, "objectAtIndex:", .{@as(u64, @intCast(i))});

        // Check if this is an interactive control (not a container or label)
        const NSButtonClass = objc.getClass("NSButton");
        const NSTextFieldClass = objc.getClass("NSTextField");
        const NSSliderClass = objc.getClass("NSSlider");
        const NSPopUpButtonClass = objc.getClass("NSPopUpButton");

        const is_button = if (NSButtonClass) |cls| subview.msgSend(u8, "isKindOfClass:", .{cls}) != 0 else false;
        const is_textfield = if (NSTextFieldClass) |cls| subview.msgSend(u8, "isKindOfClass:", .{cls}) != 0 else false;
        const is_slider = if (NSSliderClass) |cls| subview.msgSend(u8, "isKindOfClass:", .{cls}) != 0 else false;
        const is_popup = if (NSPopUpButtonClass) |cls| subview.msgSend(u8, "isKindOfClass:", .{cls}) != 0 else false;

        if (is_popup) {
            // NSPopUpButton is a subclass of NSButton, check it first
            out.append(lib.internal.allocator, subview) catch {};
        } else if (is_button) {
            out.append(lib.internal.allocator, subview) catch {};
        } else if (is_slider) {
            out.append(lib.internal.allocator, subview) catch {};
        } else if (is_textfield) {
            // Only include editable text fields (not labels)
            const is_editable = subview.msgSend(u8, "isEditable", .{}) != 0;
            if (is_editable) {
                out.append(lib.internal.allocator, subview) catch {};
            }
            // Labels: skip (don't recurse either, labels have no focusable children)
        } else {
            // Container or unknown view: recurse into children
            collectFocusableViews(subview, out);
        }
    }
}

/// Build the key view loop for Tab/Shift-Tab navigation.
/// Walks the view hierarchy to find only interactive controls and chains
/// them via nextKeyView, forming a cycle.
fn buildKeyViewLoop(window: objc.Object) void {
    const content_view = window.msgSend(objc.Object, "contentView", .{});
    if (@intFromPtr(content_view.value) == 0) return;

    var focusable: std.ArrayList(objc.Object) = .empty;
    defer focusable.deinit(lib.internal.allocator);

    collectFocusableViews(content_view, &focusable);

    if (focusable.items.len < 2) return;

    // Chain each view to the next, with wrap-around
    for (0..focusable.items.len) |i| {
        const next_i = if (i + 1 < focusable.items.len) i + 1 else 0;
        focusable.items[i].msgSend(void, "setNextKeyView:", .{focusable.items[next_i].value});
    }

    // Note: we intentionally don't call setInitialFirstResponder: here
    // as it can interfere with the window becoming key.
}

/// Expand the window if its content's natural size exceeds the current
/// content area. Mimics GTK's auto-expansion from gtk_window_set_default_size.
fn expandWindowToFitContent(window: objc.Object) void {
    const content_view = window.msgSend(objc.Object, "contentView", .{});
    if (@intFromPtr(content_view.value) == 0) return;

    const content_frame = content_view.getProperty(AppKit.CGRect, "frame");
    const extent = maxSubviewExtent(content_view);

    var needs_resize = false;
    var new_w = content_frame.size.width;
    var new_h = content_frame.size.height;

    if (extent.width > content_frame.size.width) {
        new_w = extent.width;
        needs_resize = true;
    }
    if (extent.height > content_frame.size.height) {
        new_h = extent.height;
        needs_resize = true;
    }

    if (needs_resize) {
        window.msgSend(void, "setContentSize:", .{AppKit.CGSize{
            .width = new_w,
            .height = new_h,
        }});
        // Re-sync the child with the new content size
        syncChildToContentView(window);
    }
}

/// Synchronize the child contentView's frame and EventUserData with the
/// window's actual content area.  This is the macOS equivalent of GTK's
/// gtkLayout callback – it ensures the layout engine always works with the
/// real available size.
fn syncChildToContentView(window: objc.Object) void {
    const content_view = window.msgSend(objc.Object, "contentView", .{});
    if (@intFromPtr(content_view.value) == 0) return;

    const content_frame = content_view.getProperty(AppKit.CGRect, "frame");
    const w: u32 = @intFromFloat(@max(content_frame.size.width, 0));
    const h: u32 = @intFromFloat(@max(content_frame.size.height, 0));

    // Look up the class to see if this is one of our tracked views
    const class_name_ptr = objc.c.object_getClassName(content_view.value);
    const class_name = std.mem.sliceTo(class_name_ptr, 0);
    if (std.mem.eql(u8, class_name, "CapyEventView") or
        std.mem.eql(u8, class_name, "CapyCanvasView"))
    {
        if (getEventDataFromIvar(content_view)) |data| {
            const w_changed = if (data.actual_width) |old| w != old else true;
            const h_changed = if (data.actual_height) |old| h != old else true;
            data.actual_width = @intCast(@min(w, std.math.maxInt(u31)));
            data.actual_height = @intCast(@min(h, std.math.maxInt(u31)));
            if (w_changed or h_changed) {
                if (data.class.resizeHandler) |handler|
                    handler(w, h, @intFromPtr(data));
                if (data.user.resizeHandler) |handler|
                    handler(w, h, data.userdata);
            }
        }
    }
}

// CapyWindow - NSWindow subclass that intercepts Tab/Shift-Tab to manually
// navigate the key view chain, bypassing macOS's canBecomeKeyView checks
// which normally require Full Keyboard Access to be enabled in System Settings.
var cachedCapyWindow: ?objc.Class = null;

fn getCapyWindowClass() !objc.Class {
    if (cachedCapyWindow) |cls| return cls;

    const NSWindowClass = objc.getClass("NSWindow").?;
    const cls = objc.allocateClassPair(NSWindowClass, "CapyWindow") orelse return error.InitializationError;

    // Override sendEvent: to intercept Tab and Shift-Tab
    _ = cls.addMethod("sendEvent:", struct {
        fn imp(self_id: objc.c.id, _: objc.c.SEL, event_id: objc.c.id) callconv(.c) void {
            const event = objc.Object{ .value = event_id };
            const self_obj = objc.Object{ .value = self_id };

            // NSEventTypeKeyDown = 10
            const event_type: u64 = event.msgSend(u64, "type", .{});
            if (event_type == 10) {
                // Check for Tab character (0x09)
                const chars = event.msgSend(objc.Object, "characters", .{});
                const len: u64 = chars.msgSend(u64, "length", .{});
                if (len == 1) {
                    const ch: u16 = chars.msgSend(u16, "characterAtIndex:", .{@as(u64, 0)});
                    // Tab = 0x09, Backtab (Shift-Tab) = 0x19
                    if (ch == 0x09 or ch == 0x19) {
                        const shift_held = (ch == 0x19);

                        const first_responder = self_obj.msgSend(objc.Object, "firstResponder", .{});
                        if (@intFromPtr(first_responder.value) != 0) {
                            // For text fields, the first responder is the field editor (NSTextView),
                            // not the NSTextField itself. Get the actual delegate.
                            var current_view = first_responder;
                            const NSTextViewClass = objc.getClass("NSTextView");
                            if (NSTextViewClass) |tvc| {
                                if (current_view.msgSend(u8, "isKindOfClass:", .{tvc}) != 0) {
                                    // Field editor: get the delegate which is the NSTextField
                                    const delegate = current_view.msgSend(objc.Object, "delegate", .{});
                                    if (@intFromPtr(delegate.value) != 0) {
                                        current_view = delegate;
                                    }
                                }
                            }

                            const next_view = if (shift_held)
                                current_view.msgSend(objc.Object, "previousKeyView", .{})
                            else
                                current_view.msgSend(objc.Object, "nextKeyView", .{});

                            if (@intFromPtr(next_view.value) != 0) {
                                _ = self_obj.msgSend(u8, "makeFirstResponder:", .{next_view.value});
                                return; // Consume the event
                            }
                        }
                    }

                    // Arrow keys on focused slider: adjust value
                    // Left=0xF702, Right=0xF703, Up=0xF700, Down=0xF701
                    if (ch == 0xF700 or ch == 0xF701 or ch == 0xF702 or ch == 0xF703) {
                        const first_responder = self_obj.msgSend(objc.Object, "firstResponder", .{});
                        if (@intFromPtr(first_responder.value) != 0) {
                            const NSSliderClass = objc.getClass("NSSlider");
                            if (NSSliderClass) |slider_cls| {
                                if (first_responder.msgSend(u8, "isKindOfClass:", .{slider_cls}) != 0) {
                                    const is_vertical: u8 = first_responder.msgSend(u8, "isVertical", .{});
                                    const cur: f64 = first_responder.msgSend(f64, "doubleValue", .{});
                                    const min_v: f64 = first_responder.msgSend(f64, "minValue", .{});
                                    const max_v: f64 = first_responder.msgSend(f64, "maxValue", .{});
                                    const num_ticks: i64 = first_responder.msgSend(i64, "numberOfTickMarks", .{});
                                    // Step: use tick interval if available, otherwise 1% of range
                                    const step: f64 = if (num_ticks > 1)
                                        (max_v - min_v) / @as(f64, @floatFromInt(num_ticks - 1))
                                    else
                                        (max_v - min_v) / 100.0;
                                    // Determine direction based on key and orientation
                                    const increase = if (is_vertical != 0)
                                        (ch == 0xF700) // Up increases for vertical
                                    else
                                        (ch == 0xF703); // Right increases for horizontal
                                    const decrease = if (is_vertical != 0)
                                        (ch == 0xF701) // Down decreases for vertical
                                    else
                                        (ch == 0xF702); // Left decreases for horizontal
                                    if (increase or decrease) {
                                        var new_val = if (increase) cur + step else cur - step;
                                        // Clamp to range
                                        if (new_val < min_v) new_val = min_v;
                                        if (new_val > max_v) new_val = max_v;
                                        first_responder.msgSend(void, "setDoubleValue:", .{new_val});
                                        // Trigger the action to update the Capy component
                                        // Use NSApp sendAction:to:from: since we have a raw SEL
                                        if (objc.getClass("NSApplication")) |nsapp| {
                                            const app = nsapp.msgSend(objc.Object, "sharedApplication", .{});
                                            _ = app.msgSend(u8, "sendAction:to:from:", .{
                                                first_responder.msgSend(objc.c.SEL, "action", .{}),
                                                first_responder.msgSend(objc.Object, "target", .{}).value,
                                                first_responder.value,
                                            });
                                        }
                                        return; // Consume the event
                                    }
                                }
                            }
                        }
                    }

                    // Space (0x20) or Return (0x0D) or Enter (0x03): activate focused control
                    if (ch == 0x20 or ch == 0x0D or ch == 0x03) {
                        const first_responder = self_obj.msgSend(objc.Object, "firstResponder", .{});
                        if (@intFromPtr(first_responder.value) != 0) {
                            const NSControlClass = objc.getClass("NSControl");
                            if (NSControlClass) |ctrl_cls| {
                                if (first_responder.msgSend(u8, "isKindOfClass:", .{ctrl_cls}) != 0) {
                                    first_responder.msgSend(void, "performClick:", .{self_obj.value});
                                    return; // Consume the event
                                }
                            }
                        }
                    }
                }
            }

            // For all other events, call super's sendEvent:
            const SuperClass = objc.getClass("NSWindow").?;
            self_obj.msgSendSuper(SuperClass, void, "sendEvent:", .{event});
        }
    }.imp);

    objc.registerClassPair(cls);
    cachedCapyWindow = cls;
    return cls;
}

// CapyWindowDelegate - receives windowDidResize: notifications
var cachedCapyWindowDelegate: ?objc.Class = null;

fn getCapyWindowDelegateClass() !objc.Class {
    if (cachedCapyWindowDelegate) |cls| return cls;

    const NSObjectClass = objc.getClass("NSObject").?;
    const cls = objc.allocateClassPair(NSObjectClass, "CapyWindowDelegate") orelse return error.InitializationError;

    if (!cls.addIvar("capy_window")) return error.InitializationError;

    _ = cls.addMethod("windowDidResize:", struct {
        fn imp(self_id: objc.c.id, _: objc.c.SEL, _: objc.c.id) callconv(.c) void {
            const self_obj = objc.Object{ .value = self_id };
            const window_obj = self_obj.getInstanceVariable("capy_window");
            if (@intFromPtr(window_obj.value) == 0) return;
            const window = objc.Object{ .value = window_obj.value };
            syncChildToContentView(window);
        }
    }.imp);

    objc.registerClassPair(cls);
    cachedCapyWindowDelegate = cls;
    return cls;
}

// ---------------------------------------------------------------------------
// Window
// ---------------------------------------------------------------------------

pub const Window = struct {
    source_dpi: u32 = 96,
    scale: f32 = 1.0,
    peer: GuiWidget,

    const _events = Events(@This());
    pub const setupEvents = _events.setupEvents;
    pub const setUserData = _events.setUserData;
    pub const setCallback = _events.setCallback;
    pub const setOpacity = _events.setOpacity;
    pub const getX = _events.getX;
    pub const getY = _events.getY;
    pub const getWidth = _events.getWidth;
    pub const getHeight = _events.getHeight;
    pub const getPreferredSize = _events.getPreferredSize;
    pub const requestDraw = _events.requestDraw;
    pub const deinit = _events.deinit;

    pub fn registerTickCallback(self: *Window) void {
        _ = self;
        // TODO: NSTimer or CVDisplayLink for tick callbacks
    }

    pub fn create() BackendError!Window {
        const CapyWindow = try getCapyWindowClass();
        const rect = AppKit.NSRect.make(0, 0, 800, 600);
        const style = AppKit.NSWindowStyleMask.Titled | AppKit.NSWindowStyleMask.Closable | AppKit.NSWindowStyleMask.Miniaturizable | AppKit.NSWindowStyleMask.Resizable;
        const flag: u8 = @intFromBool(false);

        const window = CapyWindow.msgSend(objc.Object, "alloc", .{});
        _ = window.msgSend(
            objc.Object,
            "initWithContentRect:styleMask:backing:defer:",
            .{ rect, style, AppKit.NSBackingStore.Buffered, flag },
        );

        // Set up window delegate for resize notifications
        const delegate_cls = getCapyWindowDelegateClass() catch null;
        if (delegate_cls) |cls| {
            const delegate = cls.msgSend(objc.Object, "alloc", .{}).msgSend(objc.Object, "init", .{});
            delegate.setInstanceVariable("capy_window", window);
            window.msgSend(void, "setDelegate:", .{delegate.value});
        }

        const data = try lib.internal.allocator.create(EventUserData);
        data.* = EventUserData{ .peer = window };

        return Window{
            .peer = GuiWidget{
                .object = window,
                .data = data,
            },
        };
    }

    pub fn resize(self: *Window, width: c_int, height: c_int) void {
        // Use setContentSize: so the content area (not the window frame including
        // title bar) gets the requested dimensions.
        self.peer.object.msgSend(void, "setContentSize:", .{AppKit.CGSize{
            .width = @floatFromInt(width),
            .height = @floatFromInt(height),
        }});
        // Propagate to child contentView
        syncChildToContentView(self.peer.object);
    }

    pub fn setTitle(self: *Window, title: [*:0]const u8) void {
        const pool = objc.AutoreleasePool.init();
        defer pool.deinit();

        self.peer.object.setProperty("title", AppKit.nsString(title));
    }

    pub fn setIcon(self: *Window, icon_data: lib.ImageData) void {
        _ = self;
        const pool = objc.AutoreleasePool.init();
        defer pool.deinit();

        const cg_image = icon_data.peer.cg_image orelse return;

        const NSImage_class = objc.getClass("NSImage") orelse return;
        const ns_image = NSImage_class.msgSend(objc.Object, "alloc", .{});
        const size = AppKit.CGSize{
            .width = @floatFromInt(icon_data.width),
            .height = @floatFromInt(icon_data.height),
        };
        const initialized = ns_image.msgSend(objc.Object, "initWithCGImage:size:", .{ cg_image, size });

        const NSApp_class = objc.getClass("NSApplication") orelse return;
        const app = NSApp_class.msgSend(objc.Object, "sharedApplication", .{});
        app.msgSend(void, "setApplicationIconImage:", .{initialized});
    }

    pub fn setChild(self: *Window, optional_peer: ?GuiWidget) void {
        if (optional_peer) |peer| {
            self.peer.object.setProperty("contentView", peer);
            // Immediately size the child to match the content area
            syncChildToContentView(self.peer.object);
        } else {
            self.peer.object.setProperty("contentView", nil);
        }
    }

    pub fn setSourceDpi(self: *Window, dpi: u32) void {
        self.source_dpi = 96;
        const resolution = @as(f32, 96.0);
        self.scale = resolution / @as(f32, @floatFromInt(dpi));
    }

    pub fn show(self: *Window) void {
        // Auto-expand window to fit content if content overflows.
        // This mimics GTK's gtk_window_set_default_size behavior where the
        // window expands to accommodate its content's natural size.
        expandWindowToFitContent(self.peer.object);

        // Try to restore saved window position using the window title as autosave name.
        // setFrameAutosaveName: automatically saves position on move/resize and
        // restores it if a saved frame exists. Only center if no frame was restored.
        var restored = false;
        const title = self.peer.object.getProperty(objc.Object, "title");
        const title_len: u64 = title.msgSend(u64, "length", .{});
        if (title_len > 0) {
            const frame_before = self.peer.object.getProperty(AppKit.CGRect, "frame");
            _ = self.peer.object.msgSend(u8, "setFrameAutosaveName:", .{title.value});
            const frame_after = self.peer.object.getProperty(AppKit.CGRect, "frame");
            // If the frame changed, a saved position was restored
            restored = (frame_before.origin.x != frame_after.origin.x or
                frame_before.origin.y != frame_after.origin.y or
                frame_before.size.width != frame_after.size.width or
                frame_before.size.height != frame_after.size.height);
        }

        if (!restored) {
            // Center window on screen as a sensible default
            self.peer.object.msgSend(void, "center", .{});
        }

        self.peer.object.msgSend(void, "makeKeyAndOrderFront:", .{self.peer.object.value});
        _ = activeWindows.fetchAdd(1, .release);

        // Build the key view loop for Tab/Shift-Tab navigation AFTER
        // the window is key, including only interactive controls
        buildKeyViewLoop(self.peer.object);
    }

    pub fn close(self: *Window) void {
        self.peer.object.msgSend(void, "close", .{});
        _ = activeWindows.fetchSub(1, .release);
    }

    pub fn setMenuBar(self: *Window, bar: anytype) void {
        _ = self;
        const NSMenu = objc.getClass("NSMenu") orelse return;
        const menu_target_cls = getCapyMenuTargetClass() catch return;

        const menubar = NSMenu.msgSend(objc.Object, "alloc", .{}).msgSend(objc.Object, "init", .{});

        // Always add the application menu with Quit as the first item
        const NSMenuItem = objc.getClass("NSMenuItem") orelse return;
        const app_menu_item = NSMenuItem.msgSend(objc.Object, "alloc", .{}).msgSend(objc.Object, "init", .{});
        menubar.msgSend(void, "addItem:", .{app_menu_item.value});

        const app_menu = NSMenu.msgSend(objc.Object, "alloc", .{}).msgSend(objc.Object, "init", .{});
        const quit_item = NSMenuItem.msgSend(objc.Object, "alloc", .{}).msgSend(objc.Object, "init", .{});
        quit_item.msgSend(void, "setTitle:", .{AppKit.nsString("Quit")});
        quit_item.setProperty("action", objc.sel("terminate:"));
        quit_item.msgSend(void, "setKeyEquivalent:", .{AppKit.nsString("q")});
        app_menu.msgSend(void, "addItem:", .{quit_item.value});
        app_menu_item.msgSend(void, "setSubmenu:", .{app_menu.value});

        // Add user-defined menus
        for (bar.menus) |menu_item| {
            const item = createMenuItemFromConfig(menu_item, menu_target_cls);
            menubar.msgSend(void, "addItem:", .{item.value});
        }

        // Set as application's main menu
        const app = objc.getClass("NSApplication").?.msgSend(objc.Object, "sharedApplication", .{});
        app.msgSend(void, "setMainMenu:", .{menubar.value});
    }

    pub fn setFullscreen(self: *Window, monitor: anytype, video_mode: anytype) void {
        _ = monitor;
        _ = video_mode;
        self.peer.object.msgSend(void, "toggleFullScreen:", .{self.peer.object.value});
    }

    pub fn unfullscreen(self: *Window) void {
        self.peer.object.msgSend(void, "toggleFullScreen:", .{self.peer.object.value});
    }
};

// ---------------------------------------------------------------------------
// Container
// ---------------------------------------------------------------------------

pub const Container = struct {
    peer: GuiWidget,

    const _events = Events(@This());
    pub const setupEvents = _events.setupEvents;
    pub const setUserData = _events.setUserData;
    pub const setCallback = _events.setCallback;
    pub const setOpacity = _events.setOpacity;
    pub const getX = _events.getX;
    pub const getY = _events.getY;
    pub const getWidth = _events.getWidth;
    pub const getHeight = _events.getHeight;
    pub const getPreferredSize = _events.getPreferredSize;
    pub const requestDraw = _events.requestDraw;
    pub const deinit = _events.deinit;

    pub fn create() BackendError!Container {
        const cls = try getCapyEventViewClass();
        const view = cls.msgSend(objc.Object, "alloc", .{})
            .msgSend(objc.Object, "initWithFrame:", .{AppKit.NSRect.make(0, 0, 1, 1)});
        const data = try lib.internal.allocator.create(EventUserData);
        data.* = EventUserData{ .peer = view };
        setEventDataIvar(view, data);
        addTrackingArea(view);
        return Container{ .peer = GuiWidget{
            .object = view,
            .data = data,
        } };
    }

    pub fn add(self: *const Container, peer: GuiWidget) void {
        self.peer.object.msgSend(void, "addSubview:", .{peer.object});
    }

    pub fn remove(self: *const Container, peer: GuiWidget) void {
        _ = self;
        peer.object.msgSend(void, "removeFromSuperview", .{});
    }

    pub fn move(self: *const Container, peer: GuiWidget, x: u32, y: u32) void {
        _ = self;
        const peerFrame = peer.object.getProperty(AppKit.NSRect, "frame");
        peer.object.setProperty("frame", AppKit.NSRect.make(
            @floatFromInt(x),
            @floatFromInt(y),
            peerFrame.size.width,
            peerFrame.size.height,
        ));
        const data = getEventUserData(peer);
        data.actual_x = @intCast(x);
        data.actual_y = @intCast(y);
    }

    pub fn resize(self: *const Container, peer: GuiWidget, width: u32, height: u32) void {
        _ = self;
        const peerFrame = peer.object.getProperty(AppKit.NSRect, "frame");
        peer.object.setProperty("frame", AppKit.NSRect.make(
            peerFrame.origin.x,
            peerFrame.origin.y,
            @floatFromInt(width),
            @floatFromInt(height),
        ));
        widgetSizeChanged(peer, width, height);

        // If the resized widget is an NSScrollView, propagate the size to its
        // document view so the child container layout has correct available space.
        // GTK handles this automatically; on macOS we must do it explicitly.
        const class_name = std.mem.sliceTo(objc.c.object_getClassName(peer.object.value), 0);
        if (std.mem.eql(u8, class_name, "NSScrollView")) {
            const doc_view = peer.object.msgSend(objc.Object, "documentView", .{});
            if (doc_view.value != null) {
                if (getEventDataFromIvar(doc_view)) |doc_data| {
                    const content_size = peer.object.msgSend(AppKit.CGSize, "contentSize", .{});
                    const vp_w: u32 = @intFromFloat(@max(content_size.width, 0));

                    // Phase 1: Set document view to viewport width × large height so
                    // the column layout gives children their preferred sizes (not compressed).
                    doc_view.setProperty("frame", AppKit.NSRect.make(0, 0, content_size.width, 100000));
                    const doc_peer = GuiWidget{ .object = doc_view, .data = doc_data };
                    widgetSizeChanged(doc_peer, vp_w, 100000);

                    // Phase 2: After relayout, measure actual content extent and
                    // shrink-wrap the document view. If content > viewport, scrollbars appear.
                    const extent = maxSubviewExtent(doc_view);
                    const final_h = @max(extent.height, content_size.height);
                    doc_view.setProperty("frame", AppKit.NSRect.make(0, 0, content_size.width, final_h));
                    doc_data.actual_height = @intFromFloat(@min(@max(final_h, 0), @as(AppKit.CGFloat, @floatFromInt(std.math.maxInt(u31)))));
                }
            }
        }
    }

    pub fn setTabOrder(self: *const Container, peers: []const GuiWidget) void {
        // No-op on macOS: we use autorecalculatesKeyViewLoop on NSWindow instead,
        // which builds a single flat key view chain from the entire view hierarchy
        // based on geometric position (top-to-bottom, left-to-right).
        // Per-container loops would conflict with the global chain.
        _ = self;
        _ = peers;
    }
};

// ---------------------------------------------------------------------------
// Canvas
// ---------------------------------------------------------------------------

pub const Canvas = struct {
    peer: GuiWidget,

    const _events = Events(@This());
    pub const setupEvents = _events.setupEvents;
    pub const setUserData = _events.setUserData;
    pub const setCallback = _events.setCallback;
    pub const setOpacity = _events.setOpacity;
    pub const getX = _events.getX;
    pub const getY = _events.getY;
    pub const getWidth = _events.getWidth;
    pub const getHeight = _events.getHeight;
    pub const getPreferredSize = _events.getPreferredSize;
    pub const requestDraw = _events.requestDraw;
    pub const deinit = _events.deinit;

    pub fn create() BackendError!Canvas {
        const cls = try getCapyCanvasViewClass();
        const view = cls.msgSend(objc.Object, "alloc", .{})
            .msgSend(objc.Object, "initWithFrame:", .{AppKit.NSRect.make(0, 0, 1, 1)});
        const data = try lib.internal.allocator.create(EventUserData);
        data.* = EventUserData{ .peer = view };
        setEventDataIvar(view, data);
        addTrackingArea(view);
        return Canvas{
            .peer = GuiWidget{
                .object = view,
                .data = data,
            },
        };
    }

    pub const DrawContextImpl = struct {
        cg_context: AppKit.CGContextRef,
        pending_gradient: ?shared.LinearGradient = null,

        pub const TextLayout = struct {
            wrap: ?f64 = null,
            font: ?AppKit.CTFontRef = null,

            pub const Font = struct {
                face: [:0]const u8,
                size: f64,
            };

            pub const TextSize = struct { width: u32, height: u32 };

            pub fn init() TextLayout {
                return TextLayout{};
            }

            pub fn setFont(self: *TextLayout, font: Font) void {
                if (self.font) |old| AppKit.CFRelease(old);
                const cf_name = AppKit.CFStringCreateWithBytes(
                    AppKit.kCFAllocatorDefault,
                    font.face.ptr,
                    @intCast(font.face.len),
                    AppKit.CFStringEncoding_UTF8,
                    0,
                );
                defer if (cf_name != null) AppKit.CFRelease(cf_name);
                self.font = AppKit.CTFontCreateWithName(cf_name, font.size, null);
            }

            pub fn getTextSize(self: *TextLayout, str: []const u8) TextSize {
                if (str.len == 0) return TextSize{ .width = 0, .height = 0 };

                const cf_str = AppKit.CFStringCreateWithBytes(
                    AppKit.kCFAllocatorDefault,
                    str.ptr,
                    @intCast(str.len),
                    AppKit.CFStringEncoding_UTF8,
                    0,
                );
                defer if (cf_str != null) AppKit.CFRelease(cf_str);
                if (cf_str == null) return TextSize{ .width = 0, .height = 0 };

                var attr_string: AppKit.CFAttributedStringRef = null;
                if (self.font) |f| {
                    const keys = [_]?*const anyopaque{@as(?*const anyopaque, @ptrCast(AppKit.kCTFontAttributeName))};
                    const values = [_]?*const anyopaque{@as(?*const anyopaque, @ptrCast(f))};
                    const attrs = AppKit.CFDictionaryCreate(
                        AppKit.kCFAllocatorDefault,
                        &keys,
                        &values,
                        1,
                        &AppKit.kCFTypeDictionaryKeyCallBacks,
                        &AppKit.kCFTypeDictionaryValueCallBacks,
                    );
                    defer if (attrs != null) AppKit.CFRelease(attrs);
                    attr_string = AppKit.CFAttributedStringCreate(AppKit.kCFAllocatorDefault, cf_str, attrs);
                } else {
                    attr_string = AppKit.CFAttributedStringCreate(AppKit.kCFAllocatorDefault, cf_str, null);
                }
                defer if (attr_string != null) AppKit.CFRelease(attr_string);
                if (attr_string == null) return TextSize{ .width = 0, .height = 0 };

                const ct_line = AppKit.CTLineCreateWithAttributedString(attr_string);
                defer if (ct_line != null) AppKit.CFRelease(ct_line);
                if (ct_line == null) return TextSize{ .width = 0, .height = 0 };

                var ascent: AppKit.CGFloat = 0;
                var descent: AppKit.CGFloat = 0;
                var leading: AppKit.CGFloat = 0;
                const width = AppKit.CTLineGetTypographicBounds(ct_line, &ascent, &descent, &leading);
                const height = ascent + descent + leading;

                return TextSize{
                    .width = @intFromFloat(@ceil(width)),
                    .height = @intFromFloat(@ceil(height)),
                };
            }

            pub fn deinit(self: *TextLayout) void {
                if (self.font) |f| AppKit.CFRelease(f);
                self.font = null;
            }
        };

        pub fn setColorRGBA(self: *DrawContextImpl, r: f32, g: f32, b: f32, a: f32) void {
            self.pending_gradient = null;
            AppKit.CGContextSetRGBFillColor(self.cg_context, r, g, b, a);
            AppKit.CGContextSetRGBStrokeColor(self.cg_context, r, g, b, a);
        }

        pub fn setLinearGradient(self: *DrawContextImpl, gradient: shared.LinearGradient) void {
            self.pending_gradient = gradient;
        }

        pub fn rectangle(self: *DrawContextImpl, x: i32, y: i32, w: u32, h: u32) void {
            AppKit.CGContextAddRect(self.cg_context, AppKit.CGRect.make(
                @floatFromInt(x),
                @floatFromInt(y),
                @floatFromInt(w),
                @floatFromInt(h),
            ));
        }

        pub fn roundedRectangleEx(self: *DrawContextImpl, x: i32, y: i32, w: u32, h: u32, corner_radiuses: [4]f32) void {
            const fx: AppKit.CGFloat = @floatFromInt(x);
            const fy: AppKit.CGFloat = @floatFromInt(y);
            const fw: AppKit.CGFloat = @floatFromInt(w);
            const fh: AppKit.CGFloat = @floatFromInt(h);

            const max_radius = @min(fw, fh) / 2.0;
            const tl: AppKit.CGFloat = @min(@as(AppKit.CGFloat, @floatCast(corner_radiuses[0])), max_radius);
            const tr: AppKit.CGFloat = @min(@as(AppKit.CGFloat, @floatCast(corner_radiuses[1])), max_radius);
            const br: AppKit.CGFloat = @min(@as(AppKit.CGFloat, @floatCast(corner_radiuses[2])), max_radius);
            const bl: AppKit.CGFloat = @min(@as(AppKit.CGFloat, @floatCast(corner_radiuses[3])), max_radius);

            AppKit.CGContextBeginPath(self.cg_context);
            AppKit.CGContextMoveToPoint(self.cg_context, fx + tl, fy);
            AppKit.CGContextAddArcToPoint(self.cg_context, fx + fw, fy, fx + fw, fy + tr, tr);
            AppKit.CGContextAddArcToPoint(self.cg_context, fx + fw, fy + fh, fx + fw - br, fy + fh, br);
            AppKit.CGContextAddArcToPoint(self.cg_context, fx, fy + fh, fx, fy + fh - bl, bl);
            AppKit.CGContextAddArcToPoint(self.cg_context, fx, fy, fx + tl, fy, tl);
            AppKit.CGContextClosePath(self.cg_context);
        }

        pub fn ellipse(self: *DrawContextImpl, x: i32, y: i32, w: u32, h: u32) void {
            AppKit.CGContextAddEllipseInRect(self.cg_context, AppKit.CGRect.make(
                @floatFromInt(x),
                @floatFromInt(y),
                @floatFromInt(w),
                @floatFromInt(h),
            ));
        }

        pub fn text(self: *DrawContextImpl, x: i32, y: i32, layout: TextLayout, str: []const u8) void {
            if (str.len == 0) return;

            const cf_str = AppKit.CFStringCreateWithBytes(
                AppKit.kCFAllocatorDefault,
                str.ptr,
                @intCast(str.len),
                AppKit.CFStringEncoding_UTF8,
                0,
            );
            defer if (cf_str != null) AppKit.CFRelease(cf_str);
            if (cf_str == null) return;

            var attr_string: AppKit.CFAttributedStringRef = null;
            if (layout.font) |f| {
                const keys = [_]?*const anyopaque{@as(?*const anyopaque, @ptrCast(AppKit.kCTFontAttributeName))};
                const values = [_]?*const anyopaque{@as(?*const anyopaque, @ptrCast(f))};
                const attrs = AppKit.CFDictionaryCreate(
                    AppKit.kCFAllocatorDefault,
                    &keys,
                    &values,
                    1,
                    &AppKit.kCFTypeDictionaryKeyCallBacks,
                    &AppKit.kCFTypeDictionaryValueCallBacks,
                );
                defer if (attrs != null) AppKit.CFRelease(attrs);
                attr_string = AppKit.CFAttributedStringCreate(AppKit.kCFAllocatorDefault, cf_str, attrs);
            } else {
                attr_string = AppKit.CFAttributedStringCreate(AppKit.kCFAllocatorDefault, cf_str, null);
            }
            defer if (attr_string != null) AppKit.CFRelease(attr_string);
            if (attr_string == null) return;

            const ct_line = AppKit.CTLineCreateWithAttributedString(attr_string);
            defer if (ct_line != null) AppKit.CFRelease(ct_line);
            if (ct_line == null) return;

            // CoreText uses bottom-left origin; flip locally for correct rendering
            var text_ascent: AppKit.CGFloat = 0;
            var text_descent: AppKit.CGFloat = 0;
            var text_leading: AppKit.CGFloat = 0;
            _ = AppKit.CTLineGetTypographicBounds(ct_line, &text_ascent, &text_descent, &text_leading);

            AppKit.CGContextSaveGState(self.cg_context);
            AppKit.CGContextTranslateCTM(self.cg_context, @floatFromInt(x), @as(AppKit.CGFloat, @floatFromInt(y)) + text_ascent);
            AppKit.CGContextScaleCTM(self.cg_context, 1.0, -1.0);
            AppKit.CGContextSetTextPosition(self.cg_context, 0, 0);
            AppKit.CTLineDraw(ct_line, self.cg_context);
            AppKit.CGContextRestoreGState(self.cg_context);
        }

        pub fn line(self: *DrawContextImpl, x1: i32, y1: i32, x2: i32, y2: i32) void {
            AppKit.CGContextMoveToPoint(self.cg_context, @floatFromInt(x1), @floatFromInt(y1));
            AppKit.CGContextAddLineToPoint(self.cg_context, @floatFromInt(x2), @floatFromInt(y2));
            AppKit.CGContextStrokePath(self.cg_context);
        }

        pub fn image(self: *DrawContextImpl, x: i32, y: i32, w: u32, h: u32, data: lib.ImageData) void {
            const cg_image = data.peer.cg_image orelse return;
            // CGContextDrawImage uses bottom-left origin; flip locally
            AppKit.CGContextSaveGState(self.cg_context);
            AppKit.CGContextTranslateCTM(self.cg_context, @floatFromInt(x), @as(AppKit.CGFloat, @floatFromInt(y)) + @as(AppKit.CGFloat, @floatFromInt(h)));
            AppKit.CGContextScaleCTM(self.cg_context, 1.0, -1.0);
            AppKit.CGContextDrawImage(self.cg_context, AppKit.CGRect.make(0, 0, @floatFromInt(w), @floatFromInt(h)), cg_image);
            AppKit.CGContextRestoreGState(self.cg_context);
        }

        pub fn clear(self: *DrawContextImpl, x: u32, y: u32, w: u32, h: u32) void {
            AppKit.CGContextClearRect(self.cg_context, AppKit.CGRect.make(
                @floatFromInt(x),
                @floatFromInt(y),
                @floatFromInt(w),
                @floatFromInt(h),
            ));
        }

        pub fn setStrokeWidth(self: *DrawContextImpl, width: f32) void {
            AppKit.CGContextSetLineWidth(self.cg_context, @floatCast(width));
        }

        pub fn stroke(self: *DrawContextImpl) void {
            AppKit.CGContextStrokePath(self.cg_context);
        }

        pub fn fill(self: *DrawContextImpl) void {
            if (self.pending_gradient) |gradient| {
                AppKit.CGContextSaveGState(self.cg_context);
                AppKit.CGContextClip(self.cg_context);

                const color_space = AppKit.CGColorSpaceCreateDeviceRGB();
                defer AppKit.CGColorSpaceRelease(color_space);

                const max_stops = 16;
                var components: [max_stops * 4]AppKit.CGFloat = undefined;
                var locations: [max_stops]AppKit.CGFloat = undefined;
                const count = @min(gradient.stops.len, max_stops);
                for (0..count) |i| {
                    const stop = gradient.stops[i];
                    components[i * 4 + 0] = @as(AppKit.CGFloat, @floatFromInt(stop.color.red)) / 255.0;
                    components[i * 4 + 1] = @as(AppKit.CGFloat, @floatFromInt(stop.color.green)) / 255.0;
                    components[i * 4 + 2] = @as(AppKit.CGFloat, @floatFromInt(stop.color.blue)) / 255.0;
                    components[i * 4 + 3] = @as(AppKit.CGFloat, @floatFromInt(stop.color.alpha)) / 255.0;
                    locations[i] = @floatCast(stop.offset);
                }

                const cg_gradient = AppKit.CGGradientCreateWithColorComponents(
                    color_space,
                    &components,
                    &locations,
                    count,
                );
                defer if (cg_gradient != null) AppKit.CGGradientRelease(cg_gradient);

                if (cg_gradient != null) {
                    AppKit.CGContextDrawLinearGradient(
                        self.cg_context,
                        cg_gradient,
                        AppKit.CGPoint{ .x = @floatCast(gradient.x0), .y = @floatCast(gradient.y0) },
                        AppKit.CGPoint{ .x = @floatCast(gradient.x1), .y = @floatCast(gradient.y1) },
                        AppKit.CGGradientDrawingOptions.DrawsBeforeStartLocation | AppKit.CGGradientDrawingOptions.DrawsAfterEndLocation,
                    );
                }

                AppKit.CGContextRestoreGState(self.cg_context);
                self.pending_gradient = null;
            } else {
                AppKit.CGContextFillPath(self.cg_context);
            }
        }
    };
};

// ---------------------------------------------------------------------------
// postEmptyEvent / runStep
// ---------------------------------------------------------------------------

pub fn postEmptyEvent() void {
    const pool = objc.AutoreleasePool.init();
    defer pool.deinit();

    const NSEvent = objc.getClass("NSEvent") orelse return;
    const event = NSEvent.msgSend(objc.Object, "otherEventWithType:location:modifierFlags:timestamp:windowNumber:context:subtype:data1:data2:", .{
        AppKit.NSEventType.ApplicationDefined,
        AppKit.CGPoint{ .x = 0, .y = 0 },
        @as(AppKit.NSUInteger, 0),
        @as(AppKit.CGFloat, 0),
        @as(i64, 0),
        @as(objc.c.id, null),
        @as(i16, 0),
        @as(i64, 0),
        @as(i64, 0),
    });
    if (event.value == null) return;

    const NSApplication = objc.getClass("NSApplication").?;
    const app = NSApplication.msgSend(objc.Object, "sharedApplication", .{});
    app.msgSend(void, "postEvent:atStart:", .{ event, @as(u8, @intFromBool(true)) });
}

pub fn runStep(step: shared.EventLoopStep) bool {
    const NSApplication = objc.getClass("NSApplication").?;
    const app = NSApplication.msgSend(objc.Object, "sharedApplication", .{});
    if (!finishedLaunching) {
        finishedLaunching = true;
        if (step == .Blocking) {
            app.msgSend(void, "run", .{});
        }
    }

    const pool = objc.AutoreleasePool.init();
    defer pool.deinit();

    const NSDate = objc.getClass("NSDate").?;
    const distant_past = NSDate.msgSend(objc.Object, "distantPast", .{});
    const distant_future = NSDate.msgSend(objc.Object, "distantFuture", .{});

    const event = app.msgSend(objc.Object, "nextEventMatchingMask:untilDate:inMode:dequeue:", .{
        AppKit.NSEventMaskAny,
        switch (step) {
            .Asynchronous => distant_past,
            .Blocking => distant_future,
        },
        AppKit.NSDefaultRunLoopMode,
        true,
    });
    if (event.value != null) {
        app.msgSend(void, "sendEvent:", .{event});
    }
    return activeWindows.load(.acquire) != 0;
}

// ---------------------------------------------------------------------------
// Label
// ---------------------------------------------------------------------------

pub const Label = struct {
    peer: GuiWidget,

    const _events = Events(@This());
    pub const setupEvents = _events.setupEvents;
    pub const setUserData = _events.setUserData;
    pub const setCallback = _events.setCallback;
    pub const setOpacity = _events.setOpacity;
    pub const getX = _events.getX;
    pub const getY = _events.getY;
    pub const getWidth = _events.getWidth;
    pub const getHeight = _events.getHeight;
    pub const getPreferredSize = _events.getPreferredSize;
    pub const requestDraw = _events.requestDraw;
    pub const deinit = _events.deinit;

    pub fn create() !Label {
        const NSTextField = objc.getClass("NSTextField").?;
        const label = NSTextField.msgSend(objc.Object, "labelWithString:", .{AppKit.nsString("")});
        // Labels should never steal keyboard focus
        label.msgSend(void, "setRefusesFirstResponder:", .{@as(u8, @intFromBool(true))});
        const data = try lib.internal.allocator.create(EventUserData);
        data.* = EventUserData{ .peer = label };
        return Label{
            .peer = GuiWidget{
                .object = label,
                .data = data,
            },
        };
    }

    pub fn setAlignment(self: *Label, alignment: f32) void {
        // NSTextAlignment: 0=Left, 1=Right, 2=Center
        const ns_alignment: AppKit.NSUInteger = if (alignment < 0.33)
            0
        else if (alignment > 0.66)
            1
        else
            2;
        self.peer.object.setProperty("alignment", ns_alignment);
    }

    pub fn setText(self: *Label, text_arg: []const u8) void {
        const nullTerminatedText = lib.internal.allocator.dupeZ(u8, text_arg) catch return;
        defer lib.internal.allocator.free(nullTerminatedText);
        self.peer.object.msgSend(void, "setStringValue:", .{AppKit.nsString(nullTerminatedText)});
    }

    pub fn setFont(self: *Label, font: lib.Font) void {
        _ = self;
        _ = font;
    }

    pub fn destroy(self: *Label) void {
        _ = self;
    }
};

// ---------------------------------------------------------------------------
// ScrollView
// ---------------------------------------------------------------------------

pub const ScrollView = struct {
    peer: GuiWidget,

    const _events = Events(@This());
    pub const setupEvents = _events.setupEvents;
    pub const setUserData = _events.setUserData;
    pub const setCallback = _events.setCallback;
    pub const setOpacity = _events.setOpacity;
    pub const getX = _events.getX;
    pub const getY = _events.getY;
    pub const getWidth = _events.getWidth;
    pub const getHeight = _events.getHeight;
    pub const getPreferredSize = _events.getPreferredSize;
    pub const requestDraw = _events.requestDraw;
    pub const deinit = _events.deinit;

    pub fn create() BackendError!ScrollView {
        const NSScrollView = objc.getClass("NSScrollView").?;
        const scroll_view = NSScrollView.msgSend(objc.Object, "alloc", .{})
            .msgSend(objc.Object, "initWithFrame:", .{AppKit.NSRect.make(0, 0, 1, 1)});
        scroll_view.setProperty("hasVerticalScroller", @as(u8, @intFromBool(true)));
        scroll_view.setProperty("hasHorizontalScroller", @as(u8, @intFromBool(true)));
        scroll_view.setProperty("autohidesScrollers", @as(u8, @intFromBool(true)));

        const data = try lib.internal.allocator.create(EventUserData);
        data.* = EventUserData{ .peer = scroll_view };
        return ScrollView{ .peer = GuiWidget{
            .object = scroll_view,
            .data = data,
        } };
    }

    pub fn setChild(self: *ScrollView, child_peer: GuiWidget, child_widget: anytype) void {
        _ = child_widget;
        self.peer.object.msgSend(void, "setDocumentView:", .{child_peer.object});
    }
};

// ---------------------------------------------------------------------------
// TextField
// ---------------------------------------------------------------------------

pub const TextField = struct {
    peer: GuiWidget,
    delegate: ?objc.Object = null,

    const _events = Events(@This());
    pub const setupEvents = _events.setupEvents;
    pub const setUserData = _events.setUserData;
    pub const setCallback = _events.setCallback;
    pub const setOpacity = _events.setOpacity;
    pub const getX = _events.getX;
    pub const getY = _events.getY;
    pub const getWidth = _events.getWidth;
    pub const getHeight = _events.getHeight;
    pub const getPreferredSize = _events.getPreferredSize;
    pub const requestDraw = _events.requestDraw;

    pub fn create() BackendError!TextField {
        const NSTextField = objc.getClass("NSTextField").?;
        const field = NSTextField.msgSend(objc.Object, "alloc", .{})
            .msgSend(objc.Object, "initWithFrame:", .{AppKit.NSRect.make(0, 0, 100, 22)});
        field.setProperty("editable", @as(u8, @intFromBool(true)));
        field.setProperty("bezeled", @as(u8, @intFromBool(true)));
        field.setProperty("drawsBackground", @as(u8, @intFromBool(true)));
        field.setProperty("selectable", @as(u8, @intFromBool(true)));

        const data = try lib.internal.allocator.create(EventUserData);
        data.* = EventUserData{ .peer = field };

        // Create delegate for text change notifications
        const delegate_cls = try getCapyTextFieldDelegateClass();
        const delegate = delegate_cls.msgSend(objc.Object, "alloc", .{})
            .msgSend(objc.Object, "init", .{});
        setEventDataIvar(delegate, data);
        field.setProperty("delegate", delegate);

        return TextField{
            .peer = GuiWidget{
                .object = field,
                .data = data,
            },
            .delegate = delegate,
        };
    }

    pub fn setText(self: *TextField, text_arg: []const u8) void {
        const nullTerminatedText = lib.internal.allocator.dupeZ(u8, text_arg) catch return;
        defer lib.internal.allocator.free(nullTerminatedText);
        self.peer.object.msgSend(void, "setStringValue:", .{AppKit.nsString(nullTerminatedText)});
    }

    pub fn getText(self: *TextField) []const u8 {
        const nsstr = self.peer.object.getProperty(objc.Object, "stringValue");
        if (nsstr.value == null) return "";
        const utf8 = nsstr.msgSend([*:0]const u8, "UTF8String", .{});
        return std.mem.sliceTo(utf8, 0);
    }

    pub fn setReadOnly(self: *TextField, read_only: bool) void {
        self.peer.object.setProperty("editable", @as(u8, @intFromBool(!read_only)));
    }

    pub fn deinit(self: *const TextField) void {
        _events.deinit(self);
    }
};

// ---------------------------------------------------------------------------
// TextArea
// ---------------------------------------------------------------------------

pub const TextArea = struct {
    peer: GuiWidget,
    text_view: objc.Object,

    const _events = Events(@This());
    pub const setupEvents = _events.setupEvents;
    pub const setUserData = _events.setUserData;
    pub const setCallback = _events.setCallback;
    pub const setOpacity = _events.setOpacity;
    pub const getX = _events.getX;
    pub const getY = _events.getY;
    pub const getWidth = _events.getWidth;
    pub const getHeight = _events.getHeight;
    pub const getPreferredSize = _events.getPreferredSize;
    pub const requestDraw = _events.requestDraw;
    pub const deinit = _events.deinit;

    pub fn create() BackendError!TextArea {
        const NSScrollView = objc.getClass("NSScrollView").?;
        const scroll_view = NSScrollView.msgSend(objc.Object, "alloc", .{})
            .msgSend(objc.Object, "initWithFrame:", .{AppKit.NSRect.make(0, 0, 200, 100)});
        scroll_view.setProperty("hasVerticalScroller", @as(u8, @intFromBool(true)));
        scroll_view.setProperty("hasHorizontalScroller", @as(u8, @intFromBool(false)));
        scroll_view.setProperty("autohidesScrollers", @as(u8, @intFromBool(true)));

        const NSTextView = objc.getClass("NSTextView").?;
        const text_view = NSTextView.msgSend(objc.Object, "alloc", .{})
            .msgSend(objc.Object, "initWithFrame:", .{AppKit.NSRect.make(0, 0, 200, 100)});
        text_view.setProperty("autoresizingMask", @as(AppKit.NSUInteger, 2)); // NSViewWidthSizable
        text_view.msgSend(void, "setRichText:", .{@as(u8, @intFromBool(false))});

        scroll_view.msgSend(void, "setDocumentView:", .{text_view});

        const data = try lib.internal.allocator.create(EventUserData);
        data.* = EventUserData{ .peer = scroll_view };
        return TextArea{
            .peer = GuiWidget{
                .object = scroll_view,
                .data = data,
            },
            .text_view = text_view,
        };
    }

    pub fn setText(self: *TextArea, text_arg: []const u8) void {
        const nullTerminatedText = lib.internal.allocator.dupeZ(u8, text_arg) catch return;
        defer lib.internal.allocator.free(nullTerminatedText);
        self.text_view.msgSend(void, "setString:", .{AppKit.nsString(nullTerminatedText)});
    }

    pub fn getText(self: *TextArea) []const u8 {
        const nsstr = self.text_view.getProperty(objc.Object, "string");
        if (nsstr.value == null) return "";
        const utf8 = nsstr.msgSend([*:0]const u8, "UTF8String", .{});
        return std.mem.sliceTo(utf8, 0);
    }

    pub fn setMonospaced(self: *TextArea, monospaced: bool) void {
        const NSFont = objc.getClass("NSFont") orelse return;
        const font = if (monospaced)
            NSFont.msgSend(objc.Object, "monospacedSystemFontOfSize:weight:", .{
                @as(AppKit.CGFloat, 13.0),
                @as(AppKit.CGFloat, 0.0),
            })
        else
            NSFont.msgSend(objc.Object, "systemFontOfSize:", .{
                @as(AppKit.CGFloat, 13.0),
            });
        if (font.value != null) {
            self.text_view.msgSend(void, "setFont:", .{font});
        }
    }
};

// ---------------------------------------------------------------------------
// CheckBox
// ---------------------------------------------------------------------------

pub const CheckBox = struct {
    peer: GuiWidget,
    action_target: ?objc.Object = null,

    const _events = Events(@This());
    pub const setupEvents = _events.setupEvents;
    pub const setUserData = _events.setUserData;
    pub const setCallback = _events.setCallback;
    pub const setOpacity = _events.setOpacity;
    pub const getX = _events.getX;
    pub const getY = _events.getY;
    pub const getWidth = _events.getWidth;
    pub const getHeight = _events.getHeight;
    pub const getPreferredSize = _events.getPreferredSize;
    pub const requestDraw = _events.requestDraw;
    pub const deinit = _events.deinit;

    pub fn create() BackendError!CheckBox {
        const NSButton = objc.getClass("NSButton").?;
        const button = NSButton.msgSend(objc.Object, "alloc", .{})
            .msgSend(objc.Object, "initWithFrame:", .{AppKit.NSRect.make(0, 0, 100, 22)});
        button.msgSend(void, "setButtonType:", .{@as(AppKit.NSUInteger, AppKit.NSButtonType.Switch)});
        button.setProperty("title", AppKit.nsString(""));
        // Accept keyboard focus so Space activates the control
        button.msgSend(void, "setRefusesFirstResponder:", .{@as(u8, @intFromBool(false))});

        const data = try lib.internal.allocator.create(EventUserData);
        data.* = EventUserData{ .peer = button };

        const target = try createActionTarget(data);
        button.setProperty("target", target);
        button.setProperty("action", objc.sel("action:"));

        return CheckBox{
            .peer = GuiWidget{
                .object = button,
                .data = data,
            },
            .action_target = target,
        };
    }

    pub fn setChecked(self: *CheckBox, checked: bool) void {
        self.peer.object.setProperty("state", @as(i64, if (checked) AppKit.NSControlStateValue.On else AppKit.NSControlStateValue.Off));
    }

    pub fn isChecked(self: *CheckBox) bool {
        const state: i64 = self.peer.object.getProperty(i64, "state");
        return state == AppKit.NSControlStateValue.On;
    }

    pub fn setEnabled(self: *CheckBox, enabled: bool) void {
        self.peer.object.setProperty("enabled", @as(u8, @intFromBool(enabled)));
    }

    pub fn setLabel(self: *CheckBox, label_text: [:0]const u8) void {
        self.peer.object.setProperty("title", AppKit.nsString(label_text.ptr));
    }

    pub fn getLabel(self: *CheckBox) [:0]const u8 {
        const title = self.peer.object.getProperty(objc.Object, "title");
        if (title.value == null) return "";
        const label = title.msgSend([*:0]const u8, "UTF8String", .{});
        return std.mem.sliceTo(label, 0);
    }
};

// ---------------------------------------------------------------------------
// RadioButton
// ---------------------------------------------------------------------------

pub const RadioButton = struct {
    peer: GuiWidget,
    action_target: ?objc.Object = null,

    const _events = Events(@This());
    pub const setupEvents = _events.setupEvents;
    pub const setUserData = _events.setUserData;
    pub const setCallback = _events.setCallback;
    pub const setOpacity = _events.setOpacity;
    pub const getX = _events.getX;
    pub const getY = _events.getY;
    pub const getWidth = _events.getWidth;
    pub const getHeight = _events.getHeight;
    pub const getPreferredSize = _events.getPreferredSize;
    pub const requestDraw = _events.requestDraw;
    pub const deinit = _events.deinit;

    pub fn create() BackendError!RadioButton {
        const NSButton = objc.getClass("NSButton").?;
        const button = NSButton.msgSend(objc.Object, "alloc", .{})
            .msgSend(objc.Object, "initWithFrame:", .{AppKit.NSRect.make(0, 0, 100, 22)});
        button.msgSend(void, "setButtonType:", .{@as(AppKit.NSUInteger, AppKit.NSButtonType.Radio)});
        button.setProperty("title", AppKit.nsString(""));
        button.msgSend(void, "setRefusesFirstResponder:", .{@as(u8, @intFromBool(false))});

        const data = try lib.internal.allocator.create(EventUserData);
        data.* = EventUserData{ .peer = button };

        const target = try createActionTarget(data);
        button.setProperty("target", target);
        button.setProperty("action", objc.sel("action:"));

        return RadioButton{
            .peer = GuiWidget{
                .object = button,
                .data = data,
            },
            .action_target = target,
        };
    }

    pub fn setChecked(self: *RadioButton, checked: bool) void {
        self.peer.object.setProperty("state", @as(i64, if (checked) AppKit.NSControlStateValue.On else AppKit.NSControlStateValue.Off));
    }

    pub fn isChecked(self: *RadioButton) bool {
        const state: i64 = self.peer.object.getProperty(i64, "state");
        return state == AppKit.NSControlStateValue.On;
    }

    pub fn setEnabled(self: *RadioButton, enabled: bool) void {
        self.peer.object.setProperty("enabled", @as(u8, @intFromBool(enabled)));
    }

    pub fn setLabel(self: *RadioButton, label_text: [:0]const u8) void {
        self.peer.object.setProperty("title", AppKit.nsString(label_text.ptr));
    }

    pub fn getLabel(self: *RadioButton) [:0]const u8 {
        const title = self.peer.object.getProperty(objc.Object, "title");
        if (title.value == null) return "";
        const label = title.msgSend([*:0]const u8, "UTF8String", .{});
        return std.mem.sliceTo(label, 0);
    }

    pub fn setGroup(self: *RadioButton, group_leader: *const RadioButton) void {
        // macOS doesn't have native radio button grouping.
        // Mutual exclusivity is managed at the component level.
        _ = self;
        _ = group_leader;
    }
};

// ---------------------------------------------------------------------------
// ProgressBar
// ---------------------------------------------------------------------------

pub const ProgressBar = struct {
    peer: GuiWidget,

    const _events = Events(@This());
    pub const setupEvents = _events.setupEvents;
    pub const setUserData = _events.setUserData;
    pub const setCallback = _events.setCallback;
    pub const setOpacity = _events.setOpacity;
    pub const getX = _events.getX;
    pub const getY = _events.getY;
    pub const getWidth = _events.getWidth;
    pub const getHeight = _events.getHeight;
    pub const getPreferredSize = _events.getPreferredSize;
    pub const requestDraw = _events.requestDraw;
    pub const deinit = _events.deinit;

    pub fn create() BackendError!ProgressBar {
        const NSProgressIndicator = objc.getClass("NSProgressIndicator").?;
        const indicator = NSProgressIndicator.msgSend(objc.Object, "alloc", .{})
            .msgSend(objc.Object, "initWithFrame:", .{AppKit.NSRect.make(0, 0, 200, 20)});
        // Determinate bar style
        indicator.msgSend(void, "setStyle:", .{@as(c_long, 0)}); // NSProgressIndicatorStyleBar
        indicator.setProperty("indeterminate", @as(u8, @intFromBool(false)));
        indicator.setProperty("minValue", @as(AppKit.CGFloat, 0.0));
        indicator.setProperty("maxValue", @as(AppKit.CGFloat, 1.0));
        indicator.setProperty("doubleValue", @as(AppKit.CGFloat, 0.0));

        const data = try lib.internal.allocator.create(EventUserData);
        data.* = EventUserData{ .peer = indicator };

        return ProgressBar{
            .peer = GuiWidget{
                .object = indicator,
                .data = data,
            },
        };
    }

    pub fn setValue(self: *ProgressBar, value: f32) void {
        self.peer.object.setProperty("doubleValue", @as(AppKit.CGFloat, @floatCast(value)));
    }
};

// ---------------------------------------------------------------------------
// Slider
// ---------------------------------------------------------------------------

pub const Slider = struct {
    peer: GuiWidget,
    action_target: ?objc.Object = null,

    const _events = Events(@This());
    pub const setupEvents = _events.setupEvents;
    pub const setUserData = _events.setUserData;
    pub const setCallback = _events.setCallback;
    pub const setOpacity = _events.setOpacity;
    pub const getX = _events.getX;
    pub const getY = _events.getY;
    pub const getWidth = _events.getWidth;
    pub const getHeight = _events.getHeight;
    pub const getPreferredSize = _events.getPreferredSize;
    pub const requestDraw = _events.requestDraw;
    pub const deinit = _events.deinit;

    pub fn create() BackendError!Slider {
        const NSSlider = objc.getClass("NSSlider").?;
        const slider = NSSlider.msgSend(objc.Object, "alloc", .{})
            .msgSend(objc.Object, "initWithFrame:", .{AppKit.NSRect.make(0, 0, 100, 22)});
        slider.setProperty("minValue", @as(AppKit.CGFloat, 0.0));
        slider.setProperty("maxValue", @as(AppKit.CGFloat, 1.0));
        slider.setProperty("continuous", @as(u8, @intFromBool(true)));
        slider.msgSend(void, "setRefusesFirstResponder:", .{@as(u8, @intFromBool(false))});

        const data = try lib.internal.allocator.create(EventUserData);
        data.* = EventUserData{ .peer = slider };

        const target_cls = try getCapySliderTargetClass();
        const target = target_cls.msgSend(objc.Object, "alloc", .{}).msgSend(objc.Object, "init", .{});
        setEventDataIvar(target, data);
        slider.setProperty("target", target);
        slider.setProperty("action", objc.sel("sliderAction:"));

        return Slider{
            .peer = GuiWidget{
                .object = slider,
                .data = data,
            },
            .action_target = target,
        };
    }

    pub fn getValue(self: *Slider) f32 {
        return @floatCast(self.peer.object.getProperty(AppKit.CGFloat, "doubleValue"));
    }

    pub fn setValue(self: *Slider, value: f32) void {
        self.peer.object.setProperty("doubleValue", @as(AppKit.CGFloat, @floatCast(value)));
    }

    pub fn setMinimum(self: *Slider, min: f32) void {
        self.peer.object.setProperty("minValue", @as(AppKit.CGFloat, @floatCast(min)));
    }

    pub fn setMaximum(self: *Slider, max: f32) void {
        self.peer.object.setProperty("maxValue", @as(AppKit.CGFloat, @floatCast(max)));
    }

    pub fn setStepSize(self: *Slider, step: f32) void {
        _ = self;
        _ = step;
    }

    pub fn setEnabled(self: *Slider, enabled: bool) void {
        self.peer.object.setProperty("enabled", @as(u8, @intFromBool(enabled)));
    }

    pub fn setOrientation(self: *Slider, orientation: anytype) void {
        _ = orientation;
        self.peer.object.setProperty("vertical", @as(u8, @intFromBool(false)));
    }

    pub fn setTickCount(self: *Slider, count: u32) void {
        self.peer.object.setProperty("numberOfTickMarks", @as(c_long, @intCast(count)));
    }

    pub fn setSnapToTicks(self: *Slider, snap: bool) void {
        self.peer.object.setProperty("allowsTickMarkValuesOnly", @as(u8, @intFromBool(snap)));
    }
};

// ---------------------------------------------------------------------------
// Dropdown
// ---------------------------------------------------------------------------

pub const Dropdown = struct {
    peer: GuiWidget,
    action_target: ?objc.Object = null,

    const _events = Events(@This());
    pub const setupEvents = _events.setupEvents;
    pub const setUserData = _events.setUserData;
    pub const setCallback = _events.setCallback;
    pub const setOpacity = _events.setOpacity;
    pub const getX = _events.getX;
    pub const getY = _events.getY;
    pub const getWidth = _events.getWidth;
    pub const getHeight = _events.getHeight;
    pub const getPreferredSize = _events.getPreferredSize;
    pub const requestDraw = _events.requestDraw;
    pub const deinit = _events.deinit;

    pub fn create() BackendError!Dropdown {
        const NSPopUpButton = objc.getClass("NSPopUpButton").?;
        const popup = NSPopUpButton.msgSend(objc.Object, "alloc", .{})
            .msgSend(objc.Object, "initWithFrame:pullsDown:", .{ AppKit.NSRect.make(0, 0, 100, 22), @as(u8, @intFromBool(false)) });
        popup.msgSend(void, "setRefusesFirstResponder:", .{@as(u8, @intFromBool(false))});

        const data = try lib.internal.allocator.create(EventUserData);
        data.* = EventUserData{ .peer = popup };

        const target_cls = try getCapyDropdownTargetClass();
        const target = target_cls.msgSend(objc.Object, "alloc", .{}).msgSend(objc.Object, "init", .{});
        setEventDataIvar(target, data);
        popup.setProperty("target", target);
        popup.setProperty("action", objc.sel("dropdownAction:"));

        return Dropdown{
            .peer = GuiWidget{
                .object = popup,
                .data = data,
            },
            .action_target = target,
        };
    }

    pub fn getSelectedIndex(self: *Dropdown) ?usize {
        const index: i64 = self.peer.object.getProperty(i64, "indexOfSelectedItem");
        if (index < 0) return null;
        return @intCast(index);
    }

    pub fn setSelectedIndex(self: *Dropdown, index: ?usize) void {
        if (index) |i| {
            self.peer.object.msgSend(void, "selectItemAtIndex:", .{@as(i64, @intCast(i))});
        }
    }

    pub fn setValues(self: *Dropdown, values: anytype) void {
        self.peer.object.msgSend(void, "removeAllItems", .{});
        for (values) |value| {
            const str = lib.internal.allocator.dupeZ(u8, value) catch continue;
            defer lib.internal.allocator.free(str);
            self.peer.object.msgSend(void, "addItemWithTitle:", .{AppKit.nsString(str)});
        }
    }

    pub fn setEnabled(self: *Dropdown, enabled: bool) void {
        self.peer.object.setProperty("enabled", @as(u8, @intFromBool(enabled)));
    }
};

// ---------------------------------------------------------------------------
// Table (Native NSTableView)
// ---------------------------------------------------------------------------

/// Shared state between the Zig Table backend and ObjC data source/delegate.
/// Heap-allocated so its address is stable for the ObjC ivar.
const TableState = struct {
    cell_provider: ?*const fn (row: usize, col: usize, buf: []u8) []const u8 = null,
    row_count: usize = 0,
    column_count: usize = 0,
    event_data: ?*EventUserData = null,
};

var cachedCapyTableDelegate: ?objc.Class = null;

fn getCapyTableDelegateClass() !objc.Class {
    if (cachedCapyTableDelegate) |cls| return cls;

    const NSObjectClass = objc.getClass("NSObject").?;
    const cls = objc.allocateClassPair(NSObjectClass, "CapyTableDelegate") orelse return error.InitializationError;
    if (!cls.addIvar("capy_event_data")) return error.InitializationError;
    if (!cls.addIvar("capy_table_state")) return error.InitializationError;

    // NSTableViewDataSource: numberOfRowsInTableView:
    _ = cls.addMethod("numberOfRowsInTableView:", struct {
        fn imp(self_id: objc.c.id, _: objc.c.SEL, _: objc.c.id) callconv(.c) i64 {
            const self_obj = objc.Object{ .value = self_id };
            const state = getTableStateFromIvar(self_obj) orelse return 0;
            return @intCast(state.row_count);
        }
    }.imp);

    // NSTableViewDataSource: tableView:objectValueForTableColumn:row:
    _ = cls.addMethod("tableView:objectValueForTableColumn:row:", struct {
        fn imp(self_id: objc.c.id, _: objc.c.SEL, tv_id: objc.c.id, col_id: objc.c.id, row: i64) callconv(.c) objc.c.id {
            const self_obj = objc.Object{ .value = self_id };
            const state = getTableStateFromIvar(self_obj) orelse return AppKit.nsString("").value;
            const provider = state.cell_provider orelse return AppKit.nsString("").value;

            // Find column index by iterating tableColumns array
            const tv = objc.Object{ .value = tv_id };
            const columns = tv.msgSend(objc.Object, "tableColumns", .{});
            const num_cols: usize = @intCast(columns.msgSend(c_ulong, "count", .{}));
            var col_idx: usize = 0;
            for (0..num_cols) |i| {
                const c_obj = columns.msgSend(objc.Object, "objectAtIndex:", .{@as(c_ulong, i)});
                if (c_obj.value == col_id) {
                    col_idx = i;
                    break;
                }
            }

            var buf: [256]u8 = undefined;
            const text = provider(@intCast(row), col_idx, &buf);
            // Copy to null-terminated buffer for NSString
            var ns_buf: [257]u8 = undefined;
            const len = @min(text.len, 256);
            @memcpy(ns_buf[0..len], text[0..len]);
            ns_buf[len] = 0;
            return AppKit.nsString(@ptrCast(ns_buf[0..len :0])).value;
        }
    }.imp);

    // NSTableViewDelegate: tableViewSelectionDidChange:
    _ = cls.addMethod("tableViewSelectionDidChange:", struct {
        fn imp(self_id: objc.c.id, _: objc.c.SEL, notification_id: objc.c.id) callconv(.c) void {
            const self_obj = objc.Object{ .value = self_id };
            const data = getEventDataFromIvar(self_obj) orelse return;
            const notification = objc.Object{ .value = notification_id };
            const tv = notification.msgSend(objc.Object, "object", .{});
            const selected_row: i64 = tv.getProperty(i64, "selectedRow");

            // Fire property change with selected row index
            if (selected_row >= 0) {
                const idx: usize = @intCast(selected_row);
                if (data.class.propertyChangeHandler) |handler|
                    handler("selected", @ptrCast(&idx), @intFromPtr(data));
                if (data.user.propertyChangeHandler) |handler|
                    handler("selected", @ptrCast(&idx), data.userdata);
            } else {
                // No selection
                const null_val: ?usize = null;
                if (data.class.propertyChangeHandler) |handler|
                    handler("selected", @ptrCast(&null_val), @intFromPtr(data));
                if (data.user.propertyChangeHandler) |handler|
                    handler("selected", @ptrCast(&null_val), data.userdata);
            }
        }
    }.imp);

    // NSTableViewDelegate: tableView:didClickTableColumn:
    _ = cls.addMethod("tableView:didClickTableColumn:", struct {
        fn imp(self_id: objc.c.id, _: objc.c.SEL, tv_id: objc.c.id, col_id: objc.c.id) callconv(.c) void {
            const self_obj = objc.Object{ .value = self_id };
            const data = getEventDataFromIvar(self_obj) orelse return;

            // Find column index
            const tv = objc.Object{ .value = tv_id };
            const columns = tv.msgSend(objc.Object, "tableColumns", .{});
            const num_cols: usize = @intCast(columns.msgSend(c_ulong, "count", .{}));
            var col_idx: usize = 0;
            for (0..num_cols) |i| {
                const c_obj = columns.msgSend(objc.Object, "objectAtIndex:", .{@as(c_ulong, i)});
                if (c_obj.value == col_id) {
                    col_idx = i;
                    break;
                }
            }

            if (data.class.propertyChangeHandler) |handler|
                handler("sort", @ptrCast(&col_idx), @intFromPtr(data));
            if (data.user.propertyChangeHandler) |handler|
                handler("sort", @ptrCast(&col_idx), data.userdata);
        }
    }.imp);

    objc.registerClassPair(cls);
    cachedCapyTableDelegate = cls;
    return cls;
}

fn getTableStateFromIvar(obj: objc.Object) ?*TableState {
    const state_obj = obj.getInstanceVariable("capy_table_state");
    if (@intFromPtr(state_obj.value) == 0) return null;
    return @as(*TableState, @ptrFromInt(@intFromPtr(state_obj.value)));
}

fn setTableStateIvar(obj: objc.Object, state: *TableState) void {
    obj.setInstanceVariable("capy_table_state", objc.Object{ .value = @ptrFromInt(@intFromPtr(state)) });
}

pub const Table = struct {
    peer: GuiWidget,
    table_view: objc.Object,
    delegate_obj: objc.Object,
    state: *TableState,

    const _events = Events(@This());
    pub const setupEvents = _events.setupEvents;
    pub const setUserData = _events.setUserData;
    pub const setCallback = _events.setCallback;
    pub const setOpacity = _events.setOpacity;
    pub const getX = _events.getX;
    pub const getY = _events.getY;
    pub const getWidth = _events.getWidth;
    pub const getHeight = _events.getHeight;
    pub const getPreferredSize = _events.getPreferredSize;
    pub const requestDraw = _events.requestDraw;

    pub fn create() BackendError!Table {
        const pool = objc.AutoreleasePool.init();
        defer pool.deinit();

        const NSTableView = objc.getClass("NSTableView").?;
        const NSScrollView = objc.getClass("NSScrollView").?;

        // Create table view
        const table_view = NSTableView.msgSend(objc.Object, "alloc", .{})
            .msgSend(objc.Object, "initWithFrame:", .{AppKit.NSRect.make(0, 0, 400, 300)});
        table_view.msgSend(void, "setUsesAlternatingRowBackgroundColors:", .{@as(u8, 1)});
        table_view.msgSend(void, "setGridStyleMask:", .{@as(c_ulong, 0)}); // no grid lines (clean look)
        table_view.msgSend(void, "setAllowsColumnReordering:", .{@as(u8, 1)});
        table_view.msgSend(void, "setAllowsColumnResizing:", .{@as(u8, 1)});
        table_view.msgSend(void, "setColumnAutoresizingStyle:", .{@as(c_ulong, 1)}); // uniform column autoresizing

        // Create scroll view wrapper
        const scroll_view = NSScrollView.msgSend(objc.Object, "alloc", .{})
            .msgSend(objc.Object, "initWithFrame:", .{AppKit.NSRect.make(0, 0, 400, 300)});
        scroll_view.msgSend(void, "setDocumentView:", .{table_view.value});
        scroll_view.msgSend(void, "setHasVerticalScroller:", .{@as(u8, 1)});
        scroll_view.msgSend(void, "setHasHorizontalScroller:", .{@as(u8, 0)});
        scroll_view.msgSend(void, "setAutohidesScrollers:", .{@as(u8, 1)});
        scroll_view.msgSend(void, "setBorderType:", .{@as(c_ulong, 3)}); // NSBezelBorder

        // Create event data
        const data = try lib.internal.allocator.create(EventUserData);
        data.* = EventUserData{ .peer = scroll_view };

        // Create shared state
        const state = try lib.internal.allocator.create(TableState);
        state.* = TableState{ .event_data = data };

        // Create and configure data source/delegate
        const ds_cls = try getCapyTableDelegateClass();
        const ds = ds_cls.msgSend(objc.Object, "alloc", .{}).msgSend(objc.Object, "init", .{});
        setEventDataIvar(ds, data);
        setTableStateIvar(ds, state);

        table_view.msgSend(void, "setDataSource:", .{ds.value});
        table_view.msgSend(void, "setDelegate:", .{ds.value});

        return Table{
            .peer = GuiWidget{
                .object = scroll_view,
                .data = data,
            },
            .table_view = table_view,
            .delegate_obj = ds,
            .state = state,
        };
    }

    pub fn setColumns(self: *Table, columns: []const @import("../../components/Table.zig").ColumnDef) void {
        const pool = objc.AutoreleasePool.init();
        defer pool.deinit();

        // Remove existing columns
        const existing = self.table_view.msgSend(objc.Object, "tableColumns", .{});
        const existing_count: usize = @intCast(existing.msgSend(c_ulong, "count", .{}));
        // Remove in reverse order to avoid index shifting
        var i = existing_count;
        while (i > 0) {
            i -= 1;
            const col = existing.msgSend(objc.Object, "objectAtIndex:", .{@as(c_ulong, i)});
            self.table_view.msgSend(void, "removeTableColumn:", .{col.value});
        }

        // Add new columns
        const NSTableColumn = objc.getClass("NSTableColumn").?;
        for (columns) |col_def| {
            const str = lib.internal.allocator.dupeZ(u8, col_def.header) catch continue;
            defer lib.internal.allocator.free(str);
            const identifier = AppKit.nsString(str);

            const tc = NSTableColumn.msgSend(objc.Object, "alloc", .{})
                .msgSend(objc.Object, "initWithIdentifier:", .{identifier.value});

            // Set header title
            const header_cell = tc.getProperty(objc.Object, "headerCell");
            header_cell.msgSend(void, "setStringValue:", .{identifier.value});

            // Set widths
            tc.msgSend(void, "setWidth:", .{@as(AppKit.CGFloat, @floatCast(col_def.width))});
            tc.msgSend(void, "setMinWidth:", .{@as(AppKit.CGFloat, @floatCast(col_def.min_width))});

            self.table_view.msgSend(void, "addTableColumn:", .{tc.value});
        }

        self.state.column_count = columns.len;
    }

    pub fn setCellProvider(self: *Table, provider: *const fn (row: usize, col: usize, buf: []u8) []const u8) void {
        self.state.cell_provider = provider;
    }

    pub fn setRowCount(self: *Table, count: usize) void {
        self.state.row_count = count;
        self.table_view.msgSend(void, "reloadData", .{});
    }

    pub fn setSelectedRow(self: *Table, row: ?usize) void {
        const pool = objc.AutoreleasePool.init();
        defer pool.deinit();

        if (row) |r| {
            const NSIndexSet = objc.getClass("NSIndexSet").?;
            const index_set = NSIndexSet.msgSend(objc.Object, "indexSetWithIndex:", .{@as(c_ulong, r)});
            self.table_view.msgSend(void, "selectRowIndexes:byExtendingSelection:", .{ index_set.value, @as(u8, 0) });
        } else {
            self.table_view.msgSend(void, "deselectAll:", .{@as(?objc.c.id, null)});
        }
    }

    pub fn getSelectedRow(self: *Table) ?usize {
        const row: i64 = self.table_view.getProperty(i64, "selectedRow");
        if (row < 0) return null;
        return @intCast(row);
    }

    pub fn reloadData(self: *Table) void {
        self.table_view.msgSend(void, "reloadData", .{});
    }

    pub fn deinit(self: *const Table) void {
        lib.internal.allocator.destroy(self.state);
        _events.deinit(self);
    }
};

// ---------------------------------------------------------------------------
// TabContainer
// ---------------------------------------------------------------------------

pub const TabContainer = struct {
    peer: GuiWidget,

    const _events = Events(@This());
    pub const setupEvents = _events.setupEvents;
    pub const setUserData = _events.setUserData;
    pub const setCallback = _events.setCallback;
    pub const setOpacity = _events.setOpacity;
    pub const getX = _events.getX;
    pub const getY = _events.getY;
    pub const getWidth = _events.getWidth;
    pub const getHeight = _events.getHeight;
    pub const getPreferredSize = _events.getPreferredSize;
    pub const requestDraw = _events.requestDraw;
    pub const deinit = _events.deinit;

    pub fn create() BackendError!TabContainer {
        const NSTabView = objc.getClass("NSTabView").?;
        const tab_view = NSTabView.msgSend(objc.Object, "alloc", .{})
            .msgSend(objc.Object, "initWithFrame:", .{AppKit.NSRect.make(0, 0, 200, 200)});

        const data = try lib.internal.allocator.create(EventUserData);
        data.* = EventUserData{ .peer = tab_view };
        return TabContainer{
            .peer = GuiWidget{
                .object = tab_view,
                .data = data,
            },
        };
    }

    pub fn insert(self: *TabContainer, position: usize, child_peer: GuiWidget) usize {
        const NSTabViewItem = objc.getClass("NSTabViewItem").?;
        const item = NSTabViewItem.msgSend(objc.Object, "alloc", .{})
            .msgSend(objc.Object, "initWithIdentifier:", .{@as(objc.c.id, null)});
        item.setProperty("view", child_peer.object);
        self.peer.object.msgSend(void, "insertTabViewItem:atIndex:", .{ item, @as(i64, @intCast(position)) });
        return position;
    }

    pub fn setLabel(self: *TabContainer, position: usize, label_text: [:0]const u8) void {
        const item = self.peer.object.msgSend(objc.Object, "tabViewItemAtIndex:", .{@as(i64, @intCast(position))});
        if (item.value != null) {
            item.setProperty("label", AppKit.nsString(label_text.ptr));
        }
    }

    pub fn getTabsNumber(self: *TabContainer) usize {
        const count: i64 = self.peer.object.getProperty(i64, "numberOfTabViewItems");
        if (count < 0) return 0;
        return @intCast(count);
    }
};

// ---------------------------------------------------------------------------
// NavigationSidebar
// ---------------------------------------------------------------------------

pub const NavigationSidebar = struct {
    peer: GuiWidget,

    const _events = Events(@This());
    pub const setupEvents = _events.setupEvents;
    pub const setUserData = _events.setUserData;
    pub const setCallback = _events.setCallback;
    pub const setOpacity = _events.setOpacity;
    pub const getX = _events.getX;
    pub const getY = _events.getY;
    pub const getWidth = _events.getWidth;
    pub const getHeight = _events.getHeight;
    pub const getPreferredSize = _events.getPreferredSize;
    pub const requestDraw = _events.requestDraw;
    pub const deinit = _events.deinit;

    pub fn create() BackendError!NavigationSidebar {
        const NSScrollView = objc.getClass("NSScrollView").?;
        const scroll_view = NSScrollView.msgSend(objc.Object, "alloc", .{})
            .msgSend(objc.Object, "initWithFrame:", .{AppKit.NSRect.make(0, 0, 200, 400)});
        scroll_view.setProperty("hasVerticalScroller", @as(u8, @intFromBool(true)));

        const data = try lib.internal.allocator.create(EventUserData);
        data.* = EventUserData{ .peer = scroll_view };
        return NavigationSidebar{
            .peer = GuiWidget{
                .object = scroll_view,
                .data = data,
            },
        };
    }

    pub fn append(self: *NavigationSidebar, item: anytype) void {
        _ = self;
        _ = item;
    }
};

// ---------------------------------------------------------------------------
// ImageData
// ---------------------------------------------------------------------------

pub const ImageData = struct {
    cg_image: AppKit.CGImageRef = null,
    width: usize = 0,
    height: usize = 0,

    pub fn from(width: usize, height: usize, stride: usize, cs: lib.Colorspace, bytes: []const u8) !ImageData {
        const color_space = AppKit.CGColorSpaceCreateDeviceRGB();
        defer AppKit.CGColorSpaceRelease(color_space);

        const bits_per_component: usize = 8;
        const bitmap_info: u32 = switch (cs) {
            .RGBA => AppKit.CGBitmapInfo.PremultipliedLast,
            .RGB => AppKit.CGBitmapInfo.NoneSkipLast,
        };

        const ctx = AppKit.CGBitmapContextCreate(
            @constCast(@ptrCast(bytes.ptr)),
            width,
            height,
            bits_per_component,
            stride,
            color_space,
            bitmap_info,
        );
        if (ctx == null) return error.UnknownError;
        defer AppKit.CGContextRelease(ctx);

        const cg_image = AppKit.CGBitmapContextCreateImage(ctx);
        return ImageData{
            .cg_image = cg_image,
            .width = width,
            .height = height,
        };
    }

    pub fn draw(self: *ImageData) DrawLock {
        _ = self;
        return DrawLock{};
    }

    pub fn deinit(self: *ImageData) void {
        if (self.cg_image != null) {
            AppKit.CGImageRelease(self.cg_image);
            self.cg_image = null;
        }
    }

    pub const DrawLock = struct {
        pub fn end(self: *DrawLock) void {
            _ = self;
        }
    };
};

// ---------------------------------------------------------------------------
// AudioGenerator (stub - GTK also stubs this)
// ---------------------------------------------------------------------------

pub const AudioGenerator = struct {
    pub fn create(sample_rate: f32) !AudioGenerator {
        _ = sample_rate;
        return AudioGenerator{};
    }

    pub fn getBuffer(self: *const AudioGenerator, channel: u16) []f32 {
        _ = self;
        _ = channel;
        return &[_]f32{};
    }

    pub fn copyBuffer(self: *AudioGenerator, channel: u16) void {
        _ = self;
        _ = channel;
    }

    pub fn doneWrite(self: *AudioGenerator) void {
        _ = self;
    }

    pub fn deinit(self: *AudioGenerator) void {
        _ = self;
    }
};
