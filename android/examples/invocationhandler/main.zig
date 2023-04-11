const std = @import("std");

const android = @import("android");

pub const panic = android.panic;

const EGLContext = android.egl.EGLContext;
const JNI = android.JNI;
const NativeActivity = android.NativeActivity;
const c = android.egl.c;
const NativeInvocationHandler = android.NativeInvocationHandler;

const app_log = std.log.scoped(.app);
comptime {
    _ = android.ANativeActivity_createFunc;
}

const ButtonData = struct {
    count: usize = 0,
};

pub fn timerInvoke(data: ?*anyopaque, jni: *android.JNI, method: android.jobject, args: android.jobjectArray) !android.jobject {
    var btn_data = @ptrCast(*ButtonData, @alignCast(@alignOf(*ButtonData), data));
    btn_data.count += 1;
    std.log.info("Running invoke!", .{});
    const method_name = try android.JNI.String.init(jni, try jni.callObjectMethod(method, "getName", "()Ljava/lang/String;", .{}));
    defer method_name.deinit(jni);
    std.log.info("Method {}", .{std.unicode.fmtUtf16le(method_name.slice)});

    const length = try jni.invokeJni(.GetArrayLength, .{args});
    var i: i32 = 0;
    while (i < length) : (i += 1) {
        const object = try jni.invokeJni(.GetObjectArrayElement, .{ args, i });
        const string = try android.JNI.String.init(jni, try jni.callObjectMethod(object, "toString", "()Ljava/lang/String;", .{}));
        defer string.deinit(jni);
        std.log.info("Arg {}: {}", .{ i, std.unicode.fmtUtf16le(string.slice) });

        if (i == 0) {
            const Button = try jni.findClass("android/widget/Button");
            var buf: [256:0]u8 = undefined;
            const str = std.fmt.bufPrintZ(&buf, "Pressed {} times!", .{btn_data.count}) catch "formatting bug";
            try Button.callVoidMethod(object, "setText", "(Ljava/lang/CharSequence;)V", .{try jni.newString(str)});
        }
    }

    return null;
}

pub const AndroidApp = struct {
    allocator: std.mem.Allocator,
    activity: *android.ANativeActivity,
    thread: ?std.Thread = null,
    running: bool = true,

    // The JNIEnv of the UI thread
    uiJni: android.NativeActivity = undefined,
    // The JNIEnv of the app thread
    mainJni: android.NativeActivity = undefined,

    invocation_handler: NativeInvocationHandler = undefined,

    // This is needed because to run a callback on the UI thread Looper you must
    // react to a fd change, so we use a pipe to force it
    pipe: [2]std.os.fd_t = undefined,
    // This is used with futexes so that runOnUiThread waits until the callback is completed
    // before returning.
    uiThreadCondition: std.atomic.Atomic(u32) = std.atomic.Atomic(u32).init(0),
    uiThreadLooper: *android.ALooper = undefined,
    uiThreadId: std.Thread.Id = undefined,

    btn_data: ButtonData = .{},

    pub fn init(allocator: std.mem.Allocator, activity: *android.ANativeActivity, stored_state: ?[]const u8) !AndroidApp {
        _ = stored_state;

        return AndroidApp{
            .allocator = allocator,
            .activity = activity,
        };
    }

    pub fn start(self: *AndroidApp) !void {
        // Initialize the variables we need to execute functions on the UI thread
        self.uiThreadLooper = android.ALooper_forThread().?;
        self.uiThreadId = std.Thread.getCurrentId();
        self.pipe = try std.os.pipe();
        android.ALooper_acquire(self.uiThreadLooper);

        var native_activity = android.NativeActivity.init(self.activity);
        var jni = native_activity.jni;
        self.uiJni = native_activity;

        // Get the window object attached to our activity
        const ActivityClass = try jni.findClass("android/app/NativeActivity");
        const activityWindow = try ActivityClass.callObjectMethod(self.activity.clazz, "getWindow", "()Landroid/view/Window;", .{});

        // This disables the surface handler set by default by android.view.NativeActivity
        // This way we let the content view do the drawing instead of us.
        const WindowClass = try jni.findClass("android/view/Window");
        try WindowClass.callVoidMethod(activityWindow, "takeSurface", "(Landroid/view/SurfaceHolder$Callback2;)V", .{@as(android.jobject, null)});

        // Do the same but with the input queue. This allows the content view to handle input.
        try WindowClass.callVoidMethod(activityWindow, "takeInputQueue", "(Landroid/view/InputQueue$Callback;)V", .{@as(android.jobject, null)});

        self.thread = try std.Thread.spawn(.{}, mainLoop, .{self});
    }

    /// Run the given function on the Android UI thread. This is necessary for manipulating the view hierarchy.
    /// Note: this function is not thread-safe, but could be made so simply using a mutex
    pub fn runOnUiThread(self: *AndroidApp, comptime func: anytype, args: anytype) !void {
        if (std.Thread.getCurrentId() == self.uiThreadId) {
            // runOnUiThread has been called from the UI thread.
            @call(.auto, func, args);
            return;
        }

        const Args = @TypeOf(args);
        const allocator = self.allocator;

        const Data = struct { args: Args, self: *AndroidApp };

        const data_ptr = try allocator.create(Data);
        data_ptr.* = .{ .args = args, .self = self };
        errdefer allocator.destroy(data_ptr);

        const Instance = struct {
            fn callback(_: c_int, _: c_int, data: ?*anyopaque) callconv(.C) c_int {
                const data_struct = @ptrCast(*Data, @alignCast(@alignOf(Data), data.?));
                const self_ptr = data_struct.self;
                defer self_ptr.allocator.destroy(data_struct);

                @call(.auto, func, data_struct.args);
                std.Thread.Futex.wake(&self_ptr.uiThreadCondition, 1);
                return 0;
            }
        };

        const result = android.ALooper_addFd(
            self.uiThreadLooper,
            self.pipe[0],
            0,
            android.ALOOPER_EVENT_INPUT,
            Instance.callback,
            data_ptr,
        );
        std.debug.assert(try std.os.write(self.pipe[1], "hello") == 5);
        if (result == -1) {
            return error.LooperError;
        }

        std.Thread.Futex.wait(&self.uiThreadCondition, 0);
    }

    pub fn getJni(self: *AndroidApp) JNI {
        return JNI.get(self.activity);
    }

    pub fn deinit(self: *AndroidApp) void {
        @atomicStore(bool, &self.running, false, .SeqCst);
        if (self.thread) |thread| {
            thread.join();
            self.thread = null;
        }
        android.ALooper_release(self.uiThreadLooper);
        self.uiJni.deinit();
    }

    fn setAppContentView(self: *AndroidApp) void {
        setAppContentViewImpl(self) catch |e| {
            app_log.err("Encountered error while setting app content view: {s}", .{@errorName(e)});
        };
    }

    fn setAppContentViewImpl(self: *AndroidApp) !void {
        const native_activity = android.NativeActivity.get(self.activity);
        const jni = native_activity.jni;

        std.log.warn("Creating android.widget.Button", .{});
        const Button = try jni.findClass("android/widget/Button");

        // We create a new Button..
        const button = try Button.newObject("(Landroid/content/Context;)V", .{self.activity.clazz});

        // .. set its text to "Hello from Zig!" ..
        try Button.callVoidMethod(button, "setText", "(Ljava/lang/CharSequence;)V", .{try jni.newString("Hello from Zig!")});

        // .. and set its callback
        const listener = try self.getOnClickListener(jni);
        try Button.callVoidMethod(button, "setOnClickListener", "(Landroid/view/View$OnClickListener;)V", .{listener});

        // And then we use it as our content view!
        std.log.err("Attempt to call NativeActivity.setContentView()", .{});
        const NativeActivityClass = try jni.findClass("android/app/NativeActivity");
        try NativeActivityClass.callVoidMethod(self.activity.clazz, "setContentView", "(Landroid/view/View;)V", .{button});
    }

    fn mainLoop(self: *AndroidApp) !void {
        self.mainJni = android.NativeActivity.init(self.activity);
        defer self.mainJni.deinit();

        try self.runOnUiThread(setAppContentView, .{self});
        while (self.running) {
            std.time.sleep(1 * std.time.ns_per_s);
        }
    }

    fn getOnClickListener(self: *AndroidApp, jni: *JNI) !android.jobject {
        // Get class loader instance
        const ActivityClass = try jni.findClass("android/app/NativeActivity");
        const cls = try ActivityClass.callObjectMethod(self.activity.clazz, "getClassLoader", "()Ljava/lang/ClassLoader;", .{});

        // Class loader class object
        const ClassLoader = try jni.findClass("java/lang/ClassLoader");
        const strClassName = try jni.newString("NativeInvocationHandler");
        defer jni.invokeJniNoException(.DeleteLocalRef, .{strClassName});
        const NativeInvocationHandlerClass = try ClassLoader.callObjectMethod(cls, "loadClass", "(Ljava/lang/String;)Ljava/lang/Class;", .{strClassName});

        // Get invocation handler factory
        self.invocation_handler = try NativeInvocationHandler.init(jni, NativeInvocationHandlerClass);

        // Create a NativeInvocationHandler
        const invocation_handler = try self.invocation_handler.createAlloc(jni, self.allocator, &self.btn_data, &timerInvoke);

        // Make an object array with 1 item, the android.view.View$OnClickListener interface class
        const interface_array = try jni.invokeJni(.NewObjectArray, .{
            1,
            try jni.invokeJni(.FindClass, .{"java/lang/Class"}),
            try jni.invokeJni(.FindClass, .{"android/view/View$OnClickListener"}),
        });

        // Create a Proxy class implementing the OnClickListener interface
        const Proxy = try jni.findClass("java/lang/reflect/Proxy");
        const proxy = Proxy.callStaticObjectMethod(
            "newProxyInstance",
            "(Ljava/lang/ClassLoader;[Ljava/lang/Class;Ljava/lang/reflect/InvocationHandler;)Ljava/lang/Object;",
            .{ cls, interface_array, invocation_handler },
        );

        return proxy;
    }
};
