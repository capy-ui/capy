const std = @import("std");
const builtin = @import("builtin");

const c = @import("c.zig");

const android = @import("android-bind.zig");
const build_options = @import("build_options");

pub const egl = @import("egl.zig");
pub const JNI = @import("jni.zig").JNI;
pub const audio = @import("audio.zig");

const app_log = std.log.scoped(.app_glue);

// Export the flat functions for now
// pub const native = android;
pub usingnamespace android;

const AndroidApp = @import("root").AndroidApp;

pub var sdk_version: c_int = 0;

/// Actual application entry point
pub export fn ANativeActivity_onCreate(activity: *android.ANativeActivity, savedState: ?[*]u8, savedStateSize: usize) callconv(.C) void {
    {
        var sdk_ver_str: [92]u8 = undefined;
        const len = android.__system_property_get("ro.build.version.sdk", &sdk_ver_str);
        if (len <= 0) {
            sdk_version = 0;
        } else {
            const str = sdk_ver_str[0..@intCast(usize, len)];
            sdk_version = std.fmt.parseInt(c_int, str, 10) catch 0;
        }
    }

    app_log.debug(
        \\Zig Android SDK:
        \\  App:              {s}
        \\  API level:        target={d}, actual={d}
        \\  App pid:          {}
        \\  Build mode:       {s}
        \\  ABI:              {s}-{s}-{s}
        \\  Compiler version: {}
        \\  Compiler backend: {s}
    , .{
        build_options.app_name,
        build_options.android_sdk_version,
        sdk_version,
        std.os.linux.getpid(),
        @tagName(builtin.mode),
        @tagName(builtin.cpu.arch),
        @tagName(builtin.os.tag),
        @tagName(builtin.abi),
        builtin.zig_version,
        @tagName(builtin.zig_backend),
    });

    const app = std.heap.c_allocator.create(AndroidApp) catch {
        app_log.err("Could not create new AndroidApp: OutOfMemory!\n", .{});
        return;
    };

    activity.callbacks.* = makeNativeActivityGlue(AndroidApp);

    app.* = AndroidApp.init(
        std.heap.c_allocator,
        activity,
        if (savedState) |state|
            state[0..savedStateSize]
        else
            null,
    ) catch |err| {
        std.err("Failed to restore app state: {}\n", .{err});
        std.heap.c_allocator.destroy(app);
        return;
    };

    app.start() catch |err| {
        std.log.err("Failed to start app state: {}\n", .{err});
        app.deinit();
        std.heap.c_allocator.destroy(app);
        return;
    };

    activity.instance = app;

    app_log.debug("Successfully started the app.\n", .{});
}

// // Required by C code for now…
threadlocal var errno: c_int = 0;
export fn __errno_location() *c_int {
    return &errno;
}

var recursive_panic = false;

// Android Panic implementation
pub fn panic(message: []const u8, stack_trace: ?*std.builtin.StackTrace, _: ?usize) noreturn {
    var logger = LogWriter{ .log_level = android.ANDROID_LOG_ERROR };

    if (@atomicLoad(bool, &recursive_panic, .SeqCst)) {
        logger.writer().print("RECURSIVE PANIC: {s}\n", .{message}) catch {};
        while (true) {
            std.time.sleep(std.time.ns_per_week);
        }
    }

    @atomicStore(bool, &recursive_panic, true, .SeqCst);

    logger.writer().print("PANIC: {s}\n", .{message}) catch {};

    const maybe_debug_info = std.debug.getSelfDebugInfo() catch null;

    //    dumpStackTrace(maybe_debug_info);

    {
        var count: usize = 0;
        var it = std.debug.StackIterator.init(null, null);
        while (it.next()) |return_address| {
            printSymbolInfoAt(count, maybe_debug_info, return_address);
            count += 1;
        }
    }

    _ = stack_trace;
    // if (stack_trace) |st| {
    //     logger.writer().print("{}\n", .{st}) catch {};
    // }

    // if (std.debug.getSelfDebugInfo()) |debug_info| {
    // std.debug.writeCurrentStackTrace(logger.writer(), debug_info, .no_color, null) catch |err| {
    //     logger.writer().print("failed to write stack trace: {s}\n", .{err}) catch {};
    // };
    // } else |err| {
    //     logger.writer().print("failed to get debug info: {s}\n", .{err}) catch {};
    // }

    logger.writer().writeAll("<-- end of stack trace -->\n") catch {};

    std.os.exit(1);
}

const LogWriter = struct {
    log_level: c_int,

    line_buffer: [8192]u8 = undefined,
    line_len: usize = 0,

    const Error = error{};
    const Writer = std.io.Writer(*LogWriter, Error, write);

    fn write(self: *LogWriter, buffer: []const u8) Error!usize {
        for (buffer) |char| {
            switch (char) {
                '\n' => {
                    self.flush();
                },
                else => {
                    if (self.line_len >= self.line_buffer.len - 1) {
                        self.flush();
                    }
                    self.line_buffer[self.line_len] = char;
                    self.line_len += 1;
                },
            }
        }
        return buffer.len;
    }

    fn flush(self: *LogWriter) void {
        if (self.line_len > 0) {
            // var buf = std.mem.zeroes([129]u8);
            // const msg = std.fmt.bufPrint(&buf, "PRINT({})\x00", .{self.line_len}) catch "PRINT(???)";
            // _ = android.__android_log_write(
            //     self.log_level,
            //     build_options.app_name.ptr,
            //     msg.ptr,
            // );

            std.debug.assert(self.line_len < self.line_buffer.len - 1);
            self.line_buffer[self.line_len] = 0;
            _ = android.__android_log_write(
                self.log_level,
                build_options.app_name.ptr,
                &self.line_buffer,
            );
        }
        self.line_len = 0;
    }

    fn writer(self: *LogWriter) Writer {
        return Writer{ .context = self };
    }
};

// Android Logging implementation
pub fn log(
    comptime message_level: std.log.Level,
    comptime scope: @Type(.EnumLiteral),
    comptime format: []const u8,
    args: anytype,
) void {
    const level = switch (message_level) {
        //  => .ANDROID_LOG_VERBOSE,
        .debug => android.ANDROID_LOG_DEBUG,
        .info => android.ANDROID_LOG_INFO,
        .warn => android.ANDROID_LOG_WARN,
        .err => android.ANDROID_LOG_ERROR,
    };

    var logger = LogWriter{
        .log_level = level,
    };
    defer logger.flush();

    logger.writer().print("{s}: " ++ format, .{@tagName(scope)} ++ args) catch {};
}

/// Returns a wrapper implementation for the given App type which implements all
/// ANativeActivity callbacks.
fn makeNativeActivityGlue(comptime App: type) android.ANativeActivityCallbacks {
    const T = struct {
        fn invoke(activity: *android.ANativeActivity, comptime func: []const u8, args: anytype) void {
            if (@hasDecl(App, func)) {
                if (activity.instance) |instance| {
                    const result = @call(.{}, @field(App, func), .{@ptrCast(*App, @alignCast(@alignOf(App), instance))} ++ args);
                    switch (@typeInfo(@TypeOf(result))) {
                        .ErrorUnion => result catch |err| app_log.err("{s} returned error {s}", .{ func, @errorName(err) }),
                        .Void => {},
                        .ErrorSet => app_log.err("{s} returned error {s}", .{ func, @errorName(result) }),
                        else => @compileError("callback must return void!"),
                    }
                }
            } else {
                app_log.debug("ANativeActivity callback {s} not available on {s}", .{ func, @typeName(App) });
            }
        }

        // return value must be created with malloc(), so we pass the c_allocator to App.onSaveInstanceState
        fn onSaveInstanceState(activity: *android.ANativeActivity, outSize: *usize) callconv(.C) ?[*]u8 {
            outSize.* = 0;
            if (@hasDecl(App, "onSaveInstanceState")) {
                if (activity.instance) |instance| {
                    const optional_slice = @ptrCast(*App, @alignCast(@alignOf(App), instance)).onSaveInstanceState(std.heap.c_allocator);
                    if (optional_slice) |slice| {
                        outSize.* = slice.len;
                        return slice.ptr;
                    }
                }
            } else {
                app_log.debug("ANativeActivity callback onSaveInstanceState not available on {s}", .{@typeName(App)});
            }
            return null;
        }

        fn onDestroy(activity: *android.ANativeActivity) callconv(.C) void {
            if (activity.instance) |instance| {
                const app = @ptrCast(*App, @alignCast(@alignOf(App), instance));
                app.deinit();
                std.heap.c_allocator.destroy(app);
            }
        }
        fn onStart(activity: *android.ANativeActivity) callconv(.C) void {
            invoke(activity, "onStart", .{});
        }
        fn onResume(activity: *android.ANativeActivity) callconv(.C) void {
            invoke(activity, "onResume", .{});
        }
        fn onPause(activity: *android.ANativeActivity) callconv(.C) void {
            invoke(activity, "onPause", .{});
        }
        fn onStop(activity: *android.ANativeActivity) callconv(.C) void {
            invoke(activity, "onStop", .{});
        }
        fn onConfigurationChanged(activity: *android.ANativeActivity) callconv(.C) void {
            invoke(activity, "onConfigurationChanged", .{});
        }
        fn onLowMemory(activity: *android.ANativeActivity) callconv(.C) void {
            invoke(activity, "onLowMemory", .{});
        }
        fn onWindowFocusChanged(activity: *android.ANativeActivity, hasFocus: c_int) callconv(.C) void {
            invoke(activity, "onWindowFocusChanged", .{(hasFocus != 0)});
        }
        fn onNativeWindowCreated(activity: *android.ANativeActivity, window: *android.ANativeWindow) callconv(.C) void {
            invoke(activity, "onNativeWindowCreated", .{window});
        }
        fn onNativeWindowResized(activity: *android.ANativeActivity, window: *android.ANativeWindow) callconv(.C) void {
            invoke(activity, "onNativeWindowResized", .{window});
        }
        fn onNativeWindowRedrawNeeded(activity: *android.ANativeActivity, window: *android.ANativeWindow) callconv(.C) void {
            invoke(activity, "onNativeWindowRedrawNeeded", .{window});
        }
        fn onNativeWindowDestroyed(activity: *android.ANativeActivity, window: *android.ANativeWindow) callconv(.C) void {
            invoke(activity, "onNativeWindowDestroyed", .{window});
        }
        fn onInputQueueCreated(activity: *android.ANativeActivity, input_queue: *android.AInputQueue) callconv(.C) void {
            invoke(activity, "onInputQueueCreated", .{input_queue});
        }
        fn onInputQueueDestroyed(activity: *android.ANativeActivity, input_queue: *android.AInputQueue) callconv(.C) void {
            invoke(activity, "onInputQueueDestroyed", .{input_queue});
        }
        fn onContentRectChanged(activity: *android.ANativeActivity, rect: *const android.ARect) callconv(.C) void {
            invoke(activity, "onContentRectChanged", .{rect});
        }
    };
    return android.ANativeActivityCallbacks{
        .onStart = T.onStart,
        .onResume = T.onResume,
        .onSaveInstanceState = T.onSaveInstanceState,
        .onPause = T.onPause,
        .onStop = T.onStop,
        .onDestroy = T.onDestroy,
        .onWindowFocusChanged = T.onWindowFocusChanged,
        .onNativeWindowCreated = T.onNativeWindowCreated,
        .onNativeWindowResized = T.onNativeWindowResized,
        .onNativeWindowRedrawNeeded = T.onNativeWindowRedrawNeeded,
        .onNativeWindowDestroyed = T.onNativeWindowDestroyed,
        .onInputQueueCreated = T.onInputQueueCreated,
        .onInputQueueDestroyed = T.onInputQueueDestroyed,
        .onContentRectChanged = T.onContentRectChanged,
        .onConfigurationChanged = T.onConfigurationChanged,
        .onLowMemory = T.onLowMemory,
    };
}

inline fn printSymbolInfoAt(st_index: usize, maybe_debug_info: ?*std.debug.DebugInfo, int_addr: usize) void {
    var symbol_name_buffer: [1024]u8 = undefined;
    var symbol_name: ?[]const u8 = null;

    if (maybe_debug_info) |di| {
        if (di.getModuleForAddress(int_addr)) |module| {
            var symbol_buffer: [1024]u8 = undefined;
            var fba = std.heap.FixedBufferAllocator.init(&symbol_buffer);

            if (module.getSymbolAtAddress(fba.allocator(), int_addr)) |symbol| {

                // symbol_name_buffer

                symbol_name = std.fmt.bufPrint(
                    &symbol_name_buffer,
                    "{s} {s} {s}",
                    .{
                        symbol.symbol_name,
                        symbol.compile_unit_name,
                        fmtMaybeLineInfo(symbol.line_info),
                    },
                ) catch symbol_name;
            } else |_| {}
        } else |_| {}
    }

    std.log.info("#{d:0>2}: 0x{X:0>8} {?s}", .{
        st_index,
        int_addr,
        symbol_name,
    });
}

fn realFmtMaybeLineInfo(self: ?std.debug.LineInfo, comptime fmt: []const u8, options: std.fmt.FormatOptions, writer: anytype) !void {
    _ = fmt;
    _ = options;
    if (self) |li| {
        try writer.print("{s}:{d}:{d}", .{
            li.file_name,
            li.line,
            li.column,
        });
    } else {
        try writer.writeAll("<no line info>");
    }
}

fn fmtMaybeLineInfo(li: ?std.debug.LineInfo) std.fmt.Formatter(realFmtMaybeLineInfo) {
    return std.fmt.Formatter(realFmtMaybeLineInfo){
        .data = li,
    };
}
