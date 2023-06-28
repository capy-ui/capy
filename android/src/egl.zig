const std = @import("std");
const log = std.log.scoped(.egl);

pub const c = @import("c.zig");

const android = @import("android-support.zig");

pub const Version = enum {
    gles2,
    gles3,
};

pub const EGLContext = struct {
    const Self = @This();

    display: c.EGLDisplay,
    surface: c.EGLSurface,
    context: c.EGLContext,

    pub fn init(window: *android.ANativeWindow, version: Version) !Self {
        const EGLint = c.EGLint;

        var egl_display = c.eglGetDisplay(null);
        if (egl_display == null) {
            log.err("Error: No display found!\n", .{});
            return error.FailedToInitializeEGL;
        }

        var egl_major: EGLint = undefined;
        var egl_minor: EGLint = undefined;
        if (c.eglInitialize(egl_display, &egl_major, &egl_minor) == 0) {
            log.err("Error: eglInitialise failed!\n", .{});
            return error.FailedToInitializeEGL;
        }

        log.info(
            \\EGL Version:    {s}
            \\EGL Vendor:     {s}
            \\EGL Extensions: {s}
            \\
        , .{
            std.mem.span(c.eglQueryString(egl_display, c.EGL_VERSION)),
            std.mem.span(c.eglQueryString(egl_display, c.EGL_VENDOR)),
            std.mem.span(c.eglQueryString(egl_display, c.EGL_EXTENSIONS)),
        });

        const config_attribute_list = [_]EGLint{
            c.EGL_RED_SIZE,
            8,
            c.EGL_GREEN_SIZE,
            8,
            c.EGL_BLUE_SIZE,
            8,
            c.EGL_ALPHA_SIZE,
            8,
            c.EGL_BUFFER_SIZE,
            32,
            c.EGL_STENCIL_SIZE,
            0,
            c.EGL_DEPTH_SIZE,
            16,
            // c.EGL_SAMPLES, 1,
            c.EGL_RENDERABLE_TYPE,
            switch (version) {
                .gles3 => c.EGL_OPENGL_ES3_BIT,
                .gles2 => c.EGL_OPENGL_ES2_BIT,
            },
            c.EGL_NONE,
        };

        var config: c.EGLConfig = undefined;
        var num_config: c.EGLint = undefined;
        if (c.eglChooseConfig(egl_display, &config_attribute_list, &config, 1, &num_config) == c.EGL_FALSE) {
            log.err("Error: eglChooseConfig failed: 0x{X:0>4}\n", .{c.eglGetError()});
            return error.FailedToInitializeEGL;
        }

        log.info("Config: {}\n", .{num_config});

        const context_attribute_list = [_]EGLint{ c.EGL_CONTEXT_CLIENT_VERSION, 2, c.EGL_NONE };

        const context = c.eglCreateContext(egl_display, config, null, &context_attribute_list) orelse {
            log.err("Error: eglCreateContext failed: 0x{X:0>4}\n", .{c.eglGetError()});
            return error.FailedToInitializeEGL;
        };
        errdefer _ = c.eglDestroyContext(egl_display, context);

        log.info("Context created: {?}\n", .{context});

        var native_window: c.EGLNativeWindowType = @as(c.EGLNativeWindowType, @ptrCast(window)); // this is safe, just a C import problem

        const android_width = android.ANativeWindow_getWidth(window);
        const android_height = android.ANativeWindow_getHeight(window);

        log.info("Screen Resolution: {}x{}\n", .{ android_width, android_height });

        const window_attribute_list = [_]EGLint{c.EGL_NONE};
        const egl_surface = c.eglCreateWindowSurface(egl_display, config, native_window, &window_attribute_list) orelse {
            log.err("Error: eglCreateWindowSurface failed: 0x{X:0>4}\n", .{c.eglGetError()});
            return error.FailedToInitializeEGL;
        };
        errdefer _ = c.eglDestroySurface(egl_display, context);

        log.info("Got Surface: {}\n", .{egl_surface});

        return Self{
            .display = egl_display,
            .surface = egl_surface,
            .context = context,
        };
    }

    pub fn deinit(self: *Self) void {
        _ = c.eglDestroySurface(self.display, self.surface);
        _ = c.eglDestroyContext(self.display, self.context);
        self.* = undefined;
    }

    pub fn swapBuffers(self: Self) !void {
        if (c.eglSwapBuffers(self.display, self.surface) == c.EGL_FALSE) {
            log.err("Error: eglMakeCurrent failed: 0x{X:0>4}\n", .{c.eglGetError()});
            return error.EglFailure;
        }
    }

    pub fn makeCurrent(self: Self) !void {
        if (c.eglMakeCurrent(self.display, self.surface, self.surface, self.context) == c.EGL_FALSE) {
            log.err("Error: eglMakeCurrent failed: 0x{X:0>4}\n", .{c.eglGetError()});
            return error.EglFailure;
        }
    }

    pub fn release(self: Self) void {
        if (c.eglMakeCurrent(self.display, self.surface, self.surface, null) == c.EGL_FALSE) {
            log.err("Error: eglMakeCurrent failed: 0x{X:0>4}\n", .{c.eglGetError()});
        }
    }
};
