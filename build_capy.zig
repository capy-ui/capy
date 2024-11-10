const std = @import("std");
const AndroidSdk = @import("android/Sdk.zig");
const Server = std.http.Server;

pub const CapyBuildOptions = struct {
    // Build related
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,

    // Configuration
    app_name: []const u8 = "Capy Example",

    // Windows
    // Nothing.

    // macOS
    // Nothing.

    // Linux
    // Nothing.

    // Android
    // As of 2022, 95% of Android devices use Android 8 (Oreo) or higher
    android_version: AndroidSdk.AndroidVersion = .android8,
    // TODO: implement sdk download
    android_download_sdk_automatically: bool = true,
    android_package_name: []const u8 = "org.capyui.example",
    // TODO: disable android build if password is not set
    // TODO: use optional
    /// The password that will be used to sign the keystore. Do not share with others!
    android_password: []const u8 = "foo",
};

pub const CapyRunOptions = struct {
    args: ?[]const []const u8 = &.{},

    // WebAssembly
    /// The path to an 'extras.js' file to be used by the WebAssembly backend
    wasm_extras_js_file: ?[]const u8 = null,
    /// Log every request from the built-in Web server that's used to host WebAssembly applications.
    wasm_debug_requests: bool = true,
};

/// Step used to run a web server for WebAssembly apps
const WebServerStep = struct {
    step: std.Build.Step,
    exe: *std.Build.Step.Compile,
    options: CapyRunOptions,

    pub fn create(owner: *std.Build, exe: *std.Build.Step.Compile, options: CapyRunOptions) *WebServerStep {
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

    pub fn make(step: *std.Build.Step, options: std.Build.Step.MakeOptions) !void {
        // Options are unused.
        _ = options;

        const self: *WebServerStep = @fieldParentPtr("step", step);
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

        var req = try res.receiveHead();
        var arena = std.heap.ArenaAllocator.init(allocator);
        defer arena.deinit();
        const req_allocator = arena.allocator();

        const path = req.head.target;
        var file_path: []const u8 = "";
        var file_content: ?[]const u8 = null;
        var content_type: []const u8 = "text/html";
        if (std.mem.eql(u8, path, "/")) {
            file_content = @embedFile("src/backends/wasm/index.html");
            content_type = "text/html";
        } else if (std.mem.eql(u8, path, "/capy.js")) {
            file_content = @embedFile("src/backends/wasm/capy.js");
            content_type = "application/javascript";
        } else if (std.mem.eql(u8, path, "/capy-worker.js")) {
            file_content = @embedFile("src/backends/wasm/capy-worker.js");
            content_type = "application/javascript";
        } else if (std.mem.eql(u8, path, "/zig-app.wasm")) {
            file_path = self.exe.getEmittedBin().getPath2(build, &self.step);
            content_type = "application/wasm";
        } else if (std.mem.eql(u8, path, "/extras.js")) {
            if (self.options.wasm_extras_js_file) |extras_path| {
                file_path = extras_path;
                content_type = "application/javascript";
            }
        } else {
            // else try the HTML files supplied by the application (in the 'html' project relative
            // to the project root)
            file_path = try std.fs.path.join(req_allocator, &.{ "html", path });
            content_type = "application/javascript";
        }

        if (self.options.wasm_debug_requests) {
            std.log.debug("{s} -> {s}", .{ path, file_path });
        }

        var status: std.http.Status = .ok;
        const content = blk: {
            if (file_content) |presupplied_content| {
                break :blk presupplied_content;
            } else {
                const file: ?std.fs.File = std.fs.cwd().openFile(file_path, .{ .mode = .read_only }) catch |err| blk2: {
                    switch (err) {
                        error.FileNotFound => break :blk2 null,
                        else => return err,
                    }
                };
                if (file) |f| {
                    defer f.close();
                    break :blk try f.readToEndAlloc(req_allocator, std.math.maxInt(usize));
                } else {
                    status = .not_found;
                    break :blk "404 Not Found";
                }
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
/// The run step from this function must be used because it depends on the target.
/// Running a binary on your local machine isn't the same as spinning a local web server
/// for WebAssembly or using ADB to upload your Android app to your phone.
pub fn runStep(step: *std.Build.Step.Compile, options: CapyRunOptions) !*std.Build.Step {
    const b = step.step.owner;

    const optimize = step.root_module.optimize.?;
    switch (step.rootModuleTarget().os.tag) {
        .windows => {
            step.subsystem = switch (optimize) {
                .Debug => .Console,
                else => .Windows,
            };
        },
        .macos => {},
        .linux, .freebsd => {
            if (step.rootModuleTarget().isAndroid()) {
                // TODO: find a new way to build Android applications
                // // TODO: automatically download the SDK and NDK and build tools?
                // // TODO: download Material components by parsing Maven?
                const sdk = AndroidSdk.init(b, null, .{});

                // // Provide some KeyStore structure so we can sign our app.
                // // Recommendation: Don't hardcore your password here, everyone can read it.
                // // At least not for your production keystore ;)
                // const key_store = AndroidSdk.KeyStore{
                //     .file = ".build_config/android.keystore",
                //     .alias = "default",
                //     .password = options.android.password,
                // };

                var libraries = std.ArrayList([]const u8).init(b.allocator);
                try libraries.append("GLESv2");
                try libraries.append("EGL");
                try libraries.append("android");
                try libraries.append("log");

                const config = AndroidSdk.AppConfig{
                    .target_version = .android9,
                    // This is displayed to the user
                    .display_name = "Capy",
                    // This is used internally for ... things?
                    .app_name = "capyui_example",
                    // This is required for the APK name. This identifies your app, android will associate
                    // your signing key with this identifier and will prevent updates if the key changes.
                    .package_name = "org.capyui.example",
                    // This is a set of resources. It should at least contain a "mipmap/icon.png" resource that
                    // will provide the application icon.
                    .resources = &[_]AndroidSdk.Resource{
                        .{ .path = "mipmap/icon.png", .content = b.path("android/default_icon.png") },
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
                sdk.configureStep(step, config, .aarch64);

                // const app = sdk.createApp(
                //     "zig-out/capy-app.apk",
                //     step.root_module.root_source_file.?.getPath(b),
                //     &.{ "android/src/CanvasView.java", "android/src/NativeInvocationHandler.java" },
                //     config,
                //     optimize,
                //     .{
                //         .aarch64 = true,
                //         .arm = false,
                //         .x86_64 = false,
                //         .x86 = false,
                //     }, // default targets
                //     key_store,
                // );

                // const android_module = b.modules.get("android").?;
                // for (app.libraries) |exe| {
                //     // Provide the "android" package in each executable we build
                //     exe.root_module.addImport("capy", capy);
                //     exe.root_module.addImport("android", android_module);
                // }
                // step.root_module.addImport("capy", capy);
                // step.root_module.export_symbol_names = &.{"ANativeActivity_onCreate"};

                // // Make the app build when we invoke "zig build" or "zig build install"
                // // TODO: only invoke keystore if .build_config/android.keystore doesn't exist
                // // When doing take environment variables or prompt if they're unavailable
                // //step.step.dependOn(sdk.initKeystore(key_store, .{}));
                // step.step.dependOn(app.final_step);

                // // keystore_step.dependOn(sdk.initKeystore(key_store, .{}));
                // const install_step = app.install();
                // const run_step = app.run();
                // run_step.dependOn(install_step);
                // return run_step;
            }
        },
        .wasi => {
            // Things like the image reader require more stack than given by default
            if (step.root_module.optimize == .ReleaseSmall) {
                step.root_module.strip = true;
            }

            const serve = WebServerStep.create(b, step, options);
            const install_step = b.addInstallArtifact(step, .{});
            serve.step.dependOn(&install_step.step);
            return &serve.step;
        },
        else => {
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
    const supported_zig = std.SemanticVersion.parse("0.14.0-dev.1911+3bf89f55c") catch unreachable;
    const zig_version = @import("builtin").zig_version;
    if (zig_version.order(supported_zig) != .eq) {
        @compileError(std.fmt.comptimePrint("unsupported Zig version ({}). Required Zig version 2024.10.0-mach: https://machengine.org/docs/nominated-zig/#2024100-mach", .{@import("builtin").zig_version}));
    }
}
