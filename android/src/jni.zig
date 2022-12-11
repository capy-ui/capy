const std = @import("std");
const log = std.log.scoped(.jni);
const android = @import("android-support.zig");

pub const JNI = struct {
    const Self = @This();

    activity: *android.ANativeActivity,
    env: *android.JNIEnv,
    activity_class: android.jclass,

    pub fn init(activity: *android.ANativeActivity) Self {
        var env: *android.JNIEnv = undefined;
        _ = activity.vm.*.AttachCurrentThread(activity.vm, &env, null);
        return fromJniEnv(activity, env);
    }

    pub fn get(activity: *android.ANativeActivity) Self {
        var env: *android.JNIEnv = undefined;
        _ = activity.vm.*.GetEnv(activity.vm, @ptrCast(*?*anyopaque, &env), android.JNI_VERSION_1_6);
        return fromJniEnv(activity, env);
    }

    fn fromJniEnv(activity: *android.ANativeActivity, env: *android.JNIEnv) Self {
        var activityClass = env.*.FindClass(env, "android/app/NativeActivity");

        return Self{
            .activity = activity,
            .env = env,
            .activity_class = activityClass,
        };
    }

    pub fn deinit(self: *Self) void {
        _ = self.activity.vm.*.DetachCurrentThread(self.activity.vm);
        self.* = undefined;
    }

    fn JniReturnType(comptime function: @TypeOf(.literal)) type {
        @setEvalBranchQuota(10_000);
        return @typeInfo(@typeInfo(std.meta.fieldInfo(android.JNINativeInterface, function).field_type).Pointer.child).Fn.return_type.?;
    }

    pub inline fn invokeJni(self: Self, comptime function: @TypeOf(.literal), args: anytype) JniReturnType(function) {
        return @call(
            .{},
            @field(self.env.*, @tagName(function)),
            .{self.env} ++ args,
        );
    }

    pub fn findClass(self: Self, class: [:0]const u8) android.jclass {
        return self.invokeJni(.FindClass, .{class.ptr});
    }

    pub fn newString(self: Self, string: [*:0]const u8) android.jstring {
        return self.invokeJni(.NewStringUTF, .{ string });
    }

    pub fn AndroidGetUnicodeChar(self: *Self, keyCode: c_int, metaState: c_int) u21 {
        // https://stackoverflow.com/questions/21124051/receive-complete-android-unicode-input-in-c-c/43871301
        const eventType = android.AKEY_EVENT_ACTION_DOWN;

        const class_key_event = self.findClass("android/view/KeyEvent");

        const method_get_unicode_char = self.invokeJni(.GetMethodID, .{ class_key_event, "getUnicodeChar", "(I)I" });
        const eventConstructor = self.invokeJni(.GetMethodID, .{ class_key_event, "<init>", "(II)V" });
        const eventObj = self.invokeJni(.NewObject, .{ class_key_event, eventConstructor, eventType, keyCode });

        const unicodeKey = self.invokeJni(.CallIntMethod, .{ eventObj, method_get_unicode_char, metaState });

        return @intCast(u21, unicodeKey);
    }

    pub fn AndroidMakeFullscreen(self: *Self) void {
        // Partially based on
        // https://stackoverflow.com/questions/47507714/how-do-i-enable-full-screen-immersive-mode-for-a-native-activity-ndk-app

        // Get android.app.NativeActivity, then get getWindow method handle, returns
        // view.Window type
        const activityClass = self.findClass("android/app/NativeActivity");
        const getWindow = self.invokeJni(.GetMethodID, .{ activityClass, "getWindow", "()Landroid/view/Window;" });
        const window = self.invokeJni(.CallObjectMethod, .{ self.activity.clazz, getWindow });

        // Get android.view.Window class, then get getDecorView method handle, returns
        // view.View type
        const windowClass = self.findClass("android/view/Window");
        const getDecorView = self.invokeJni(.GetMethodID, .{ windowClass, "getDecorView", "()Landroid/view/View;" });
        const decorView = self.invokeJni(.CallObjectMethod, .{ window, getDecorView });

        // Get the flag values associated with systemuivisibility
        const viewClass = self.findClass("android/view/View");
        const flagLayoutHideNavigation = self.invokeJni(.GetStaticIntField, .{ viewClass, self.invokeJni(.GetStaticFieldID, .{ viewClass, "SYSTEM_UI_FLAG_LAYOUT_HIDE_NAVIGATION", "I" }) });
        const flagLayoutFullscreen = self.invokeJni(.GetStaticIntField, .{ viewClass, self.invokeJni(.GetStaticFieldID, .{ viewClass, "SYSTEM_UI_FLAG_LAYOUT_FULLSCREEN", "I" }) });
        const flagLowProfile = self.invokeJni(.GetStaticIntField, .{ viewClass, self.invokeJni(.GetStaticFieldID, .{ viewClass, "SYSTEM_UI_FLAG_LOW_PROFILE", "I" }) });
        const flagHideNavigation = self.invokeJni(.GetStaticIntField, .{ viewClass, self.invokeJni(.GetStaticFieldID, .{ viewClass, "SYSTEM_UI_FLAG_HIDE_NAVIGATION", "I" }) });
        const flagFullscreen = self.invokeJni(.GetStaticIntField, .{ viewClass, self.invokeJni(.GetStaticFieldID, .{ viewClass, "SYSTEM_UI_FLAG_FULLSCREEN", "I" }) });
        const flagImmersiveSticky = self.invokeJni(.GetStaticIntField, .{ viewClass, self.invokeJni(.GetStaticFieldID, .{ viewClass, "SYSTEM_UI_FLAG_IMMERSIVE_STICKY", "I" }) });

        const setSystemUiVisibility = self.invokeJni(.GetMethodID, .{ viewClass, "setSystemUiVisibility", "(I)V" });

        // Call the decorView.setSystemUiVisibility(FLAGS)
        self.invokeJni(.CallVoidMethod, .{
            decorView,
            setSystemUiVisibility,
            (flagLayoutHideNavigation | flagLayoutFullscreen | flagLowProfile | flagHideNavigation | flagFullscreen | flagImmersiveSticky),
        });

        // now set some more flags associated with layoutmanager -- note the $ in the
        // class path search for api-versions.xml
        // https://android.googlesource.com/platform/development/+/refs/tags/android-9.0.0_r48/sdk/api-versions.xml

        const layoutManagerClass = self.findClass("android/view/WindowManager$LayoutParams");
        const flag_WinMan_Fullscreen = self.invokeJni(.GetStaticIntField, .{ layoutManagerClass, self.invokeJni(.GetStaticFieldID, .{ layoutManagerClass, "FLAG_FULLSCREEN", "I" }) });
        const flag_WinMan_KeepScreenOn = self.invokeJni(.GetStaticIntField, .{ layoutManagerClass, self.invokeJni(.GetStaticFieldID, .{ layoutManagerClass, "FLAG_KEEP_SCREEN_ON", "I" }) });
        const flag_WinMan_hw_acc = self.invokeJni(.GetStaticIntField, .{ layoutManagerClass, self.invokeJni(.GetStaticFieldID, .{ layoutManagerClass, "FLAG_HARDWARE_ACCELERATED", "I" }) });
        //    const int flag_WinMan_flag_not_fullscreen =
        //    env.GetStaticIntField(layoutManagerClass,
        //    (env.GetStaticFieldID(layoutManagerClass, "FLAG_FORCE_NOT_FULLSCREEN",
        //    "I") ));
        // call window.addFlags(FLAGS)
        self.invokeJni(.CallVoidMethod, .{
            window,
            self.invokeJni(.GetMethodID, .{ windowClass, "addFlags", "(I)V" }),
            (flag_WinMan_Fullscreen | flag_WinMan_KeepScreenOn | flag_WinMan_hw_acc),
        });
    }

    pub fn AndroidDisplayKeyboard(self: *Self, show: bool) bool {
        // Based on
        // https://stackoverflow.com/questions/5864790/how-to-show-the-soft-keyboard-on-native-activity
        var lFlags: android.jint = 0;

        // Retrieves Context.INPUT_METHOD_SERVICE.
        const ClassContext = self.findClass("android/content/Context");
        const FieldINPUT_METHOD_SERVICE = self.invokeJni(.GetStaticFieldID, .{ ClassContext, "INPUT_METHOD_SERVICE", "Ljava/lang/String;" });
        const INPUT_METHOD_SERVICE = self.invokeJni(.GetStaticObjectField, .{ ClassContext, FieldINPUT_METHOD_SERVICE });

        // Runs getSystemService(Context.INPUT_METHOD_SERVICE).
        const ClassInputMethodManager = self.findClass("android/view/inputmethod/InputMethodManager");
        const MethodGetSystemService = self.invokeJni(.GetMethodID, .{ self.activity_class, "getSystemService", "(Ljava/lang/String;)Ljava/lang/Object;" });
        const lInputMethodManager = self.invokeJni(.CallObjectMethod, .{ self.activity.clazz, MethodGetSystemService, INPUT_METHOD_SERVICE });

        // Runs getWindow().getDecorView().
        const MethodGetWindow = self.invokeJni(.GetMethodID, .{ self.activity_class, "getWindow", "()Landroid/view/Window;" });
        const lWindow = self.invokeJni(.CallObjectMethod, .{ self.activity.clazz, MethodGetWindow });
        const ClassWindow = self.findClass("android/view/Window");
        const MethodGetDecorView = self.invokeJni(.GetMethodID, .{ ClassWindow, "getDecorView", "()Landroid/view/View;" });
        const lDecorView = self.invokeJni(.CallObjectMethod, .{ lWindow, MethodGetDecorView });

        if (show) {
            // Runs lInputMethodManager.showSoftInput(...).
            const MethodShowSoftInput = self.invokeJni(.GetMethodID, .{ ClassInputMethodManager, "showSoftInput", "(Landroid/view/View;I)Z" });
            return 0 != self.invokeJni(.CallBooleanMethod, .{ lInputMethodManager, MethodShowSoftInput, lDecorView, lFlags });
        } else {
            // Runs lWindow.getViewToken()
            const ClassView = self.findClass("android/view/View");
            const MethodGetWindowToken = self.invokeJni(.GetMethodID, .{ ClassView, "getWindowToken", "()Landroid/os/IBinder;" });
            const lBinder = self.invokeJni(.CallObjectMethod, .{ lDecorView, MethodGetWindowToken });

            // lInputMethodManager.hideSoftInput(...).
            const MethodHideSoftInput = self.invokeJni(.GetMethodID, .{ ClassInputMethodManager, "hideSoftInputFromWindow", "(Landroid/os/IBinder;I)Z" });
            return 0 != self.invokeJni(.CallBooleanMethod, .{ lInputMethodManager, MethodHideSoftInput, lBinder, lFlags });
        }
    }

    /// Move the task containing this activity to the back of the activity stack.
    /// The activity's order within the task is unchanged.
    /// nonRoot: If false then this only works if the activity is the root of a task; if true it will work for any activity in a task.
    /// returns: If the task was moved (or it was already at the back) true is returned, else false.
    pub fn AndroidSendToBack(self: *Self, nonRoot: bool) bool {
        const ClassActivity = self.findClass("android/app/Activity");
        const MethodmoveTaskToBack = self.invokeJni(.GetMethodID, .{ ClassActivity, "moveTaskToBack", "(Z)Z" });

        return 0 != self.invokeJni(.CallBooleanMethod, .{ self.activity.clazz, MethodmoveTaskToBack, if (nonRoot) @as(c_int, 1) else 0 });
    }

    pub fn AndroidHasPermissions(self: *Self, perm_name: [:0]const u8) bool {
        if (android.sdk_version < 23) {
            log.err(
                "Android SDK version {} does not support AndroidRequestAppPermissions\n",
                .{android.sdk_version},
            );
            return false;
        }

        const ls_PERM = self.invokeJni(.NewStringUTF, .{perm_name});

        const PERMISSION_GRANTED = blk: {
            var ClassPackageManager = self.findClass("android/content/pm/PackageManager");
            var lid_PERMISSION_GRANTED = self.invokeJni(.GetStaticFieldID, .{ ClassPackageManager, "PERMISSION_GRANTED", "I" });
            break :blk self.invokeJni(.GetStaticIntField, .{ ClassPackageManager, lid_PERMISSION_GRANTED });
        };

        const ClassContext = self.findClass("android/content/Context");
        const MethodcheckSelfPermission = self.invokeJni(.GetMethodID, .{ ClassContext, "checkSelfPermission", "(Ljava/lang/String;)I" });
        const int_result = self.invokeJni(.CallIntMethod, .{ self.activity.clazz, MethodcheckSelfPermission, ls_PERM });
        return (int_result == PERMISSION_GRANTED);
    }

    pub fn AndroidRequestAppPermissions(self: *Self, perm_name: [:0]const u8) void {
        if (android.sdk_version < 23) {
            log.err(
                "Android SDK version {} does not support AndroidRequestAppPermissions\n",
                .{android.sdk_version},
            );
            return;
        }

        const perm_array = self.invokeJni(.NewObjectArray, .{
            1,
            self.findClass("java/lang/String"),
            self.invokeJni(.NewStringUTF, .{perm_name}),
        });

        const MethodrequestPermissions = self.invokeJni(.GetMethodID, .{ self.activity_class, "requestPermissions", "([Ljava/lang/String;I)V" });

        // Last arg (0) is just for the callback (that I do not use)
        self.invokeJni(.CallVoidMethod, .{ self.activity.clazz, MethodrequestPermissions, perm_array, @as(c_int, 0) });
    }

    pub fn getFilesDir(self: *Self, allocator: std.mem.Allocator) ![:0]const u8 {
        const getFilesDirMethod = self.invokeJni(.GetMethodID, .{ self.activity_class, "getFilesDir", "()Ljava/io/File;" });

        const files_dir = self.env.*.CallObjectMethod(self.env, self.activity.clazz, getFilesDirMethod);

        const fileClass = self.findClass("java/io/File");

        const getPathMethod = self.invokeJni(.GetMethodID, .{ fileClass, "getPath", "()Ljava/lang/String;" });

        const path_string = self.env.*.CallObjectMethod(self.env, files_dir, getPathMethod);

        const utf8_or_null = self.invokeJni(.GetStringUTFChars, .{ path_string, null });

        if (utf8_or_null) |utf8_ptr| {
            defer self.invokeJni(.ReleaseStringUTFChars, .{ path_string, utf8_ptr });

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
};
