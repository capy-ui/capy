const std = @import("std");
const AndroidSdk = @import("android/Sdk.zig");
const Server = std.http.Server;

pub const CapyBuildOptions = struct {
    app_name: []const u8 = "Capy Example",
    windows: WindowsOptions = .{},
    mac: MacOptions = .{},
    linux: LinuxOptions = .{},
    // TODO: disable android build if password is not set
    // TODO: use optional
    android: AndroidOptions = .{ .password = "foo", .package_name = "org.capyui.example" },
    wasm: WasmOptions = .{},
    args: ?[]const []const u8 = &.{},
    link_libraries_on_root_module: bool = false,

    pub const WindowsOptions = struct {};

    pub const MacOptions = struct {};

    pub const AndroidOptions = struct {
        // As of 2022, 95% of Android devices use Android 8 (Oreo) or higher
        version: AndroidSdk.AndroidVersion = .android8,
        // TODO: implement sdk download
        download_sdk_automatically: bool = true,
        package_name: []const u8,
        /// The password that will be used to sign the keystore. Do not share with others!
        password: []const u8,
    };

    pub const WasmOptions = struct {
        extras_js_file: ?[]const u8 = null,
        debug_requests: bool = true,
    };

    pub const LinuxOptions = struct {};
};

/// Step used to run a web server for WebAssembly apps
const WebServerStep = struct {
    step: std.Build.Step,
    exe: *std.Build.Step.Compile,
    options: CapyBuildOptions.WasmOptions,

    pub fn create(owner: *std.Build, exe: *std.Build.Step.Compile, options: CapyBuildOptions.WasmOptions) *WebServerStep {
        const self = owner.allocator.create(WebServerStep) catch unreachable;
        self.* = .{
            .step = std.Build.Step.init(.{
                .id = .custom,
                .name = "webserver",
                .owner = owner,
                .makeFn = WebServerStep.make,
            }),
            .exe = exe,
            .options = options,
        };
        return self;
    }

    const Context = struct {
        exe: *std.Build.Step.Compile,
        builder: *std.Build,
    };

    pub fn make(step: *std.Build.Step, prog_node: *std.Progress.Node) !void {
        // There's no progress to report on.
        _ = prog_node;

        const self = @fieldParentPtr(WebServerStep, "step", step);
        const allocator = step.owner.allocator;
        _ = allocator;

        const address = std.net.Address.parseIp("::1", 8080) catch unreachable;
        var net_server = try address.listen(.{ .reuse_address = true });

        std.debug.print("Web server opened at http://localhost:8080/\n", .{});

        while (true) {
            const res = try net_server.accept();
            var read_buffer: [4096]u8 = undefined;
            var server = Server.init(res, &read_buffer);
            const thread = try std.Thread.spawn(.{}, handler, .{ self, step.owner, &server });
            thread.detach();
        }
    }

    fn handler(self: *WebServerStep, build: *std.Build, res: *Server) !void {
        const allocator = build.allocator;
        const prefix = comptime std.fs.path.dirname(@src().file).? ++ std.fs.path.sep_str;

        var req = try res.receiveHead();
        var arena = std.heap.ArenaAllocator.init(allocator);
        defer arena.deinit();
        const req_allocator = arena.allocator();

        const path = req.head.target;
        var file_path: []const u8 = "";
        var content_type: []const u8 = "text/html";
        if (std.mem.eql(u8, path, "/")) {
            file_path = try std.fs.path.join(req_allocator, &.{ prefix, "src/backends/wasm/index.html" });
            content_type = "text/html";
        } else if (std.mem.eql(u8, path, "/capy.js")) {
            file_path = try std.fs.path.join(req_allocator, &.{ prefix, "src/backends/wasm/capy.js" });
            content_type = "application/javascript";
        } else if (std.mem.eql(u8, path, "/capy-worker.js")) {
            file_path = try std.fs.path.join(req_allocator, &.{ prefix, "src/backends/wasm/capy-worker.js" });
            content_type = "application/javascript";
        } else if (std.mem.eql(u8, path, "/zig-app.wasm")) {
            file_path = self.exe.getEmittedBin().getPath2(build, &self.step);
            content_type = "application/wasm";
        } else if (std.mem.eql(u8, path, "/extras.js")) {
            if (self.options.extras_js_file) |extras_path| {
                file_path = extras_path;
                content_type = "application/javascript";
            }
        }

        if (self.options.debug_requests) {
            std.log.debug("{s} -> {s}", .{ path, file_path });
        }
        const file: ?std.fs.File = std.fs.cwd().openFile(file_path, .{ .mode = .read_only }) catch |err| blk: {
            switch (err) {
                error.FileNotFound => break :blk null,
                else => return err,
            }
        };

        var status: std.http.Status = .ok;
        const content = blk: {
            if (file) |f| {
                defer f.close();
                break :blk try f.readToEndAlloc(req_allocator, std.math.maxInt(usize));
            } else {
                status = .not_found;
                break :blk "404 Not Found";
            }
        };

        try req.respond(content, .{
            .status = status,
            .keep_alive = false,
            .extra_headers = &.{
                .{ .name = "Connection", .value = "close" },
                .{ .name = "Content-Type", .value = content_type },
                .{ .name = "Cross-Origin-Opener-Policy", .value = "same-origin" },
                .{ .name = "Cross-Origin-Embedder-Policy", .value = "require-corp" },
                // TODO: Content-Length ?
            },
            .transfer_encoding = .none,
        });
        res.connection.stream.close();
    }
};

/// Takes the given CompileStep and options and returns a run step.
/// The run step from this function must be used because it depends on the target,
/// running a binary on your local machine isn't the same as spinning a local web server
/// for WebAssembly or using ADB to upload your Android app to your phone.
/// If you do not wish to run your CompileStep, ignore the run step by doing
/// _ = install(step, .{ ... });
pub fn install(step: *std.Build.Step.Compile, options: CapyBuildOptions) !*std.Build.Step {
    const prefix = comptime std.fs.path.dirname(@src().file).? ++ std.fs.path.sep_str;
    const b = step.step.owner;
    step.subsystem = .Native;

    const capy = b.createModule(.{
        .root_source_file = .{ .path = prefix ++ "/src/main.zig" },
        .target = step.root_module.resolved_target,
        .imports = &.{},
    });
    if (!options.link_libraries_on_root_module) {
        step.root_module.addImport("capy", capy);
    }

    const module = if (options.link_libraries_on_root_module)
        &step.root_module
    else
        capy;

    const zigimg_dep = b.dependency("zigimg", .{
        .target = step.root_module.resolved_target.?,
        .optimize = step.root_module.optimize orelse .Debug,
    });
    const zigimg = zigimg_dep.module("zigimg");
    module.addImport("zigimg", zigimg);
    switch (step.rootModuleTarget().os.tag) {
        .windows => {
            switch (step.root_module.optimize orelse .Debug) {
                .Debug => step.subsystem = .Console,
                else => step.subsystem = .Windows,
            }
            const zigwin32 = b.createModule(.{
                .root_source_file = .{ .path = prefix ++ "/vendor/zigwin32/win32.zig" },
            });
            module.addImport("zigwin32", zigwin32);

            module.linkSystemLibrary("comctl32", .{});
            module.linkSystemLibrary("gdi32", .{});
            module.linkSystemLibrary("gdiplus", .{});

            // TODO: use capy.addWin32ResourceFile
            switch (step.rootModuleTarget().cpu.arch) {
                .x86_64 => module.addObjectFile(.{ .path = prefix ++ "/src/backends/win32/res/x86_64.o" }),
                //.i386 => step.addObjectFile(prefix ++ "/src/backends/win32/res/i386.o"), // currently disabled due to problems with safe SEH
                else => {}, // not much of a problem as it'll just lack styling
            }
        },
        .macos => {
            if (@import("builtin").os.tag != .macos) {
                // const sdk_root_dir = b.pathFromRoot("macos-sdk/");
                // const sdk_framework_dir = std.fs.path.join(b.allocator, &.{ sdk_root_dir, "System/Library/Frameworks" }) catch unreachable;
                // const sdk_include_dir = std.fs.path.join(b.allocator, &.{ sdk_root_dir, "usr/include" }) catch unreachable;
                // const sdk_lib_dir = std.fs.path.join(b.allocator, &.{ sdk_root_dir, "usr/lib" }) catch unreachable;
                // module.addFrameworkPath(.{ .path = sdk_framework_dir });
                // module.addSystemIncludePath(.{ .path = sdk_include_dir });
                // module.addLibraryPath(.{ .path = sdk_lib_dir });
                // @import("macos_sdk").addPathsModule(module);
                @import("macos_sdk").addPaths(step);
            }

            const objc = b.dependency("zig-objc", .{ .target = step.root_module.resolved_target.?, .optimize = step.root_module.optimize.? });
            module.addImport("objc", objc.module("objc"));

            module.link_libc = true;
            module.linkFramework("CoreData", .{});
            module.linkFramework("ApplicationServices", .{});
            module.linkFramework("CoreFoundation", .{});
            module.linkFramework("CoreGraphics", .{});
            module.linkFramework("CoreText", .{});
            module.linkFramework("CoreServices", .{});
            module.linkFramework("Foundation", .{});
            module.linkFramework("AppKit", .{});
            module.linkFramework("ColorSync", .{});
            module.linkFramework("ImageIO", .{});
            module.linkFramework("CFNetwork", .{});
            module.linkSystemLibrary("objc", .{ .use_pkg_config = .no });
        },
        .linux, .freebsd => {
            if (step.rootModuleTarget().isAndroid()) {
                // // TODO: automatically download the SDK and NDK and build tools?
                // // TODO: download Material components by parsing Maven?
                const sdk = AndroidSdk.init(b, null, .{});
                const optimize = step.root_module.optimize orelse .Debug;

                // Provide some KeyStore structure so we can sign our app.
                // Recommendation: Don't hardcore your password here, everyone can read it.
                // At least not for your production keystore ;)
                const key_store = AndroidSdk.KeyStore{
                    .file = ".build_config/android.keystore",
                    .alias = "default",
                    .password = options.android.password,
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
                    step.root_module.root_source_file.?.getPath(b),
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
                    exe.root_module.addImport("capy", capy);
                    exe.root_module.addImport("android", android_module);
                }
                step.root_module.addImport("capy", capy);
                step.root_module.export_symbol_names = &.{"ANativeActivity_onCreate"};

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
                module.link_libc = true;
                module.linkSystemLibrary("gtk4", .{});
            }
        },
        .freestanding => {
            if (step.rootModuleTarget().isWasm()) {
                // Things like the image reader require more stack than given by default
                // TODO: remove once ziglang/zig#12589 is merged
                step.stack_size = @max(step.stack_size orelse 0, 256 * 1024);
                if (step.root_module.optimize == .ReleaseSmall) {
                    step.root_module.strip = true;
                }
                capy.export_symbol_names = &.{"_start"};

                const serve = WebServerStep.create(b, step, options.wasm);
                const install_step = b.addInstallArtifact(step, .{});
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

comptime {
    const supported_zig = std.SemanticVersion.parse("0.12.0-dev.3180+83e578a18") catch unreachable;
    if (@import("builtin").zig_version.order(supported_zig) != .eq) {
        @compileError(std.fmt.comptimePrint("unsupported Zig version ({}). Required Zig version 2024.3.0-mach: https://machengine.org/about/nominated-zig/#202430-mach", .{@import("builtin").zig_version}));
    }
}
