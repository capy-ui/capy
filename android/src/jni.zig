const std = @import("std");
const log = std.log.scoped(.jni);
const android = @import("android-support.zig");

/// Wraps JNIEnv to provide a better Zig API.
/// *android.JNIEnv can be directly cast to `*JNI`. For example:
/// ```
/// const jni = @ptrCast(*JNI, jni_env);
/// ```
pub const JNI = opaque {
    // Underlying implementation
    fn JniReturnType(comptime function: @TypeOf(.literal)) type {
        @setEvalBranchQuota(10_000);
        return @typeInfo(@typeInfo(std.meta.fieldInfo(android.JNINativeInterface, function).type).Pointer.child).Fn.return_type.?;
    }

    pub inline fn invokeJniNoException(jni: *JNI, comptime function: @TypeOf(.literal), args: anytype) JniReturnType(function) {
        const env = @ptrCast(*android.JNIEnv, @alignCast(@alignOf(*android.JNIEnv), jni));
        return @call(
            .auto,
            @field(env.*, @tagName(function)),
            .{env} ++ args,
        );
    }

    /// Possible JNI Errors
    const Error = error{
        ExceptionThrown,
        ClassNotDefined,
    };

    pub inline fn invokeJni(jni: *JNI, comptime function: @TypeOf(.literal), args: anytype) Error!JniReturnType(function) {
        const value = jni.invokeJniNoException(function, args);
        if (jni.invokeJniNoException(.ExceptionCheck, .{}) == android.JNI_TRUE) {
            log.err("Encountered exception while calling: {s} {any}", .{ @tagName(function), args });
            inline for (args) |arg, i| {
                if (comptime std.meta.trait.isZigString(@TypeOf(arg))) {
                    log.err("Arg {d}: {s}", .{ i, arg });
                }
            }
            //return Error.ExceptionThrown;
        }
        return value;
    }

    // Convenience functions

    pub fn findClass(jni: *JNI, class: [:0]const u8) Error!Class {
        return Class.init(jni, class);
    }

    pub fn getClassNameString(jni: *JNI, object: android.jobject) Error!String {
        const object_class = try jni.invokeJni(.GetObjectClass, .{object});
        const ClassClass = try jni.findClass("java/lang/Class");
        const getName = try jni.invokeJni(.GetMethodID, .{ ClassClass, "getName", "()Ljava/lang/String;" });
        const name = try jni.invokeJni(.CallObjectMethod, .{ object_class, getName });
        return String.init(jni, name);
    }

    pub fn printToString(jni: *JNI, object: android.jobject) void {
        const string = try String.init(jni, try jni.callObjectMethod(object, "toString", "()Ljava/lang/String;", .{}));
        defer string.deinit(jni);
        log.info("{any}: {}", .{ object, std.unicode.fmtUtf16le(string.slice) });
    }

    pub fn newString(jni: *JNI, string: [*:0]const u8) Error!android.jstring {
        return jni.invokeJni(.NewStringUTF, .{string});
    }

    pub fn getLongField(jni: *JNI, object: android.jobject, field_id: android.jfieldID) !android.jlong {
        return jni.invokeJni(.GetLongField, .{ object, field_id });
    }

    pub inline fn callObjectMethod(jni: *JNI, object: android.jobject, name: [:0]const u8, signature: [:0]const u8, args: anytype) Error!JniReturnType(.CallObjectMethod) {
        const object_class = try jni.invokeJni(.GetObjectClass, .{object});
        const method_id = try jni.invokeJni(.GetMethodID, .{ object_class, name, signature });
        return jni.invokeJni(.CallObjectMethod, .{ object, method_id } ++ args);
    }

    pub const Class = struct {
        jni: *JNI,
        class: android.jclass,

        pub fn init(jni: *JNI, class_name: [:0]const u8) !Class {
            const class = jni.invokeJni(.FindClass, .{class_name.ptr}) catch {
                log.err("Class Not Found: {s}", .{class_name});
                return Error.ClassNotDefined;
            };
            return Class{
                .jni = jni,
                .class = class,
            };
        }

        pub inline fn newObject(class: Class, signature: [:0]const u8, args: anytype) Error!JniReturnType(.NewObject) {
            const method_id = try class.jni.invokeJni(.GetMethodID, .{ class.class, "<init>", signature });
            var values: [args.len]android.jvalue = undefined;
            // TODO: switch all methods to their A variant
            inline for (args) |arg, i| {
                var value: android.jvalue = undefined;
                switch (@TypeOf(arg)) {
                    android.jint, u32, c_int => value = .{ .i = @bitCast(i32, arg) },
                    android.jlong, usize => value = .{ .j = @bitCast(i64, arg) },
                    android.jfloat => value = .{ .f = arg },
                    android.jobject => value = .{ .l = arg },
                    else => @compileError("unsupported jni type: " ++ @typeName(@TypeOf(arg))),
                }
                values[i] = value;
            }

            return try class.jni.invokeJni(.NewObjectA, .{ class.class, method_id, &values });
        }

        pub inline fn getStaticIntField(class: Class, name: [:0]const u8) !android.jint {
            const field_id = try class.jni.invokeJni(.GetStaticFieldID, .{ class.class, name, "I" });
            return try class.jni.invokeJni(.GetStaticIntField, .{ class.class, field_id });
        }

        pub inline fn getStaticObjectField(class: Class, name: [:0]const u8, signature: [:0]const u8) !android.jobject {
            const field_id = try class.jni.invokeJni(.GetStaticFieldID, .{ class.class, name, signature });
            return try class.jni.invokeJni(.GetStaticObjectField, .{ class.class, field_id });
        }

        pub inline fn setIntField(class: Class, object: android.jobject, name: [:0]const u8, signature: [:0]const u8, value: android.jint) !void {
            const field_id = try class.jni.invokeJni(.GetFieldID, .{ class.class, name, signature });
            try class.jni.invokeJni(.SetIntField, .{ object, field_id, value });
        }

        pub inline fn callVoidMethod(class: Class, object: android.jobject, name: [:0]const u8, signature: [:0]const u8, args: anytype) Error!void {
            const method_id = try class.jni.invokeJni(.GetMethodID, .{ class.class, name, signature });
            try class.jni.invokeJni(.CallVoidMethod, .{ object, method_id } ++ args);
        }

        pub inline fn callIntMethod(class: Class, object: android.jobject, name: [:0]const u8, signature: [:0]const u8, args: anytype) Error!android.jint {
            const method_id = try class.jni.invokeJni(.GetMethodID, .{ class.class, name, signature });
            return try class.jni.invokeJni(.CallIntMethod, .{ object, method_id } ++ args);
        }

        pub inline fn callFloatMethod(class: Class, object: android.jobject, name: [:0]const u8, signature: [:0]const u8, args: anytype) Error!android.jfloat {
            const method_id = try class.jni.invokeJni(.GetMethodID, .{ class.class, name, signature });
            return try class.jni.invokeJni(.CallFloatMethod, .{ object, method_id } ++ args);
        }

        pub inline fn callLongMethod(class: Class, object: android.jobject, name: [:0]const u8, signature: [:0]const u8, args: anytype) Error!android.jlong {
            const method_id = try class.jni.invokeJni(.GetMethodID, .{ class.class, name, signature });
            return try class.jni.invokeJni(.CallLongMethod, .{ object, method_id } ++ args);
        }

        pub inline fn callBooleanMethod(class: Class, object: android.jobject, name: [:0]const u8, signature: [:0]const u8, args: anytype) Error!bool {
            const method_id = try class.jni.invokeJni(.GetMethodID, .{ class.class, name, signature });
            return try class.jni.invokeJni(.CallBooleanMethod, .{ object, method_id } ++ args) == android.JNI_TRUE;
        }

        pub inline fn callObjectMethod(class: Class, object: android.jobject, name: [:0]const u8, signature: [:0]const u8, args: anytype) Error!android.jobject {
            const method_id = try class.jni.invokeJni(.GetMethodID, .{ class.class, name, signature });
            return class.jni.invokeJni(.CallObjectMethod, .{ object, method_id } ++ args);
        }

        pub inline fn callStaticObjectMethod(class: Class, name: [:0]const u8, signature: [:0]const u8, args: anytype) Error!android.jobject {
            const method_id = try class.jni.invokeJni(.GetStaticMethodID, .{ class.class, name, signature });
            return try class.jni.invokeJni(.CallStaticObjectMethod, .{ class.class, method_id } ++ args);
        }
    };

    pub const String = struct {
        jstring: android.jstring,
        slice: []const u16,

        pub fn init(jni: *JNI, string: android.jstring) Error!String {
            const len = try jni.invokeJni(.GetStringLength, .{string});
            const ptr = try jni.invokeJni(.GetStringChars, .{ string, null });
            const slice = ptr[0..@intCast(usize, len)];
            return String{
                .jstring = string,
                .slice = slice,
            };
        }

        pub fn deinit(string: String, jni: *JNI) void {
            jni.invokeJniNoException(.ReleaseStringChars, .{ string.jstring, string.slice.ptr });
        }
    };
};
