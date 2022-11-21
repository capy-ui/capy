const std = @import("std");
const build_zelda = @import("vendor/zelda/build.zig");
const zig_libressl = if (@import("builtin").os.tag == .windows)
    struct {} // TODO: fix
else
    @import("vendor/zelda/zig-libressl/build.zig");

pub fn install(step: *std.build.LibExeObjStep, comptime prefix: []const u8) !void {
    step.subsystem = .Native;

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
        .macos => {
            if (@import("builtin").os.tag != .macos) {
                const b = step.builder;
                const sdk_root_dir = b.pathFromRoot("macos-sdk/");
                const sdk_framework_dir = std.fs.path.join(b.allocator, &.{ sdk_root_dir, "System/Library/Frameworks" }) catch unreachable;
                const sdk_include_dir = std.fs.path.join(b.allocator, &.{ sdk_root_dir, "usr/include" }) catch unreachable;
                const sdk_lib_dir = std.fs.path.join(b.allocator, &.{ sdk_root_dir, "usr/lib" }) catch unreachable;
                step.addFrameworkPath(sdk_framework_dir);
                step.addSystemIncludePath(sdk_include_dir);
                step.addLibraryPath(sdk_lib_dir);
            }

            step.linkLibC();
            step.linkFramework("CoreData");
            step.linkFramework("ApplicationServices");
            step.linkFramework("CoreFoundation");
            step.linkFramework("Foundation");
            step.linkFramework("AppKit");
            step.linkSystemLibraryName("objc");
        },
        .freestanding => {
            if (step.target.toTarget().isWasm()) {
                // Things like the image reader require more stack than given by default
                // TODO: remove once ziglang/zig#12589 is merged
                step.stack_size = std.math.max(step.stack_size orelse 0, 256 * 1024);
                if (step.build_mode == .ReleaseSmall) {
                    step.strip = true;
                }
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

    const zigimg = std.build.Pkg{
        .name = "zigimg",
        .source = std.build.FileSource.relative(prefix ++ "/vendor/zigimg/zigimg.zig"),
    };

    const zelda = build_zelda.pkgs.zelda;
    const use_system_libressl = @import("builtin").os.tag == .windows;
    if ((comptime @import("builtin").os.tag != .windows) and step.target.getOsTag() != .freestanding and step.target.getOsTag() != .windows) {
        try zig_libressl.useLibreSslForStep(
            step.builder,
            step.target,
            .ReleaseSafe,
            prefix ++ "/vendor/zelda/zig-libressl/libressl",
            step,
            use_system_libressl,
        );
    }

    const capy = std.build.Pkg{
        .name = "capy",
        .source = std.build.FileSource.relative(prefix ++ "/src/main.zig"),
        .dependencies = &[_]std.build.Pkg{ zigimg, zelda },
    };
    step.addPackage(capy);
}
