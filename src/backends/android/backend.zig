const std = @import("std");
const shared = @import("../shared.zig");
const lib = @import("../../main.zig");
const android = @import("android");

const EventFunctions = shared.EventFunctions(@This());
const EventType = shared.BackendEventType;
const BackendError = shared.BackendError;
const MouseButton = shared.MouseButton;
//pub const PeerType = *c.GtkWidget;
pub const PeerType = *opaque {};

var activeWindows = std.atomic.Atomic(usize).init(0);
var hasInit: bool = false;

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

pub inline fn getEventUserData(peer: PeerType) *EventUserData {
    _ = peer;
    //return @ptrCast(*EventUserData, @alignCast(@alignOf(EventUserData), c.g_object_get_data(@ptrCast(*c.GObject, peer), "eventUserData").?));
}

pub fn Events(comptime T: type) type {
    _ = T;
    return struct {};
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
    }

    pub fn setTitle(self: *Window, title: [*:0]const u8) void {
        _ = self;
        _ = title;
    }

    pub fn setChild(self: *Window, peer: ?PeerType) void {
        _ = self;
        _ = peer;
    }

    pub fn setSourceDpi(self: *Window, dpi: u32) void {
        self.source_dpi = 96;
        // TODO
        const resolution = @as(f32, 96.0);
        self.scale = resolution / @intToFloat(f32, dpi);
    }

    pub fn show(self: *Window) void {
        _ = self;
        _ = activeWindows.fetchAdd(1, .Release);
    }

    pub fn close(self: *Window) void {
        _ = self;
        @panic("TODO: close window");
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
    //pub const ANativeActivity_onCreate = @import("android-support.zig").ANativeActivity_onCreate;

    // pub fn panic(msg: []const u8, _: ?*std.builtin.StackTrace, _: ?usize) noreturn {
    //     _ = msg;

    //     @breakpoint();
    //     unreachable;
    // }

    comptime {
        _ = android.ANativeActivity_createFunc;
        _ = android.ANativeActivity_onCreate;
    }


    pub const AndroidApp = struct {
        allocator: std.mem.Allocator,
        activity: *android.ANativeActivity,
        jni: android.JNI = undefined,
        thread: ?std.Thread = null,
        running: bool = true,

        // TODO: add an interface in capy for handling stored state
        pub fn init(allocator: std.mem.Allocator, activity: *android.ANativeActivity, stored_state: ?[]const u8) !AndroidApp {
            _ = stored_state;
            std.log.info("HELLO WORLD", .{});

            return AndroidApp{
                .allocator = allocator,
                .activity = activity,
            };
        }

        pub fn start(self: *AndroidApp) !void {
            std.log.info("start", .{});
            self.thread = try std.Thread.spawn(.{}, mainLoop, .{ self });
        }

        pub fn deinit(self: *AndroidApp) void {
            @atomicStore(bool, &self.running, false, .SeqCst);
            if (self.thread) |thread| {
                thread.join();
                self.thread = null;
            }
            self.jni.deinit();
            std.log.info("end", .{});
        }

        pub fn onNativeWindowCreated(self: *AndroidApp, window: *android.ANativeWindow) void {
            //_ = window;
            _ = self;
            //android.ANativeWindow_release(window);
            _ = android.ANativeWindow_unlockAndPost(window);
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
            while (@atomicLoad(bool, &self.running, .SeqCst)) {
                std.time.sleep(1 * std.time.ns_per_s);
            }
        }

    };
    
};
