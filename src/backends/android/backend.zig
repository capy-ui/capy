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

const NativeActivity = android.NativeActivity;

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
    overridenSize: ?lib.Size = null,
};

const EVENT_USER_DATA_KEY: c_int = 1888792543; // guarenteed by a fair dice roll
pub inline fn getEventUserData(peer: PeerType) *EventUserData {
    const jni = theApp.getJni();
    const View = jni.findClass("android/view/View") catch unreachable;
    const tag = View.callObjectMethod(peer, "getTag", "(I)Ljava/lang/Object;", .{EVENT_USER_DATA_KEY}) catch unreachable;

    const Long = jni.findClass("java/lang/Long") catch unreachable;
    const value = Long.callLongMethod(tag, "longValue", "()J", .{}) catch unreachable;
    return @intToPtr(*EventUserData, @bitCast(u64, value));
}

pub fn Events(comptime T: type) type {
    return struct {
        const Self = @This();

        pub fn setupEvents(widget: PeerType) BackendError!void {
            const jni = theApp.getJni();
            var data = try lib.internal.lasting_allocator.create(EventUserData);
            data.* = EventUserData{ .peer = widget }; // ensure that it uses default values
            std.log.info("Cast {*} to Long", .{data});

            // Wrap the memory address in a Long object
            // As long as we treat the Long as an unsigned number on our side, this supports all possible
            // 64-bit addresses.
            const Long = jni.findClass("java/lang/Long") catch return error.InitializationError;
            const dataAddress = Long.newObject("(J)V", .{ @ptrToInt(data) }) catch return error.InitializationError;

            const View = jni.findClass("android/view/View") catch return error.InitializationError;
            View.callVoidMethod(widget, "setTag", "(ILjava/lang/Object;)V", .{ EVENT_USER_DATA_KEY, dataAddress }) catch return error.InitializationError;
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
            const data = getEventUserData(self.peer);
            if (data.overridenSize) |size| {
                return @intCast(c_int, size.width);
            }

            const jni = theApp.getJni();
            const View = jni.findClass("android/view/View") catch unreachable;
            const width = View.callIntMethod(self.peer, "getMeasuredWidth", "()I", .{}) catch unreachable;
            return width;
        }

        pub fn getHeight(self: *const T) c_int {
            const data = getEventUserData(self.peer);
            if (data.overridenSize) |size| {
                return @intCast(c_int, size.height);
            }

            const jni = theApp.getJni();
            const View = jni.findClass("android/view/View") catch unreachable;
            const height = View.callIntMethod(self.peer, "getMeasuredHeight", "()I", .{}) catch unreachable;
            return height;
        }

        pub fn getPreferredSize(self: *const T) lib.Size {
            // TODO
            _ = self;
            return lib.Size.init(
                200,
                100,
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

    pub fn setChild(self: *Window, in_peer: ?PeerType) void {
        self.show();

        theApp.runOnUiThread(struct {
            fn callback(peer: ?PeerType) void {
                const jni = theApp.getJni();
                const activityClass = jni.findClass("android/app/NativeActivity") catch unreachable;
                std.log.info("NativeActivity.setContentView({?})", .{peer});
                activityClass.callVoidMethod(
                    theApp.activity.clazz,
                    "setContentView",
                    "(Landroid/view/View;)V",
                    .{peer},
                ) catch unreachable;
            }
        }.callback, .{in_peer}) catch unreachable;

        const data = getEventUserData(in_peer.?);
        data.overridenSize = lib.Size.init(720, 1080);
        data.user.resizeHandler.?(720, 800, data.userdata);
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
            _ = activeWindows.fetchAdd(1, .SeqCst);
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
        var view: PeerType = undefined;
        theApp.runOnUiThread(struct {
            fn callback(view_ptr: *PeerType) void {
                std.log.info("Creating android.widget.Button", .{});
                const jni = theApp.getJni();
                const AndroidButton = jni.findClass("android/widget/Button") catch unreachable;
                const peer = (AndroidButton.newObject("(Landroid/content/Context;)V", .{theApp.activity.clazz}) catch unreachable).?;
                Button.setupEvents(peer) catch unreachable;
                view_ptr.* = jni.invokeJniNoException(.NewGlobalRef, .{peer}).?;
            }
        }.callback, .{&view}) catch unreachable;
        return Button{ .peer = view };
    }

    pub fn setLabel(self: *const Button, label: [:0]const u8) void {
        const jni = theApp.getJni();
        const ButtonClass = jni.findClass("android/widget/Button") catch unreachable;
        ButtonClass.callVoidMethod(self.peer, "setText", "(Ljava/lang/CharSequence;)V", .{jni.newString(label) catch unreachable}) catch unreachable;
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

pub const Label = struct {
    peer: PeerType,

    pub usingnamespace Events(Label);

    pub fn create() BackendError!Label {
        var view: PeerType = undefined;
        theApp.runOnUiThread(struct {
            fn callback(view_ptr: *PeerType) void {
                std.log.info("Creating android.widget.TextView", .{});
                const jni = theApp.getJni();
                const TextView = jni.findClass("android/widget/TextView");
                const peerInit = jni.invokeJni(.GetMethodID, .{ TextView, "<init>", "(Landroid/content/Context;)V" });
                const peer = jni.invokeJni(.NewObject, .{ TextView, peerInit, theApp.activity.clazz }).?;
                Label.setupEvents(peer) catch unreachable;
                view_ptr.* = jni.invokeJni(.NewGlobalRef, .{peer}).?;
            }
        }.callback, .{&view}) catch unreachable;
        return Label{ .peer = view };
    }

    pub fn setText(self: *Label, text: [:0]const u8) void {
        const jni = theApp.getJni();
        const TextView = jni.findClass("android/widget/TextView") catch unreachable;
        TextView.callVoidMethod(self.peer, .{ "setText", "(Ljava/lang/CharSequence;)V", jni.newString(text) catch unreachable }) catch unreachable;
    }

    pub fn getText(self: *Label) [:0]const u8 {
        _ = self;
        return "";
    }

    pub fn setAlignment(self: *Label, alignment: f32) void {
        _ = self;
        _ = alignment;
    }
};

pub const TextField = struct {
    peer: PeerType,

    pub usingnamespace Events(TextField);

    pub fn create() BackendError!TextField {
        var view: PeerType = undefined;
        theApp.runOnUiThread(struct {
            fn callback(view_ptr: *PeerType) void {
                std.log.info("Creating android.widget.EditText", .{});
                const jni = theApp.getJni();
                const EditText = jni.findClass("android/widget/EditText") catch unreachable;
                const peer = (EditText.newObject("(Landroid/content/Context;)V", .{theApp.activity.clazz}) catch unreachable).?;
                TextField.setupEvents(peer) catch unreachable;
                view_ptr.* = jni.invokeJniNoException(.NewGlobalRef, .{peer}).?;
            }
        }.callback, .{&view}) catch unreachable;
        return TextField{ .peer = view };
    }

    pub fn setText(self_ptr: *TextField, text_ptr: []const u8) void {
        theApp.runOnUiThread(struct {
            fn callback(self: *TextField, text: []const u8) void {
                const allocator = lib.internal.scratch_allocator;
                const nulTerminated = allocator.dupeZ(u8, text) catch return;
                defer allocator.free(nulTerminated);

                const jni = theApp.getJni();
                const EditText = jni.findClass("android/widget/EditText") catch unreachable;
                EditText.callVoidMethod(self.peer, "setText", "(Ljava/lang/CharSequence;)V", .{jni.newString(nulTerminated) catch unreachable}) catch unreachable;
            }
        }.callback, .{ self_ptr, text_ptr }) catch unreachable;
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
        var layout: PeerType = undefined;
        theApp.runOnUiThread(struct {
            fn callback(layout_ptr: *PeerType) void {
                std.log.info("Creating android.widget.AbsoluteLayout", .{});
                const jni = theApp.getJni();
                const AbsoluteLayout = jni.findClass("android/widget/AbsoluteLayout") catch unreachable;
                const view = (AbsoluteLayout.newObject("(Landroid/content/Context;)V", .{theApp.activity.clazz}) catch unreachable).?;
                Container.setupEvents(view) catch unreachable; // TODO: bubble up errors
                layout_ptr.* = jni.invokeJniNoException(.NewGlobalRef, .{view}).?;
            }
        }.callback, .{&layout}) catch unreachable;
        return Container{ .peer = layout };
    }

    pub fn add(in_self: *const Container, in_peer: PeerType) void {
        theApp.runOnUiThread(struct {
            fn callback(self: *const Container, peer: PeerType) void {
                const jni = theApp.getJni();
                const AbsoluteLayout = jni.findClass("android/widget/AbsoluteLayout") catch unreachable;
                const LayoutParams = jni.findClass("android/widget/AbsoluteLayout$LayoutParams") catch unreachable;
                const params = LayoutParams.newObject("(IIII)V", .{ @as(c_int, 100), @as(c_int, 100), @as(c_int, 0), @as(c_int, 0) }) catch unreachable;
                AbsoluteLayout.callVoidMethod(self.peer, "addView", "(Landroid/view/View;Landroid/view/ViewGroup$LayoutParams;)V", .{ peer, params }) catch unreachable;
            }
        }.callback, .{ in_self, in_peer }) catch unreachable;
    }

    pub fn remove(self: *const Container, peer: PeerType) void {
        _ = self;
        _ = peer;
        @panic("TODO: remove");
    }

    pub fn move(in_self: *const Container, in_peer: PeerType, in_x: u32, in_y: u32) void {
        theApp.runOnUiThread(struct {
            fn callback(self: *const Container, peer: PeerType, x: u32, y: u32) void {
                //std.log.info("move {*} to {d}, {d}", .{ peer, x, y });
                const jni = theApp.getJni();
                const View = jni.findClass("android/view/View") catch unreachable;
                const params = View.callObjectMethod(peer, "getLayoutParams", "()Landroid/view/ViewGroup$LayoutParams;", .{}) catch unreachable;

                const LayoutParams = jni.findClass("android/widget/AbsoluteLayout$LayoutParams") catch unreachable;
                LayoutParams.setIntField(params, "x", "I", @intCast(android.jint, x)) catch unreachable;
                LayoutParams.setIntField(params, "y", "I", @intCast(android.jint, y)) catch unreachable;

                const AbsoluteLayout = jni.findClass("android/widget/AbsoluteLayout") catch unreachable;
                AbsoluteLayout.callVoidMethod(self.peer, "updateViewLayout", "(Landroid/view/View;Landroid/view/ViewGroup$LayoutParams;)V", .{ peer, params }) catch unreachable;
            }
        }.callback, .{ in_self, in_peer, in_x, in_y }) catch unreachable;
    }

    pub fn resize(in_self: *const Container, in_peer: PeerType, in_w: u32, in_h: u32) void {
        theApp.runOnUiThread(struct {
            fn callback(self: *const Container, peer: PeerType, w: u32, h: u32) void {
                //std.log.info("resize {*} to {d}, {d}", .{ peer, w, h });
                const jni = theApp.getJni();
                const View = jni.findClass("android/view/View") catch unreachable;
                const params = View.callObjectMethod(peer, "getLayoutParams", "()Landroid/view/ViewGroup$LayoutParams;", .{}) catch unreachable;

                const LayoutParams = jni.findClass("android/widget/AbsoluteLayout$LayoutParams") catch unreachable;
                LayoutParams.setIntField(params, "width", "I", @intCast(android.jint, w)) catch unreachable;
                LayoutParams.setIntField(params, "height", "I", @intCast(android.jint, h)) catch unreachable;

                const AbsoluteLayout = jni.findClass("android/widget/AbsoluteLayout") catch unreachable;
                AbsoluteLayout.callVoidMethod(self.peer, "updateViewLayout", "(Landroid/view/View;Landroid/view/ViewGroup$LayoutParams;)V", .{ peer, params }) catch unreachable;

                // const measure = jni.invokeJni(.GetMethodID, .{ View, "measure", "(II)V" });
                // jni.invokeJni(.CallVoidMethod, .{ self.peer, measure, @as(c_int, 0), @as(c_int, 0) });
                getEventUserData(peer).overridenSize = lib.Size.init(w, h);
            }
        }.callback, .{ in_self, in_peer, in_w, in_h }) catch unreachable;
        getEventUserData(in_peer).user.resizeHandler.?(in_w, in_h, getEventUserData(in_peer).userdata);
    }
};

pub fn postEmptyEvent() void {
    @panic("TODO: postEmptyEvent");
}

pub fn runStep(step: shared.EventLoopStep) bool {
    _ = step;
    return activeWindows.load(.Acquire) != 0 and theApp.running;
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
        thread: ?std.Thread = null,
        uiThreadLooper: *android.ALooper = undefined,
        running: bool = true,

        // The JNIEnv of the UI thread
        uiJni: *android.JNI = undefined,
        // The JNIEnv of the app thread
        mainJni: *android.JNI = undefined,
        uiThreadId: std.Thread.Id = undefined,

        // This is needed because to run a callback on the UI thread Looper you must
        // react to a fd change, so we use a pipe to force it
        pipe: [2]std.os.fd_t = undefined,
        // This is used with futexes so that runOnUiThread waits until the callback is completed
        // before returning.
        uiThreadCondition: std.atomic.Atomic(u32) = std.atomic.Atomic(u32).init(0),

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
            self.uiThreadLooper = android.ALooper_forThread().?;
            self.uiThreadId = std.Thread.getCurrentId();
            self.pipe = try std.os.pipe();
            android.ALooper_acquire(self.uiThreadLooper);

            var native_activity = android.NativeActivity.init(self.activity);
            self.uiJni = native_activity.jni;
            const jni = native_activity.jni;

            std.log.info("Attempt to call NativeActivity.getWindow()", .{});
            const activityClass = try jni.findClass("android/app/NativeActivity");
            const activityWindow = try activityClass.callObjectMethod(self.activity.clazz, "getWindow", "()Landroid/view/Window;", .{});
            const WindowClass = try jni.findClass("android/view/Window");

            // This disables the surface handler set by default by android.view.NativeActivity
            // This way we let the content view do the drawing instead of us.
            try WindowClass.callVoidMethod(
                activityWindow,
                "takeSurface",
                "(Landroid/view/SurfaceHolder$Callback2;)V",
                .{@as(android.jobject, null)},
            );

            try WindowClass.callVoidMethod(
                activityWindow,
                "takeInputQueue",
                "(Landroid/view/InputQueue$Callback;)V",
                .{@as(android.jobject, null)},
            );

            // std.log.err("Attempt to call NativeActivity.clearContentView()", .{});
            // const activityClass = jni.findClass("android/app/NativeActivity");
            // const getWindow = jni.invokeJni(.GetMethodID, .{ activityClass, "getWindow", "()Landroid/view/Window;" });
            // const window = jni.invokeJni(.CallObjectMethod, .{ self.activity.clazz, getWindow });
            // const PhoneWindow = jni.findClass("com/android/internal/policy/PhoneWindow");
            // const clearContentView = jni.invokeJni(.GetMethodID, .{ PhoneWindow, "clearContentView", "()V" });
            // jni.invokeJni(.CallVoidMethod, .{
            //     window,
            //     clearContentView,
            // });
            self.thread = try std.Thread.spawn(.{}, mainLoop, .{self});
        }

        pub fn runOnUiThread(self: *AndroidApp, comptime func: anytype, args: anytype) !void {
            if (std.Thread.getCurrentId() == self.uiThreadId) {
                std.log.err("CALLED runOnUiThread FROM UI THREAD", .{});
                @call(.auto, func, args);
                return;
            }

            // TODO: use a mutex so that there aren't concurrent requests which wouldn't mix well with addFd
            const Args = @TypeOf(args);
            const allocator = lib.internal.scratch_allocator;

            const args_ptr = try allocator.create(Args);
            args_ptr.* = args;
            errdefer allocator.destroy(args_ptr);

            const Instance = struct {
                fn callback(_: c_int, _: c_int, data: ?*anyopaque) callconv(.C) c_int {
                    const args_data = @ptrCast(*Args, @alignCast(@alignOf(Args), data.?));
                    defer allocator.destroy(args_data);

                    @call(.auto, func, args_data.*);
                    std.Thread.Futex.wake(&theApp.uiThreadCondition, 1);
                    return 0;
                }
            };

            const result = android.ALooper_addFd(
                self.uiThreadLooper,
                self.pipe[0],
                0,
                android.ALOOPER_EVENT_INPUT,
                Instance.callback,
                args_ptr,
            );
            std.debug.assert(try std.os.write(self.pipe[1], "hello") == 5);
            if (result == -1) {
                return error.LooperError;
            }

            std.Thread.Futex.wait(&self.uiThreadCondition, 0);
        }

        pub fn getJni(self: *AndroidApp) *android.JNI {
            var native_activity = android.NativeActivity.get(self.activity);
            return native_activity.jni;
        }

        pub fn deinit(self: *AndroidApp) void {
            @atomicStore(bool, &self.running, false, .SeqCst);
            if (self.thread) |thread| {
                thread.join();
                self.thread = null;
            }
            android.ALooper_release(self.uiThreadLooper);
        }

        pub fn onNativeWindowCreated(self: *AndroidApp, window: *android.ANativeWindow) void {
            _ = self;
            _ = android.ANativeWindow_unlockAndPost(window);
        }

        fn setAppContentView(self: *AndroidApp) void {
            const jni = self.uiJni;

            const TextView = jni.findClass("android/widget/TextView") catch unreachable;
            const textView = TextView.newObject("(Landroid/content/Context;)V", .{self.activity.clazz}) catch unreachable;
            TextView.callVoidMethod(textView, "setText", "(Ljava/lang/CharSequence;)V", .{jni.newString("Hello from Zig!") catch unreachable}) catch unreachable;

            std.log.info("Attempt to call NativeActivity.getWindow()", .{});
            const activityClass = jni.findClass("android/app/NativeActivity") catch unreachable;

            std.log.err("Attempt to call NativeActivity.setContentView()", .{});
            activityClass.callVoidMethod(self.activity.clazz, "setContentView", "(Landroid/view/View;)V", .{textView}) catch unreachable;
        }

        fn mainLoop(self: *AndroidApp) !void {
            var native_activity = android.NativeActivity.init(self.activity);
            self.mainJni = native_activity.jni;

            try self.runOnUiThread(setAppContentView, .{self});
            try @import("root").main();
        }
    };
};
