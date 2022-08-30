const std = @import("std");

pub fn install(step: *std.build.LibExeObjStep, comptime prefix: []const u8) !void {
    step.subsystem = .Native;
    step.use_stage1 = true;

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
                // Things like the image reader require more stack than given by default
                // TODO: remove once ziglang/zig#12589 is merged
                step.stack_size = std.math.max(step.stack_size orelse 0, 256 * 1024);
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

    const zigimg = std.build.Pkg {
        .name = "zigimg",
        .source = std.build.FileSource.relative(prefix ++ "/vendor/zigimg/zigimg.zig"),
    };
    
    const zfetch = try @import("vendor/zfetch/build.zig").getPackage(step.builder);

    const capy = std.build.Pkg{
        .name = "capy",
        .source = std.build.FileSource.relative(prefix ++ "/src/main.zig"),
        .dependencies = &[_]std.build.Pkg{ zigimg, zfetch },
    };
    step.addPackage(capy);
}
