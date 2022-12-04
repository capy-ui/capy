const std = @import("std");
const AndroidSdk = @import("android/Sdk.zig");
//const build_zelda = @import("vendor/zelda/build.zig");
const zig_libressl = struct {};
// const zig_libressl = if (@import("builtin").os.tag == .windows)
//     struct {} // TODO: fix
// else
//     @import("vendor/zelda/zig-libressl/build.zig");

pub const CapyBuildOptions = struct {
    android: AndroidOptions = .{},

    pub const AndroidOptions = struct {
        // As of 2022, 95% of Android devices use Android 8 (Oreo) or higher
        version: AndroidSdk.AndroidVersion = .android8,
        // TODO: implement sdk downloading
        download_sdk_automatically: bool = true,
    };
};

pub fn install(step: *std.build.LibExeObjStep, options: CapyBuildOptions) !void {
    const prefix = comptime std.fs.path.dirname(@src().file).? ++ std.fs.path.sep_str;
    step.subsystem = .Native;

    const zigimg = std.build.Pkg{
        .name = "zigimg",
        .source = std.build.FileSource { .path = prefix ++ "/vendor/zigimg/zigimg.zig" },
    };

    // const zelda = build_zelda.pkgs.zelda;
    // const use_system_libressl = @import("builtin").os.tag == .windows;
    // if ((comptime @import("builtin").os.tag != .windows) and step.target.getOsTag() != .freestanding and step.target.getOsTag() != .windows and false) {
    //     try zig_libressl.useLibreSslForStep(
    //         step.builder,
    //         step.target,
    //         .ReleaseSafe,
    //         prefix ++ "/vendor/zelda/zig-libressl/libressl",
    //         step,
    //         use_system_libressl,
    //     );
    // }

    const capy = std.build.Pkg{
        .name = "capy",
        .source = std.build.FileSource { .path = prefix ++ "/src/main.zig" },
        //.dependencies = &[_]std.build.Pkg{ zigimg, zelda },
        .dependencies = &[_]std.build.Pkg{ zigimg },
    };
    if (!step.target.toTarget().isAndroid()) step.addPackage(capy);

    switch (step.target.getOsTag()) {
        .windows => {
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
        .linux, .freebsd => {
            if (step.target.toTarget().isAndroid()) {
                // TODO: automatically download the SDK and NDK and build tools?
                const sdk = AndroidSdk.init(step.builder, null, .{});
                const mode = step.build_mode;

                // Provide some KeyStore structure so we can sign our app.
                // Recommendation: Don't hardcore your password here, everyone can read it.
                // At least not for your production keystore ;)
                const key_store = AndroidSdk.KeyStore{
                    .file = ".build_config/android.keystore",
                    .alias = "default",
                    .password = "ziguana",
                };

                var libraries = std.ArrayList([]const u8).init(step.builder.allocator);
                try libraries.append("GLESv2");
                try libraries.append("EGL");
                try libraries.append("android");
                try libraries.append("log");

                const config = AndroidSdk.AppConfig{
                    .target_version = options.android.version,
                    // This is displayed to the user
                    .display_name = "Capy Example",
                    // This is used internally for ... things?
                    .app_name = "capyui_example",
                    // This is required for the APK name. This identifies your app, android will associate
                    // your signing key with this identifier and will prevent updates if the key changes.
                    .package_name = "io.capyui.example",
                    // This is a set of resources. It should at least contain a "mipmap/icon.png" resource that
                    // will provide the application icon.
                    .resources = &[_]AndroidSdk.Resource{
                        .{ .path = "mipmap/icon.png", .content = .{ .path = "android/default_icon.png" } },
                    },
                    .aaudio = false,
                    .opensl = false,
                    // This is a list of android permissions. Check out the documentation to figure out which you need.
                    .permissions = &[_][]const u8{
                        "android.permission.SET_RELEASE_APP",
                        //"android.permission.RECORD_AUDIO",
                    },
                    // This is a list of native android apis to link against.
                    .libraries = libraries.items,
                    .packages = &.{ },
                };

                const app = sdk.createApp(
                    "zig-out/capy-app.apk",
                    step.root_src.?.getPath(step.builder),
                    config,
                    mode,
                    .{
                        .aarch64 = true,
                        .arm = false,
                        .x86_64 = false,
                        .x86 = false,
                    }, // default targets
                    key_store,
                );

                const capy_android = std.build.Pkg{
                    .name = "capy",
                    .source = std.build.FileSource { .path = prefix ++ "/src/main.zig" },
                    .dependencies = &[_]std.build.Pkg{ zigimg, app.getAndroidPackage("android") },
                };
                for (app.libraries) |exe| {
                    // Provide the "android" package in each executable we build
                    exe.addPackage(capy_android);
                }
                step.addPackage(capy_android);
                step.export_symbol_names = &.{ "ANativeActivity_onCreate" };

                // Make the app build when we invoke "zig build" or "zig build install"
                // TODO: only invoke keystore if .build_config/android.keystore doesn't exist
                // When doing take environment variables or prompt if they're unavailable
                //step.step.dependOn(sdk.initKeystore(key_store, .{}));
                step.step.dependOn(app.final_step);

                //const b = step.builder;
                // const keystore_step = b.step("keystore", "Initialize a fresh debug keystore");
                // const push_step = b.step("push", "Push the app to a connected android device");
                // const run_step = b.step("run", "Run the app on a connected android device");

                // keystore_step.dependOn(sdk.initKeystore(key_store, .{}));
                // push_step.dependOn(app.install());
                // run_step.dependOn(app.run());
                step.step.dependOn(app.install());
                step.step.dependOn(app.run());
            } else {
                step.linkLibC();
                step.linkSystemLibrary("gtk+-3.0");
            }
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
}
