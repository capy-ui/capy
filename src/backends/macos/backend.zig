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

// pub const PeerType = *opaque {};
pub const PeerType = objc.Object;

pub const Button = @import("components/Button.zig");

const atomicValue = if (@hasDecl(std.atomic, "Value")) std.atomic.Value else std.atomic.Atomic; // support zig 0.11 as well as current master
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
    }
}

pub fn showNativeMessageDialog(msgType: shared.MessageType, comptime fmt: []const u8, args: anytype) void {
    const msg = std.fmt.allocPrintZ(lib.internal.scratch_allocator, fmt, args) catch {
        std.log.err("Could not launch message dialog, original text: " ++ fmt, args);
        return;
    };
    defer lib.internal.scratch_allocator.free(msg);
    _ = msgType;
    @panic("TODO: message dialogs on macOS");
}

/// user data used for handling events
pub const EventUserData = struct {
    user: EventFunctions = .{},
    class: EventFunctions = .{},
    userdata: usize = 0,
    classUserdata: usize = 0,
    peer: PeerType,
    focusOnClick: bool = false,
};

var test_data = EventUserData{ .peer = undefined };
pub inline fn getEventUserData(peer: PeerType) *EventUserData {
    _ = peer;
    return &test_data;
    //return @ptrCast(*EventUserData, @alignCast(@alignOf(EventUserData), c.g_object_get_data(@ptrCast(*c.GObject, peer), "eventUserData").?));
}

pub fn Events(comptime T: type) type {
    return struct {
        const Self = @This();

        pub fn setupEvents(peer: objc.Object) BackendError!void {
            _ = peer;
            // TODO
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
                .PropertyChange => data.propertyChangeHandler = cb,
            }
        }

        pub fn setOpacity(self: *const T, opacity: f32) void {
            _ = opacity;
            _ = self;
        }

        pub fn getX(self: *const T) c_int {
            _ = self;
            return 0;
        }

        pub fn getY(self: *const T) c_int {
            _ = self;
            return 0;
        }

        pub fn getWidth(self: *const T) u32 {
            _ = self;
            return 100;
        }

        pub fn getHeight(self: *const T) u32 {
            _ = self;
            return 100;
        }

        pub fn getPreferredSize(self: *const T) lib.Size {
            if (@hasDecl(T, "getPreferredSize_impl")) {
                return self.getPreferredSize_impl();
            }
            return lib.Size.init(
                100,
                100,
            );
        }

        pub fn deinit(self: *const T) void {
            _ = self;
        }
    };
}

pub const Window = struct {
    source_dpi: u32 = 96,
    scale: f32 = 1.0,
    peer: objc.Object,

    pub usingnamespace Events(Window);
    pub fn registerTickCallback(self: *Window) void {
        _ = self;
        // TODO
    }
    pub fn create() BackendError!Window {
        const NSWindow = objc.getClass("NSWindow").?;
        const rect = AppKit.NSRect.make(0, 0, 800, 600);
        const style = AppKit.NSWindowStyleMask.Titled | AppKit.NSWindowStyleMask.Closable | AppKit.NSWindowStyleMask.Miniaturizable | AppKit.NSWindowStyleMask.Resizable;
        const flag: u8 = @intFromBool(false);

        const window = NSWindow.msgSend(objc.Object, "alloc", .{});
        _ = window.msgSend(
            objc.Object,
            "initWithContentRect:styleMask:backing:defer:",
            .{ rect, style, AppKit.NSBackingStore.Buffered, flag },
        );

        return Window{
            .peer = window,
        };
    }

    pub fn resize(self: *Window, width: c_int, height: c_int) void {
        var frame = self.peer.getProperty(AppKit.NSRect, "frame");
        frame.size.width = @floatFromInt(width);
        frame.size.height = @floatFromInt(height);
        self.peer.msgSend(void, "setFrame:display:", .{ frame, true });
    }

    pub fn setTitle(self: *Window, title: [*:0]const u8) void {
        const pool = objc.AutoreleasePool.init();
        defer pool.deinit();

        self.peer.setProperty("title", AppKit.nsString(title));
    }

    pub fn setChild(self: *Window, optional_peer: ?PeerType) void {
        if (optional_peer) |peer| {
            self.peer.setProperty("contentView", peer);
        } else {
            @panic("TODO: set null child");
        }
    }

    pub fn setSourceDpi(self: *Window, dpi: u32) void {
        self.source_dpi = 96;
        // TODO
        const resolution = @as(f32, 96.0);
        self.scale = resolution / @as(f32, @floatFromInt(dpi));
    }

    pub fn show(self: *Window) void {
        self.peer.msgSend(void, "makeKeyAndOrderFront:", .{self.peer.value});
        _ = activeWindows.fetchAdd(1, .release);
    }

    pub fn close(self: *Window) void {
        self.peer.msgSend(void, "close", .{});
        _ = activeWindows.fetchSub(1, .release);
    }
};

var cachedFlippedNSView: ?objc.Class = null;
fn getFlippedNSView() !objc.Class {
    if (cachedFlippedNSView) |notNull| {
        return notNull;
    }

    const FlippedNSView = objc.allocateClassPair(objc.getClass("NSView").?, "FlippedNSView").?;
    defer objc.registerClassPair(FlippedNSView);
    const success = try FlippedNSView.addMethod("isFlipped", struct {
        fn imp(target: objc.c.id, sel: objc.c.SEL) callconv(.C) u8 {
            _ = sel;
            _ = target;
            return @intFromBool(true);
        }
    }.imp);
    if (!success) {
        return error.InitializationError;
    }

    cachedFlippedNSView = FlippedNSView;

    return FlippedNSView;
}

pub const Container = struct {
    peer: objc.Object,

    pub usingnamespace Events(Container);

    pub fn create() BackendError!Container {
        const view = (try getFlippedNSView())
            .msgSend(objc.Object, "alloc", .{})
            .msgSend(objc.Object, "initWithFrame:", .{AppKit.NSRect.make(0, 0, 1, 1)});
        return Container{ .peer = view };
    }

    pub fn add(self: *const Container, peer: PeerType) void {
        self.peer.msgSend(void, "addSubview:", .{peer});
    }

    pub fn remove(self: *const Container, peer: PeerType) void {
        _ = self;
        peer.msgSend(void, "removeFromSuperview", .{});
    }

    pub fn move(self: *const Container, peer: PeerType, x: u32, y: u32) void {
        _ = self;

        const peerFrame = peer.getProperty(AppKit.NSRect, "frame");

        peer.setProperty("frame", AppKit.NSRect.make(
            @floatFromInt(x),
            @floatFromInt(y),
            peerFrame.size.width,
            peerFrame.size.height,
        ));
    }

    pub fn resize(self: *const Container, peer: PeerType, width: u32, height: u32) void {
        _ = self;

        const peerFrame = peer.getProperty(AppKit.NSRect, "frame");

        peer.setProperty("frame", AppKit.NSRect.make(
            peerFrame.origin.x,
            peerFrame.origin.y,
            @floatFromInt(width),
            @floatFromInt(height),
        ));
    }

    pub fn setTabOrder(self: *const Container, peers: []const PeerType) void {
        _ = peers;
        _ = self;
    }
};

pub const Canvas = struct {
    pub usingnamespace Events(Canvas);

    pub const DrawContextImpl = struct {};
};

pub fn postEmptyEvent() void {
    @panic("TODO: postEmptyEvent");
}

pub fn runStep(step: shared.EventLoopStep) bool {
    const NSApplication = objc.getClass("NSApplication").?;
    const app = NSApplication.msgSend(objc.Object, "sharedApplication", .{});
    if (!finishedLaunching) {
        finishedLaunching = true;
        if (step == .Blocking) {
            // Run the NSApplication and stop it immediately using the delegate.
            // This is a similar technique to what GLFW does (see cocoa_window.m in GLFW's source code)
            app.msgSend(void, "run", .{});
        }
    }

    // Implement the event loop manually
    // Passing distantFuture as the untilDate causes the behaviour of EventLoopStep.Blocking
    // Passing distantPast as the untilDate causes the behaviour of EventLoopStep.Asynchronous
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
        // app.msgSend(void, "updateWindows", .{});
    }
    return activeWindows.load(.acquire) != 0;
}

pub const Label = struct {
    peer: objc.Object,

    pub usingnamespace Events(Label);

    pub fn create() !Label {
        const NSTextField = objc.getClass("NSTextField").?;
        const label = NSTextField.msgSend(objc.Object, "labelWithString:", .{AppKit.nsString("")});
        return Label{
            .peer = label,
        };
    }

    pub fn setAlignment(self: *Label, alignment: f32) void {
        _ = self;
        _ = alignment;
    }

    pub fn setText(self: *Label, text: []const u8) void {
        const nullTerminatedText = lib.internal.scratch_allocator.dupeZ(u8, text) catch return;
        defer lib.internal.scratch_allocator.free(nullTerminatedText);
        self.peer.msgSend(void, "setStringValue:", .{AppKit.nsString(nullTerminatedText)});
    }

    pub fn setFont(self: *Label, font: lib.Font) void {
        _ = self;
        _ = font;
    }

    pub fn destroy(self: *Label) void {
        _ = self;
    }
};
