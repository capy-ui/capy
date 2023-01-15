const std = @import("std");
const log = std.log.scoped(.jni);
const android = @import("android-support.zig");

const Self = @This();

activity: *android.ANativeActivity,
jni: *android.JNI,
activity_class: android.JNI.Class,

pub fn init(activity: *android.ANativeActivity) Self {
    var env: *android.JNIEnv = undefined;
    _ = activity.vm.*.AttachCurrentThread(activity.vm, &env, null);
    return fromJniEnv(activity, env);
}

/// Get the JNIEnv associated with the current thread.
pub fn get(activity: *android.ANativeActivity) Self {
    var nullable_env: ?*android.JNIEnv = null;
    _ = activity.vm.*.GetEnv(activity.vm, @ptrCast(*?*anyopaque, &nullable_env), android.JNI_VERSION_1_6);
    if (nullable_env) |env| {
        return fromJniEnv(activity, env);
    } else {
        return init(activity);
    }
}

fn fromJniEnv(activity: *android.ANativeActivity, env: *android.JNIEnv) Self {
    var jni = @ptrCast(*android.JNI, env);
    var activityClass = jni.findClass("android/app/NativeActivity") catch @panic("Could not get NativeActivity class");

    return Self{
        .activity = activity,
        .jni = jni,
        .activity_class = activityClass,
    };
}

pub fn deinit(self: *Self) void {
    _ = self.activity.vm.*.DetachCurrentThread(self.activity.vm);
    self.* = undefined;
}

pub fn AndroidGetUnicodeChar(self: *Self, keyCode: c_int, metaState: c_int) !u21 {
    // https://stackoverflow.com/questions/21124051/receive-complete-android-unicode-input-in-c-c/43871301
    const eventType = android.AKEY_EVENT_ACTION_DOWN;

    const KeyEvent = try self.jni.findClass("android/view/KeyEvent");

    const event_obj = try KeyEvent.newObject("(II)V", .{ eventType, keyCode });
    const unicode_key = try KeyEvent.callIntMethod(event_obj, "getUnicodeChar", "(I)I", .{metaState});

    return @intCast(u21, unicode_key);
}

pub fn AndroidMakeFullscreen(self: *Self) !void {
    // Partially based on
    // https://stackoverflow.com/questions/47507714/how-do-i-enable-full-screen-immersive-mode-for-a-native-activity-ndk-app

    // Get android.app.NativeActivity, then get getWindow method handle, returns
    // view.Window type
    const ActivityClass = try self.jni.findClass("android/app/NativeActivity");
    const window = try ActivityClass.callObjectMethod(self.activity.clazz, "getWindow", "()Landroid/view/Window;", .{});

    // Get android.view.Window class, then get getDecorView method handle, returns
    // view.View type
    const WindowClass = try self.jni.findClass("android/view/Window");
    const decorView = try WindowClass.callObjectMethod(window, "getDecorView", "()Landroid/view/View;", .{});

    // Get the flag values associated with systemuivisibility
    const ViewClass = try self.jni.findClass("android/view/View");
    const flagLayoutHideNavigation = try ViewClass.getStaticIntField("SYSTEM_UI_FLAG_LAYOUT_HIDE_NAVIGATION");
    const flagLayoutFullscreen = try ViewClass.getStaticIntField("SYSTEM_UI_FLAG_LAYOUT_FULLSCREEN");
    const flagLowProfile = try ViewClass.getStaticIntField("SYSTEM_UI_FLAG_LOW_PROFILE");
    const flagHideNavigation = try ViewClass.getStaticIntField("SYSTEM_UI_FLAG_HIDE_NAVIGATION");
    const flagFullscreen = try ViewClass.getStaticIntField("SYSTEM_UI_FLAG_FULLSCREEN");
    const flagImmersiveSticky = try ViewClass.getStaticIntField("SYSTEM_UI_FLAG_IMMERSIVE_STICKY");

    // Call the decorView.setSystemUiVisibility(FLAGS)
    try ViewClass.callVoidMethod(decorView, "setSystemUiVisibility", "(I)V", .{
        (flagLayoutHideNavigation | flagLayoutFullscreen | flagLowProfile | flagHideNavigation | flagFullscreen | flagImmersiveSticky),
    });

    // now set some more flags associated with layoutmanager -- note the $ in the
    // class path search for api-versions.xml
    // https://android.googlesource.com/platform/development/+/refs/tags/android-9.0.0_r48/sdk/api-versions.xml
    const LayoutManagerClass = try self.jni.findClass("android/view/WindowManager$LayoutParams");
    const flag_WinMan_Fullscreen = try LayoutManagerClass.getStaticIntField("FLAG_FULLSCREEN");
    const flag_WinMan_KeepScreenOn = try LayoutManagerClass.getStaticIntField("FLAG_KEEP_SCREEN_ON");
    const flag_WinMan_hw_acc = try LayoutManagerClass.getStaticIntField("FLAG_HARDWARE_ACCELERATED");

    //    const int flag_WinMan_flag_not_fullscreen =
    //    env.GetStaticIntField(layoutManagerClass,
    //    (env.GetStaticFieldID(layoutManagerClass, "FLAG_FORCE_NOT_FULLSCREEN",
    //    "I") ));
    // call window.addFlags(FLAGS)

    try WindowClass.callVoidMethod(window, "addFlags", "(I)V", .{(flag_WinMan_Fullscreen | flag_WinMan_KeepScreenOn | flag_WinMan_hw_acc)});
}

pub fn AndroidDisplayKeyboard(self: *Self, show: bool) !bool {
    // Based on
    // https://stackoverflow.com/questions/5864790/how-to-show-the-soft-keyboard-on-native-activity
    var lFlags: android.jint = 0;

    // Retrieves Context.INPUT_METHOD_SERVICE.
    const ClassContext = try self.jni.findClass("android/content/Context");
    const INPUT_METHOD_SERVICE = try ClassContext.getStaticObjectField("INPUT_METHOD_SERVICE", "Ljava/lang/String;");

    // Runs getSystemService(Context.INPUT_METHOD_SERVICE).
    const ClassInputMethodManager = try self.jni.findClass("android/view/inputmethod/InputMethodManager");
    const lInputMethodManager = try ClassInputMethodManager.callObjectMethod(self.activity.clazz, "getSystemService", "(Ljava/lang/String;)Ljava/lang/Object;", .{INPUT_METHOD_SERVICE});

    // Runs getWindow().getDecorView().
    const lWindow = try ClassContext.callObjectMethod(self.activity.clazz, "getWindow", "()Landroid/view/Window;", .{});
    const ClassWindow = try self.jni.findClass("android/view/Window");
    const lDecorView = try ClassWindow.callObjectMethod(lWindow, "getDecorView", "()Landroid/view/View;", .{});

    if (show) {
        // Runs lInputMethodManager.showSoftInput(...).
        return ClassInputMethodManager.callBooleanMethod(lInputMethodManager, "showSoftInput", "(Landroid/view/View;I)Z", .{ lDecorView, lFlags });
    } else {
        // Runs lWindow.getViewToken()
        const ClassView = try self.jni.findClass("android/view/View");
        const lBinder = try ClassView.callObjectMethod(lDecorView, "getWindowToken", "()Landroid/os/IBinder;", .{});

        // lInputMethodManager.hideSoftInput(...).
        return ClassInputMethodManager.callBooleanMethod(lInputMethodManager, "hideSoftInputFromWindow", "(Landroid/os/IBinder;I)Z", .{ lBinder, lFlags });
    }
}

/// Move the task containing this activity to the back of the activity stack.
/// The activity's order within the task is unchanged.
/// nonRoot: If false then this only works if the activity is the root of a task; if true it will work for any activity in a task.
/// returns: If the task was moved (or it was already at the back) true is returned, else false.
pub fn AndroidSendToBack(self: *Self, nonRoot: bool) !bool {
    const ClassActivity = try self.jni.findClass("android/app/Activity");
    return ClassActivity.callBooleanMethod(self.activity.clazz, "moveTaskToBack", "(Z)Z", .{if (nonRoot) @as(c_int, 1) else 0});
}

pub fn AndroidHasPermissions(self: *Self, perm_name: [:0]const u8) !bool {
    if (android.sdk_version < 23) {
        log.err(
            "Android SDK version {} does not support AndroidRequestAppPermissions\n",
            .{android.sdk_version},
        );
        return false;
    }

    const ls_PERM = try self.jni.newString(perm_name);

    const PERMISSION_GRANTED = blk: {
        var ClassPackageManager = try self.jni.findClass("android/content/pm/PackageManager");
        break :blk try ClassPackageManager.getStaticIntField("PERMISSION_GRANTED");
    };

    const ClassContext = try self.jni.findClass("android/content/Context");
    const int_result = try ClassContext.callIntMethod(self.activity.clazz, "checkSelfPermission", "(Ljava/lang/String;)I", .{ls_PERM});
    return (int_result == PERMISSION_GRANTED);
}

pub fn AndroidRequestAppPermissions(self: *Self, perm_name: [:0]const u8) !void {
    if (android.sdk_version < 23) {
        log.err(
            "Android SDK version {} does not support AndroidRequestAppPermissions\n",
            .{android.sdk_version},
        );
        return;
    }

    const perm_array = try self.jni.invokeJni(.NewObjectArray, .{
        1,
        try self.jni.invokeJni(.FindClass, .{"java/lang/String"}),
        try self.jni.newString(perm_name),
    });

    // Last arg (0) is just for the callback (that I do not use)
    try self.activity_class.callVoidMethod(self.activity.clazz, "requestPermissions", "([Ljava/lang/String;I)V", .{ perm_array, @as(c_int, 0) });
}

pub fn getFilesDir(self: *Self, allocator: std.mem.Allocator) ![:0]const u8 {
    const files_dir = try self.activity_class.callVoidMethod(self.activity.clazz, "getFilesDir", "()Ljava/io/File;", .{});

    const FileClass = try self.jni.findClass("java/io/File");

    const path_string = try FileClass.callObjectMethod(files_dir, "getPath", "()Ljava/lang/String;", .{});

    const utf8_or_null = try self.jni.invokeJni(.GetStringUTFChars, .{ path_string, null });

    if (utf8_or_null) |utf8_ptr| {
        defer self.jni.invokeJniNoException(.ReleaseStringUTFChars, .{ path_string, utf8_ptr });

        const utf8 = std.mem.sliceTo(utf8_ptr, 0);

        return try allocator.dupeZ(u8, utf8);
    } else {
        return error.OutOfMemory;
    }
}

comptime {
    _ = AndroidGetUnicodeChar;
    _ = AndroidMakeFullscreen;
    _ = AndroidDisplayKeyboard;
    _ = AndroidSendToBack;
    _ = AndroidHasPermissions;
    _ = AndroidRequestAppPermissions;
}
