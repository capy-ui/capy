const std = @import("std");
const AndroidSdk = @import("android/Sdk.zig");
const Server = std.http.Server;

pub const CapyBuildOptions = struct {
    app_name: []const u8 = "Capy Example",
    android: AndroidOptions = .{},
    args: ?[]const []const u8 = &.{},

    pub const AndroidOptions = struct {
        // As of 2022, 95% of Android devices use Android 8 (Oreo) or higher
        version: AndroidSdk.AndroidVersion = .android8,
        // TODO: implement sdk download
        download_sdk_automatically: bool = true,
        package_name: []const u8 = "io.capyui.example",
    };
};

/// Step used to run a web server for WebAssembly apps
const WebServerStep = struct {
    step: std.build.Step,
    exe: *std.build.CompileStep,

    pub fn create(owner: *std.build.Builder, exe: *std.build.LibExeObjStep) *WebServerStep {
        const self = owner.allocator.create(WebServerStep) catch unreachable;
        self.* = .{
            .step = std.build.Step.init(.{
                .id = .custom,
                .name = "webserver",
                .owner = owner,
                .makeFn = WebServerStep.make,
            }),
            .exe = exe,
        };
        return self;
    }

    const Context = struct {
        exe: *std.build.CompileStep,
        builder: *std.build.Builder,
    };

    pub fn make(step: *std.build.Step, prog_node: *std.Progress.Node) !void {
        // There's no progress to report on.
        _ = prog_node;

        const self = @fieldParentPtr(WebServerStep, "step", step);
        const allocator = step.owner.allocator;

        var server = Server.init(allocator, .{ .reuse_address = true });
        defer server.deinit();

        try server.listen(try std.net.Address.parseIp("127.0.0.1", 8080));
        std.debug.print("Web server opened at http://localhost:8080/\n", .{});

        while (true) {
            const res = try server.accept(.{ .dynamic = 8192 });
            const thread = try std.Thread.spawn(.{}, handler, .{ self, step.owner, res });
            thread.detach();
        }
    }

    fn handler(self: *WebServerStep, build: *std.Build, res: *Server.Response) !void {
        const allocator = build.allocator;
        const build_root = build.build_root.path orelse unreachable;
        while (true) {
            defer res.reset();
            try res.wait();

            var arena = std.heap.ArenaAllocator.init(allocator);
            defer arena.deinit();
            const req_allocator = arena.allocator();

            const path = res.request.headers.target;
            var file_path: []const u8 = "";
            var content_type: []const u8 = "text/html";
            if (std.mem.eql(u8, path, "/")) {
                file_path = try std.fs.path.join(req_allocator, &.{ build_root, "src/backends/wasm/index.html" });
                content_type = "text/html";
            } else if (std.mem.eql(u8, path, "/capy.js")) {
                file_path = try std.fs.path.join(req_allocator, &.{ build_root, "src/backends/wasm/capy.js" });
                content_type = "application/javascript";
            } else if (std.mem.eql(u8, path, "/zig-app.wasm")) {
                file_path = self.exe.getOutputSource().getPath2(build, &self.step);
                content_type = "application/wasm";
            }

            res.headers.transfer_encoding = .{ .content_length = 14 };
            res.headers.connection = res.request.headers.connection;
            res.headers.custom = &.{
                .{ .name = "Content-Type", .value = content_type },
            };
            try res.do();

            _ = try res.write("Hello, World!\n");

            if (res.connection.conn.closing) break;
        }
    }
};

/// Takes the given CompileStep and options and returns a run step.
/// The run step from this function must be used because it depends on the target,
/// running a binary on your local machine isn't the same as spinning a local web server
/// for WebAssembly or using ADB to upload your Android app to your phone.
/// If you do not wish to run your CompileStep, ignore the run step by doing
/// _ = install(step, .{ ... });
pub fn install(step: *std.Build.CompileStep, options: CapyBuildOptions) !*std.Build.Step {
    const prefix = comptime std.fs.path.dirname(@src().file).? ++ std.fs.path.sep_str;
    const b = step.step.owner;
    step.subsystem = .Native;

    const zigimg = b.createModule(.{
        .source_file = .{ .path = prefix ++ "/vendor/zigimg/zigimg.zig" },
    });

    step.addAnonymousModule("capy", .{
        .source_file = .{ .path = prefix ++ "/src/main.zig" },
        .dependencies = &.{.{ .name = "zigimg", .module = zigimg }},
    });

    // const capy = std.build.Pkg{
    //     .name = "capy",
    //     .source = std.build.FileSource{ .path = prefix ++ "/src/main.zig" },
    //     //.dependencies = &[_]std.build.Pkg{ zigimg, zelda },
    //     .dependencies = &[_]std.build.Pkg{zigimg},
    // };
    //if (!step.target.toTarget().isAndroid()) step.addPackage(capy);

    switch (step.target.getOsTag()) {
        .windows => {
            switch (step.optimize) {
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
                // // TODO: automatically download the SDK and NDK and build tools?
                // // TODO: download Material components by parsing Maven?
                const sdk = AndroidSdk.init(b, null, .{});
                const optimize = step.optimize;

                // Provide some KeyStore structure so we can sign our app.
                // Recommendation: Don't hardcore your password here, everyone can read it.
                // At least not for your production keystore ;)
                const key_store = AndroidSdk.KeyStore{
                    .file = ".build_config/android.keystore",
                    .alias = "default",
                    .password = "ziguana",
                };

                var libraries = std.ArrayList([]const u8).init(b.allocator);
                try libraries.append("GLESv2");
                try libraries.append("EGL");
                try libraries.append("android");
                try libraries.append("log");

                const config = AndroidSdk.AppConfig{
                    .target_version = options.android.version,
                    // This is displayed to the user
                    .display_name = options.app_name,
                    // This is used internally for ... things?
                    .app_name = "capyui_example",
                    // This is required for the APK name. This identifies your app, android will associate
                    // your signing key with this identifier and will prevent updates if the key changes.
                    .package_name = options.android.package_name,
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
                    //.fullscreen = true,
                };

                const app = sdk.createApp(
                    "zig-out/capy-app.apk",
                    step.root_src.?.getPath(b),
                    &.{ "android/src/CanvasView.java", "android/src/NativeInvocationHandler.java" },
                    config,
                    optimize,
                    .{
                        .aarch64 = true,
                        .arm = false,
                        .x86_64 = false,
                        .x86 = false,
                    }, // default targets
                    key_store,
                );

                const android_module = b.modules.get("android").?;
                for (app.libraries) |exe| {
                    // Provide the "android" package in each executable we build
                    exe.addAnonymousModule("capy", .{
                        .source_file = .{ .path = prefix ++ "/src/main.zig" },
                        .dependencies = &.{
                            .{ .name = "zigimg", .module = zigimg },
                            .{ .name = "android", .module = android_module },
                        },
                    });
                    exe.addModule("android", android_module);
                }
                step.addAnonymousModule("capy", .{
                    .source_file = .{ .path = prefix ++ "/src/main.zig" },
                    .dependencies = &.{
                        .{ .name = "zigimg", .module = zigimg },
                        .{ .name = "android", .module = android_module },
                    },
                });
                step.export_symbol_names = &.{"ANativeActivity_onCreate"};

                // Make the app build when we invoke "zig build" or "zig build install"
                // TODO: only invoke keystore if .build_config/android.keystore doesn't exist
                // When doing take environment variables or prompt if they're unavailable
                //step.step.dependOn(sdk.initKeystore(key_store, .{}));
                step.step.dependOn(app.final_step);

                // keystore_step.dependOn(sdk.initKeystore(key_store, .{}));
                const install_step = app.install();
                const run_step = app.run();
                run_step.dependOn(install_step);
                return run_step;
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
                if (step.optimize == .ReleaseSmall) {
                    step.strip = true;
                }

                const serve = WebServerStep.create(b, step);
                const install_step = b.addInstallArtifact(step);
                serve.step.dependOn(&install_step.step);
                return &serve.step;
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

    const run_step = b.addRunArtifact(step);
    if (options.args) |args| {
        run_step.addArgs(args);
    }
    return &run_step.step; // this works because run_step is allocated on the heap
}
