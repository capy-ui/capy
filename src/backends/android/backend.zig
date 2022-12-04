const std = @import("std");
const shared = @import("../shared.zig");
const lib = @import("../../main.zig");
const android = @import("android");

const EventFunctions = shared.EventFunctions(@This());
const EventType = shared.BackendEventType;
const BackendError = shared.BackendError;
const MouseButton = shared.MouseButton;

pub const PeerType = *anyopaque; // jobject but not optional

var activeWindows = std.atomic.Atomic(usize).init(0);
var hasInit: bool = false;
var theApp: *backendExport.AndroidApp = undefined;

pub fn init() BackendError!void {
    if (!hasInit) {
        hasInit = true;
    }
}

pub fn showNativeMessageDialog(msgType: shared.MessageType, comptime fmt: []const u8, args: anytype) void {
    const msg = std.fmt.allocPrintZ(lib.internal.scratch_allocator, fmt, args) catch {
        std.log.err("Could not launch message dialog, original text: " ++ fmt, args);
        return;
    };
    defer lib.internal.scratch_allocator.free(msg);
    _ = msgType;
    @panic("TODO: message dialogs on Android");
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

const EVENT_USER_DATA_KEY: c_int = 1888792543; // guarenteed by a fair dice roll
pub inline fn getEventUserData(peer: PeerType) *EventUserData {
    const jni = &theApp.jni;
    const View = jni.findClass("android/view/View");
    const getTag = jni.invokeJni(.GetMethodID, .{ View, "getTag", "(I)Ljava/lang/Object;" });
    const tag = jni.invokeJni(.CallObjectMethod, .{ peer, getTag, EVENT_USER_DATA_KEY });

    const Long = jni.findClass("java/lang/Long");
    const longValue = jni.invokeJni(.GetMethodID, .{ Long, "longValue", "()J" });
    const value = jni.invokeJni(.CallLongMethod, .{ tag, longValue });
    return @intToPtr(*EventUserData, @bitCast(u64, value));
}

pub fn Events(comptime T: type) type {
    return struct {
        const Self = @This();

        pub fn setupEvents(widget: PeerType) BackendError!void {
            const jni = &theApp.jni;
            var data = try lib.internal.lasting_allocator.create(EventUserData);
            data.* = EventUserData{ .peer = widget }; // ensure that it uses default values
            std.log.info("Cast {*} to Long", .{ data });

            // Wrap the memory address in a Long object
            // Right now, it relies on the hope the memory address is < 0x7fffffffffffffff otherwise it will
            // overflow out of the Java long. But normally, it shouldn't happen.
            const Long = jni.findClass("java/lang/Long");
            const longInit = jni.invokeJni(.GetMethodID, .{ Long, "<init>", "(J)V" });
            std.debug.assert(@ptrToInt(data) <= 0x7fffffffffffffff);
            const dataAddress = jni.invokeJni(.NewObject, .{ Long, longInit, @ptrToInt(data) }) orelse return BackendError.InitializationError;

            const View = jni.findClass("android/view/View");
            const setTag = jni.invokeJni(.GetMethodID, .{ View, "setTag", "(ILjava/lang/Object;)V" });
            jni.invokeJni(.CallVoidMethod, .{ widget, setTag, EVENT_USER_DATA_KEY, dataAddress });
        }

        pub fn deinit(self: *const T) void {
            // TODO
            _ = self;
        }

        pub inline fn setUserData(self: *T, data: anytype) void {
            comptime {
                if (!std.meta.trait.isSingleItemPtr(@TypeOf(data))) {
                    @compileError(std.fmt.comptimePrint("Expected single item pointer, got {s}", .{@typeName(@TypeOf(data))}));
                }
            }

            getEventUserData(self.peer).userdata = @ptrToInt(data);
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
            }
        }

        pub fn setOpacity(self: *T, opacity: f64) void {
            // TODO
            _ = self;
            _ = opacity;
        }

        /// Requests a redraw
        pub fn requestDraw(self: *T) !void {
            // TODO
            _ = self;
        }

        pub fn getWidth(self: *const T) c_int {
            // TODO
            _ = self;
            return 10;
        }

        pub fn getHeight(self: *const T) c_int {
            // TODO
            _ = self;
            return 10;
        }

        pub fn getPreferredSize(self: *const T) lib.Size {
            // TODO
            _ = self;
            return lib.Size.init(
                10,
                10,
            );
        }
    };
}

pub const Window = struct {
    source_dpi: u32 = 96,
    scale: f32 = 1.0,

    pub usingnamespace Events(Window);

    pub fn create() BackendError!Window {
        return Window{};
    }

    pub fn resize(self: *Window, width: c_int, height: c_int) void {
        _ = self;
        _ = width;
        _ = height;
        // Cannot resize an activity on Android.
    }

    pub fn setTitle(self: *Window, title: [*:0]const u8) void {
        _ = self;
        _ = title;
        // Title is ignored on Android.
    }

    pub fn setChild(self: *Window, peer: ?PeerType) void {
        self.show();
        
        const jni = &theApp.jni;
        const activityClass = jni.findClass("android/app/NativeActivity");
        const setContentView = jni.invokeJni(.GetMethodID, .{ activityClass, "setContentView", "(Landroid/view/View;)V" });
        std.log.info("NativeActivity.setContentView({?})", .{ peer });
        jni.invokeJni(.CallVoidMethod, .{
            theApp.activity.clazz,
            setContentView,
            peer,
        });

        getEventUserData(peer.?).user.resizeHandler.?(800, 800, getEventUserData(peer.?).userdata);
    }

    pub fn setSourceDpi(self: *Window, dpi: u32) void {
        self.source_dpi = 96;
        // TODO
        const resolution = @as(f32, 96.0);
        self.scale = resolution / @intToFloat(f32, dpi);
    }

    pub fn show(_: *Window) void {
        if (activeWindows.load(.SeqCst) > 0) {
            // Cannot show more than one window
            // TODO: handle it as opening an other activity?
            return;
        } else {
            const jni = &theApp.jni;
            _ = activeWindows.fetchAdd(1, .SeqCst);
            std.log.info("edit activity", .{});
            
            // Get the window associated to the current NativeActivity
            const activityClass = jni.findClass("android/app/NativeActivity");
            const getWindow = jni.invokeJni(.GetMethodID, .{ activityClass, "getWindow", "()Landroid/view/Window;" });
            const activityWindow = jni.invokeJni(.CallObjectMethod, .{ theApp.activity.clazz, getWindow });
            const WindowClass = jni.findClass("android/view/Window");

            // This disables the surface handler set by default by android.view.NativeActivity
            // This way we let the content view do the drawing instead of us.
            const takeSurface = jni.invokeJni(.GetMethodID, .{ WindowClass, "takeSurface", "(Landroid/view/SurfaceHolder$Callback2;)V" });
            jni.invokeJni(.CallVoidMethod, .{
                activityWindow,
                takeSurface,
                @as(android.jobject, null),
            });
        }
    }

    pub fn close(self: *Window) void {
        _ = self;
        @panic("TODO: close window");
    }
};

pub const Button = struct {
    peer: PeerType,

    pub usingnamespace Events(Button);

    pub fn create() BackendError!Button {
        std.log.info("Creating android.widget.Button", .{});
        const jni = &theApp.jni;
        const AndroidButton = jni.findClass("android/widget/Button");
        const peerInit = jni.invokeJni(.GetMethodID, .{ AndroidButton, "<init>", "(Landroid/content/Context;)V" });
        const peer = jni.invokeJni(.NewObject, .{ AndroidButton, peerInit, theApp.activity.clazz }) orelse return BackendError.InitializationError;
        try Button.setupEvents(peer);
        return Button{ .peer = peer };
    }

    pub fn setLabel(self: *const Button, label: [:0]const u8) void {
        _ = self;
        _ = label;
    }

    pub fn getLabel(self: *const Button) [:0]const u8 {
        _ = self;
        return "";
    }

    pub fn setEnabled(self: *const Button, enabled: bool) void {
        _ = self;
        _ = enabled;
    }
};

pub const TextField = struct {
    peer: PeerType,

    pub usingnamespace Events(TextField);

    pub fn create() BackendError!TextField {
        std.log.info("Creating android.widget.EditText", .{});
        const jni = &theApp.jni;
        const EditText = jni.findClass("android/widget/EditText");
        const peerInit = jni.invokeJni(.GetMethodID, .{ EditText, "<init>", "(Landroid/content/Context;)V" });
        const peer = jni.invokeJni(.NewObject, .{ EditText, peerInit, theApp.activity.clazz }) orelse return BackendError.InitializationError;
        try TextField.setupEvents(peer);
        return TextField{ .peer = peer };
    }

    pub fn setText(self: *TextField, text: []const u8) void {
        _ = self;
        _ = text;
    }

    pub fn getText(self: *TextField) [:0]const u8 {
        _ = self;
        return "";
    }

    pub fn setReadOnly(self: *TextField, readOnly: bool) void {
        _ = self;
        _ = readOnly;
    }
};

pub const Canvas = struct {
    peer: PeerType,

    pub usingnamespace Events(Canvas);

    pub const DrawContext = struct {

        pub const Font = struct {
            face: [:0]const u8,
            size: f64,
        };

        pub const TextSize = struct { width: u32, height: u32 };

        pub const TextLayout = struct {
            wrap: ?f64 = null,

            pub fn setFont(self: *TextLayout, font: Font) void {
                // TODO
                _ = self;
                _ = font;
            }

            pub fn deinit(self: *TextLayout) void {
                // TODO
                _ = self;
            }

            pub fn getTextSize(self: *TextLayout, str: []const u8) TextSize {
                // TODO
                _ = self;
                _ = str;
                return TextSize{ .width = 0, .height = 0 };
            }

            pub fn init() TextLayout {
                return TextLayout{};
            }
        };

        pub fn setColorByte(self: *DrawContext, color: lib.Color) void {
            // TODO
            _ = self;
            _ = color;
        }

        pub fn setColor(self: *DrawContext, r: f32, g: f32, b: f32) void {
            self.setColorRGBA(r, g, b, 1);
        }

        pub fn setColorRGBA(self: *DrawContext, r: f32, g: f32, b: f32, a: f32) void {
            const color = lib.Color{
                .red = @floatToInt(u8, std.math.clamp(r, 0, 1) * 255),
                .green = @floatToInt(u8, std.math.clamp(g, 0, 1) * 255),
                .blue = @floatToInt(u8, std.math.clamp(b, 0, 1) * 255),
                .alpha = @floatToInt(u8, std.math.clamp(a, 0, 1) * 255),
            };
            self.setColorByte(color);
        }

        pub fn rectangle(self: *DrawContext, x: i32, y: i32, w: u32, h: u32) void {
            // TODO
            _ = self;
            _ = x;
            _ = y;
            _ = w;
            _ = h;
        }

        pub fn text(self: *DrawContext, x: i32, y: i32, layout: TextLayout, str: []const u8) void {
            // TODO
            _ = self;
            _ = x;
            _ = y;
            _ = layout;
            _ = str;
        }

        pub fn image(self: *DrawContext, x: i32, y: i32, w: u32, h: u32, data: lib.ImageData) void {
            // TODO
            _ = self;
            _ = x;
            _ = y;
            _ = w;
            _ = h;
            _ = data;
        }

        pub fn line(self: *DrawContext, x1: i32, y1: i32, x2: i32, y2: i32) void {
            // TODO
            _ = self;
            _ = x1;
            _ = y1;
            _ = x2;
            _ = y2;
        }

        pub fn ellipse(self: *DrawContext, x: i32, y: i32, w: u32, h: u32) void {
            // TODO
            _ = self;
            _ = x;
            _ = y;
            _ = w;
            _ = h;
        }

        pub fn clear(self: *DrawContext, x: u32, y: u32, w: u32, h: u32) void {
            // TODO
            _ = self;
            _ = x;
            _ = y;
            _ = w;
            _ = h;
        }

        pub fn stroke(self: *DrawContext) void {
            // TODO
            _ = self;
        }

        pub fn fill(self: *DrawContext) void {
            // TODO
            _ = self;
        }
    };

    pub fn create() !Canvas {
        return Canvas{ .peer = undefined };
    }
};

pub const Container = struct {
    peer: PeerType,

    pub usingnamespace Events(Container);

    pub fn create() BackendError!Container {
        std.log.info("Creating android.widget.AbsoluteLayout", .{});
        const jni = &theApp.jni;
        const AbsoluteLayout = jni.findClass("android/widget/AbsoluteLayout");
        const absoluteLayoutInit = jni.invokeJni(.GetMethodID, .{ AbsoluteLayout, "<init>", "(Landroid/content/Context;)V" });
        const layout = jni.invokeJni(.NewObject, .{ AbsoluteLayout, absoluteLayoutInit, theApp.activity.clazz }) orelse return BackendError.InitializationError;
        try Container.setupEvents(layout);
        return Container{ .peer = layout };
    }

    pub fn add(self: *const Container, peer: PeerType) void {
        std.log.info("add peer to container", .{});
        const jni = &theApp.jni;
        const LayoutParams = jni.findClass("android/widget/AbsoluteLayout$LayoutParams");
        const paramsInit = jni.invokeJni(.GetMethodID, .{ LayoutParams, "<init>", "(IIII)V" });
        const params = jni.invokeJni(.NewObject, .{ LayoutParams, paramsInit, @as(c_int, 100), @as(c_int, 100), @as(c_int, 0), @as(c_int, 0) }).?;

        const AbsoluteLayout = jni.findClass("android/widget/AbsoluteLayout");
        const addView = jni.invokeJni(.GetMethodID, .{ AbsoluteLayout, "addView", "(Landroid/view/View;Landroid/view/ViewGroup$LayoutParams;)V" });
        jni.invokeJni(.CallVoidMethod, .{ self.peer, addView, peer, params });
    }

    pub fn remove(self: *const Container, peer: PeerType) void {
        _ = self;
        _ = peer;
        @panic("TODO: remove");
    }

    pub fn move(self: *const Container, peer: PeerType, x: u32, y: u32) void {
        _ = self;
        std.log.info("move {*} to {d}, {d}", .{ peer, x, y });
    }

    pub fn resize(self: *const Container, peer: PeerType, w: u32, h: u32) void {
        _ = self;
        _ = peer;
        _ = w;
        _ = h;
    }
};

pub fn postEmptyEvent() void {
    @panic("TODO: postEmptyEvent");
}

pub fn runStep(step: shared.EventLoopStep) bool {
    _ = step;
    return activeWindows.load(.Acquire) != 0;
}

pub const backendExport = struct {
    comptime {
        _ = android.ANativeActivity_createFunc;
        _ = @import("root").log;
    }

    pub const panic = android.panic;
    pub const log = android.log;

    pub const AndroidApp = struct {
        allocator: std.mem.Allocator,
        activity: *android.ANativeActivity,
        jni: android.JNI = undefined,
        thread: ?std.Thread = null,
        running: bool = true,

        // TODO: add an interface in capy for handling stored state
        pub fn init(allocator: std.mem.Allocator, activity: *android.ANativeActivity, stored_state: ?[]const u8) !AndroidApp {
            _ = stored_state;

            return AndroidApp{
                .allocator = allocator,
                .activity = activity,
            };
        }

        pub fn start(self: *AndroidApp) !void {
            theApp = self;
            self.thread = try std.Thread.spawn(.{}, mainLoop, .{ self });
        }

        pub fn deinit(self: *AndroidApp) void {
            @atomicStore(bool, &self.running, false, .SeqCst);
            if (self.thread) |thread| {
                thread.join();
                self.thread = null;
            }
            self.jni.deinit();
        }

        pub fn onNativeWindowCreated(self: *AndroidApp, window: *android.ANativeWindow) void {
            _ = self;
            _ = window;
            std.log.info("native window created", .{});
        }

        fn setAppContentView(self: *AndroidApp) void {
            std.log.warn("Creating android.widget.TextView", .{});
            const TextView = self.jni.findClass("android/widget/TextView");
            const textViewInit = self.jni.invokeJni(.GetMethodID, .{ TextView, "<init>", "(Landroid/content/Context;)V" });
            const textView = self.jni.invokeJni(.NewObject, .{ TextView, textViewInit, self.activity.clazz });

            const setText = self.jni.invokeJni(.GetMethodID, .{ TextView, "setText", "(Ljava/lang/CharSequence;)V" });
            self.jni.invokeJni(.CallVoidMethod, .{ textView, setText, self.jni.newString("Hello from Zig!") });

            std.log.info("Attempt to call NativeActivity.getWindow()", .{});
            const activityClass = self.jni.findClass("android/app/NativeActivity");
            const getWindow = self.jni.invokeJni(.GetMethodID, .{ activityClass, "getWindow", "()Landroid/view/Window;" });
            const activityWindow = self.jni.invokeJni(.CallObjectMethod, .{ self.activity.clazz, getWindow });
            const WindowClass = self.jni.findClass("android/view/Window");

            // This disables the surface handler set by default by android.view.NativeActivity
            // This way we let the content view do the drawing instead of us.
            const takeSurface = self.jni.invokeJni(.GetMethodID, .{ WindowClass, "takeSurface", "(Landroid/view/SurfaceHolder$Callback2;)V" });
            self.jni.invokeJni(.CallVoidMethod, .{
                activityWindow,
                takeSurface,
                @as(android.jobject, null),
            });

            std.log.err("Attempt to call NativeActivity.setContentView()", .{});
            const setContentView = self.jni.invokeJni(.GetMethodID, .{ activityClass, "setContentView", "(Landroid/view/View;)V" });
            self.jni.invokeJni(.CallVoidMethod, .{
                self.activity.clazz,
                setContentView,
                textView,
            });
        }

        fn mainLoop(self: *AndroidApp) !void {
            self.jni = android.JNI.init(self.activity);
            self.setAppContentView();
            try @import("root").main();
        }

    };
    
};
