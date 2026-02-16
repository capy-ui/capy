const build_options = @import("build_options");

// TODO: `pub usingnamespace @cImport({...});` was removed to eliminate usingnamespace.
// This file re-exported all declarations from the cImport of EGL, GLES2, and optionally
// AAudio/OpenSLES headers. To complete this replacement, identify which C declarations
// are actually used by consumers of this module and forward them explicitly from the
// cImport below. For now, this is Android-only code and does not affect macOS compilation.
const _c = @cImport({
    @cInclude("EGL/egl.h");
    // @cInclude("EGL/eglext.h");
    @cInclude("GLES2/gl2.h");
    @cInclude("GLES2/gl2ext.h");
    // @cInclude("unwind.h");
    // @cInclude("dlfcn.h");
    if (build_options.enable_aaudio) {
        @cInclude("aaudio/AAudio.h");
    }
    if (build_options.enable_opensl) {
        @cInclude("SLES/OpenSLES.h");
        @cInclude("SLES/OpenSLES_Android.h");
    }
});
// TODO: Forward specific declarations from _c that are needed by consumers of this module.
// Example: pub const EGLDisplay = _c.EGLDisplay;
