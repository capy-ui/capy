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

var activeWindows = std.atomic.Value(usize).init(0);
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
    const msg = std.fmt.allocPrintSentinel(lib.internal.allocator, fmt, args, 0) catch {
        std.log.err("Could not launch message dialog, original text: " ++ fmt, args);
        return;
    };
    defer lib.internal.allocator.free(msg);
    _ = msgType;
    @panic("TODO: message dialogs on macOS");
}

/// user data used for handling events
pub const EventUserData = struct {
    user: EventFunctions = .{},
    class: EventFunctions = .{},
    userdata: usize = 0,
    classUserdata: usize = 0,
    peer: objc.Object,
    focusOnClick: bool = false,
};

pub const GuiWidget = struct {
    object: objc.Object,
    data: *EventUserData,
};

pub inline fn getEventUserData(peer: GuiWidget) *EventUserData {
    return peer.data;
}

pub fn Events(comptime T: type) type {
    return struct {
        const Self = @This();

        pub fn setupEvents(peer: GuiWidget) BackendError!void {
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
            _ = self;
            return lib.Size.init(
                100,
                100,
            );
        }

        pub fn requestDraw(self: *T) !void {
            self.peer.object.msgSend(void, "setNeedsDisplay:", .{@as(u8, @intFromBool(true))});
        }

        pub fn deinit(self: *const T) void {
            const peer = self.peer;
            lib.internal.allocator.destroy(peer.data);
        }
    };
}

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
            .peer = GuiWidget{
                .object = window,
                .data = try lib.internal.allocator.create(EventUserData),
            },
        };
    }

    pub fn resize(self: *Window, width: c_int, height: c_int) void {
        var frame = self.peer.object.getProperty(AppKit.NSRect, "frame");
        frame.size.width = @floatFromInt(width);
        frame.size.height = @floatFromInt(height);
        self.peer.object.msgSend(void, "setFrame:display:", .{ frame, true });
    }

    pub fn setTitle(self: *Window, title: [*:0]const u8) void {
        const pool = objc.AutoreleasePool.init();
        defer pool.deinit();

        self.peer.object.setProperty("title", AppKit.nsString(title));
    }

    pub fn setChild(self: *Window, optional_peer: ?GuiWidget) void {
        if (optional_peer) |peer| {
            self.peer.object.setProperty("contentView", peer);
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
        self.peer.object.msgSend(void, "makeKeyAndOrderFront:", .{self.peer.object.value});
        _ = activeWindows.fetchAdd(1, .release);
    }

    pub fn close(self: *Window) void {
        self.peer.object.msgSend(void, "close", .{});
        _ = activeWindows.fetchSub(1, .release);
    }

    pub fn setMenuBar(self: *Window, bar: anytype) void {
        _ = self;
        _ = bar;
        // TODO: implement NSMenu on macOS
    }

    pub fn setFullscreen(self: *Window, monitor: anytype, video_mode: anytype) void {
        _ = self;
        _ = monitor;
        _ = video_mode;
        // TODO: implement fullscreen on macOS
    }

    pub fn unfullscreen(self: *Window) void {
        _ = self;
        // TODO: implement unfullscreen on macOS
    }
};

var cachedFlippedNSView: ?objc.Class = null;
fn getFlippedNSView() !objc.Class {
    if (cachedFlippedNSView) |notNull| {
        return notNull;
    }

    const FlippedNSView = objc.allocateClassPair(objc.getClass("NSView").?, "FlippedNSView").?;
    defer objc.registerClassPair(FlippedNSView);
    const success = FlippedNSView.addMethod("isFlipped", struct {
        fn imp(target: objc.c.id, sel: objc.c.SEL) callconv(.c) u8 {
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
        const view = (try getFlippedNSView())
            .msgSend(objc.Object, "alloc", .{})
            .msgSend(objc.Object, "initWithFrame:", .{AppKit.NSRect.make(0, 0, 1, 1)});
        return Container{ .peer = GuiWidget{
            .object = view,
            .data = try lib.internal.allocator.create(EventUserData),
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
    }

    pub fn setTabOrder(self: *const Container, peers: []const GuiWidget) void {
        _ = peers;
        _ = self;
    }
};

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
        const NSView = objc.getClass("NSView").?;
        const view = NSView.msgSend(objc.Object, "alloc", .{})
            .msgSend(objc.Object, "initWithFrame:", .{AppKit.NSRect.make(0, 0, 1, 1)});
        return Canvas{
            .peer = GuiWidget{
                .object = view,
                .data = try lib.internal.allocator.create(EventUserData),
            },
        };
    }

    pub const DrawContextImpl = struct {
        pub const TextLayout = struct {
            wrap: ?f64 = null,

            pub const Font = struct {
                face: [:0]const u8,
                size: f64,
            };

            pub const TextSize = struct { width: u32, height: u32 };

            pub fn init() TextLayout {
                return TextLayout{};
            }

            pub fn setFont(self: *TextLayout, font: Font) void {
                _ = self;
                _ = font;
            }

            pub fn getTextSize(self: *TextLayout, str: []const u8) TextSize {
                _ = self;
                _ = str;
                return TextSize{ .width = 0, .height = 0 };
            }

            pub fn deinit(self: *TextLayout) void {
                _ = self;
            }
        };

        pub fn setColorRGBA(self: *DrawContextImpl, r: f32, g: f32, b: f32, a: f32) void {
            _ = self;
            _ = r;
            _ = g;
            _ = b;
            _ = a;
        }

        pub fn setLinearGradient(self: *DrawContextImpl, gradient: shared.LinearGradient) void {
            _ = self;
            _ = gradient;
        }

        pub fn rectangle(self: *DrawContextImpl, x: i32, y: i32, w: u32, h: u32) void {
            _ = self;
            _ = x;
            _ = y;
            _ = w;
            _ = h;
        }

        pub fn roundedRectangleEx(self: *DrawContextImpl, x: i32, y: i32, w: u32, h: u32, corner_radiuses: [4]f32) void {
            _ = self;
            _ = x;
            _ = y;
            _ = w;
            _ = h;
            _ = corner_radiuses;
        }

        pub fn ellipse(self: *DrawContextImpl, x: i32, y: i32, w: u32, h: u32) void {
            _ = self;
            _ = x;
            _ = y;
            _ = w;
            _ = h;
        }

        pub fn text(self: *DrawContextImpl, x: i32, y: i32, layout: TextLayout, str: []const u8) void {
            _ = self;
            _ = x;
            _ = y;
            _ = layout;
            _ = str;
        }

        pub fn line(self: *DrawContextImpl, x1: i32, y1: i32, x2: i32, y2: i32) void {
            _ = self;
            _ = x1;
            _ = y1;
            _ = x2;
            _ = y2;
        }

        pub fn image(self: *DrawContextImpl, x: i32, y: i32, w: u32, h: u32, data: lib.ImageData) void {
            _ = self;
            _ = x;
            _ = y;
            _ = w;
            _ = h;
            _ = data;
        }

        pub fn clear(self: *DrawContextImpl, x: u32, y: u32, w: u32, h: u32) void {
            _ = self;
            _ = x;
            _ = y;
            _ = w;
            _ = h;
        }

        pub fn setStrokeWidth(self: *DrawContextImpl, width: f32) void {
            _ = self;
            _ = width;
        }

        pub fn stroke(self: *DrawContextImpl) void {
            _ = self;
        }

        pub fn fill(self: *DrawContextImpl) void {
            _ = self;
        }
    };
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
        return Label{
            .peer = GuiWidget{
                .object = label,
                .data = try lib.internal.allocator.create(EventUserData),
            },
        };
    }

    pub fn setAlignment(self: *Label, alignment: f32) void {
        _ = self;
        _ = alignment;
    }

    pub fn setText(self: *Label, text: []const u8) void {
        const nullTerminatedText = lib.internal.allocator.dupeZ(u8, text) catch return;
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

// --- Stub types for macOS (TODO: implement in Phase 3) ---

fn stubGuiWidget() BackendError!GuiWidget {
    const NSView = objc.getClass("NSView").?;
    const view = NSView.msgSend(objc.Object, "alloc", .{})
        .msgSend(objc.Object, "initWithFrame:", .{AppKit.NSRect.make(0, 0, 1, 1)});
    return GuiWidget{
        .object = view,
        .data = try lib.internal.allocator.create(EventUserData),
    };
}

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
        return ScrollView{ .peer = try stubGuiWidget() };
    }

    pub fn setChild(self: *ScrollView, child_peer: GuiWidget, child_widget: anytype) void {
        _ = self;
        _ = child_peer;
        _ = child_widget;
    }
};

pub const TextField = struct {
    peer: GuiWidget,
    text: ?[]const u8 = null,

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
        return TextField{ .peer = try stubGuiWidget() };
    }

    pub fn setText(self: *TextField, text: []const u8) void {
        if (self.text) |old| lib.internal.allocator.free(old);
        self.text = lib.internal.allocator.dupe(u8, text) catch return;
    }

    pub fn getText(self: *TextField) []const u8 {
        return self.text orelse "";
    }

    pub fn setReadOnly(self: *TextField, read_only: bool) void {
        _ = self;
        _ = read_only;
    }

    pub fn deinit(self: *const TextField) void {
        if (self.text) |t| lib.internal.allocator.free(t);
        _events.deinit(self);
    }
};

pub const TextArea = struct {
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

    pub fn create() BackendError!TextArea {
        return TextArea{ .peer = try stubGuiWidget() };
    }

    pub fn setText(self: *TextArea, text: []const u8) void {
        _ = self;
        _ = text;
    }

    pub fn getText(self: *TextArea) []const u8 {
        _ = self;
        return "";
    }

    pub fn setMonospaced(self: *TextArea, monospaced: bool) void {
        _ = self;
        _ = monospaced;
    }
};

pub const CheckBox = struct {
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

    pub fn create() BackendError!CheckBox {
        return CheckBox{ .peer = try stubGuiWidget() };
    }

    pub fn setChecked(self: *CheckBox, checked: bool) void {
        _ = self;
        _ = checked;
    }

    pub fn isChecked(self: *CheckBox) bool {
        _ = self;
        return false;
    }

    pub fn setEnabled(self: *CheckBox, enabled: bool) void {
        _ = self;
        _ = enabled;
    }

    pub fn setLabel(self: *CheckBox, label_text: [:0]const u8) void {
        _ = self;
        _ = label_text;
    }

    pub fn getLabel(self: *CheckBox) [:0]const u8 {
        _ = self;
        return "";
    }
};

pub const Slider = struct {
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

    pub fn create() BackendError!Slider {
        return Slider{ .peer = try stubGuiWidget() };
    }

    pub fn getValue(self: *Slider) f32 {
        _ = self;
        return 0;
    }

    pub fn setValue(self: *Slider, value: f32) void {
        _ = self;
        _ = value;
    }

    pub fn setMinimum(self: *Slider, min: f32) void {
        _ = self;
        _ = min;
    }

    pub fn setMaximum(self: *Slider, max: f32) void {
        _ = self;
        _ = max;
    }

    pub fn setStepSize(self: *Slider, step: f32) void {
        _ = self;
        _ = step;
    }

    pub fn setEnabled(self: *Slider, enabled: bool) void {
        _ = self;
        _ = enabled;
    }

    pub fn setOrientation(self: *Slider, orientation: anytype) void {
        _ = self;
        _ = orientation;
    }
};

pub const Dropdown = struct {
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

    pub fn create() BackendError!Dropdown {
        return Dropdown{ .peer = try stubGuiWidget() };
    }

    pub fn getSelectedIndex(self: *Dropdown) ?usize {
        _ = self;
        return null;
    }

    pub fn setSelectedIndex(self: *Dropdown, index: ?usize) void {
        _ = self;
        _ = index;
    }

    pub fn setValues(self: *Dropdown, values: anytype) void {
        _ = self;
        _ = values;
    }

    pub fn setEnabled(self: *Dropdown, enabled: bool) void {
        _ = self;
        _ = enabled;
    }
};

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
        return TabContainer{ .peer = try stubGuiWidget() };
    }

    pub fn insert(self: *TabContainer, position: usize, child_peer: GuiWidget) usize {
        _ = self;
        _ = child_peer;
        return position;
    }

    pub fn setLabel(self: *TabContainer, position: usize, label_text: [:0]const u8) void {
        _ = self;
        _ = position;
        _ = label_text;
    }

    pub fn getTabsNumber(self: *TabContainer) usize {
        _ = self;
        return 0;
    }
};

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
        return NavigationSidebar{ .peer = try stubGuiWidget() };
    }

    pub fn append(self: *NavigationSidebar, item: anytype) void {
        _ = self;
        _ = item;
    }
};

pub const ImageData = struct {
    pub fn from(width: usize, height: usize, stride: usize, cs: lib.Colorspace, bytes: []const u8) !ImageData {
        _ = width;
        _ = height;
        _ = stride;
        _ = cs;
        _ = bytes;
        return ImageData{};
    }

    pub fn draw(self: *ImageData) DrawLock {
        _ = self;
        return DrawLock{};
    }

    pub fn deinit(self: *ImageData) void {
        _ = self;
    }

    pub const DrawLock = struct {
        pub fn end(self: *DrawLock) void {
            _ = self;
        }
    };
};

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
