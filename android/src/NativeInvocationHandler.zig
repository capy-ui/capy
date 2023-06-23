const std = @import("std");
const android = @import("android-support.zig");
const Self = @This();

class: android.jobject,
initFn: android.jmethodID,

pub fn init(jni: *android.JNI, class: android.jobject) !Self {
    const methods = [_]android.JNINativeMethod{
        .{
            .name = "invoke0",
            .signature = "(Ljava/lang/Object;Ljava/lang/reflect/Method;[Ljava/lang/Object;)Ljava/lang/Object;",
            .fnPtr = InvocationHandler.invoke0,
        },
    };
    _ = try jni.invokeJni(.RegisterNatives, .{ class, &methods, methods.len });
    return Self{
        .class = class,
        .initFn = try jni.invokeJni(.GetMethodID, .{ class, "<init>", "(J)V" }),
    };
}

pub fn createAlloc(self: Self, jni: *android.JNI, alloc: std.mem.Allocator, pointer: ?*anyopaque, function: InvokeFn) !android.jobject {
    // Create a InvocationHandler struct
    var handler = try alloc.create(InvocationHandler);
    errdefer alloc.destroy(handler);
    handler.* = .{
        .pointer = pointer,
        .function = function,
    };

    const handler_value = @intFromPtr(handler);
    std.debug.assert(handler_value <= 0x7fffffffffffffff);

    // Call handler constructor
    const result = try jni.invokeJni(.NewObject, .{ self.class, self.initFn, handler_value }) orelse return error.InvocationHandlerInitError;
    return result;

    // return handler;
}

/// Function signature for invoke functions
pub const InvokeFn = *const fn (?*anyopaque, *android.JNI, android.jobject, android.jobjectArray) anyerror!android.jobject;

/// InvocationHandler Technique found here https://groups.google.com/g/android-ndk/c/SRgy93Un8vM
const InvocationHandler = struct {
    pointer: ?*anyopaque,
    function: InvokeFn,

    /// Called by java class NativeInvocationHandler
    pub fn invoke0(jni: *android.JNI, this: android.jobject, proxy: android.jobject, method: android.jobject, args: android.jobjectArray) android.jobject {
        return invoke_impl(jni, this, proxy, method, args) catch |e| switch (e) {
            else => @panic(@errorName(e)),
        };
    }

    fn invoke_impl(jni: *android.JNI, this: android.jobject, proxy: android.jobject, method: android.jobject, args: android.jobjectArray) anyerror!android.jobject {
        _ = proxy; // This is the proxy object. Calling anything on it will cause invoke to be called. If this isn't explicitly handled, it will recurse infinitely
        const Class = try jni.invokeJni(.GetObjectClass, .{this});
        const ptrField = try jni.invokeJni(.GetFieldID, .{ Class, "ptr", "J" });
        const jptr = try jni.getLongField(this, ptrField);
        const h = @ptrFromInt(*InvocationHandler, @intCast(usize, jptr));
        return h.function(h.pointer, jni, method, args);
    }
};
