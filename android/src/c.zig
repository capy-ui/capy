const build_options = @import("build_options");
pub usingnamespace @cImport({
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
