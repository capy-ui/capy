const std = @import("std");

pub fn install(step: *std.build.LibExeObjStep, comptime prefix: []const u8) !void {
    step.subsystem = .Native;
    // step.linkSystemLibrary("glfw");
    // step.linkSystemLibrary("GLESv2");

    switch (step.target.getOsTag()) {
        .linux, .freebsd => {
            step.linkLibC();
            step.linkSystemLibrary("gtk+-3.0");
        },
        .windows => {
            // There doesn't seem to be a way to link to a .def file so we temporarily put it in the Zig installation folder
            const libcommon = step.builder.pathJoin(&.{ std.fs.path.dirname(step.builder.zig_exe).?, "lib", "libc", "mingw", "lib-common", "gdiplus.def" });
            defer step.builder.allocator.free(libcommon);
            std.fs.accessAbsolute(libcommon, .{}) catch |err| switch (err) {
                error.FileNotFound => {
                    try std.fs.copyFileAbsolute(step.builder.pathFromRoot(prefix ++ "/src/backends/win32/gdiplus.def"), libcommon, .{});
                },
                else => {},
            };

            switch (step.build_mode) {
                .Debug => step.subsystem = .Console,
                else => step.subsystem = .Windows,
            }
            step.linkSystemLibrary("comctl32");
            step.linkSystemLibrary("gdi32");
            step.linkSystemLibrary("gdiplus");
            switch (step.target.toTarget().cpu.arch) {
                .x86_64 => step.addObjectFile(prefix ++ "/src/backends/win32/res/x86_64.o"),
                //.i386 => step.addObjectFile(prefix ++ "/src/backends/win32/res/i386.o"), // currently disabled due to problems with safe SEH
                else => {}, // not much of a problem as it'll just lack styling
            }
        },
        .freestanding => {
            if (step.target.toTarget().isWasm()) {
                // supported
            } else {
                return error.UnsupportedOs;
            }
        },
        else => {
            // TODO: use the GLES backend as long as the windowing system is supported
            // but the UI library isn't
            return error.UnsupportedOs;
        },
    }

    const capy = std.build.Pkg{
        .name = "capy",
        .source = std.build.FileSource.relative(prefix ++ "/src/main.zig"),
        .dependencies = &[_]std.build.Pkg{},
    };
    step.addPackage(capy);
}
