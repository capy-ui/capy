const std = @import("std");
pub const runStep = @import("build_capy.zig").runStep;
pub const CapyBuildOptions = @import("build_capy.zig").CapyBuildOptions;
pub const CapyRunOptions = @import("build_capy.zig").CapyRunOptions;
const AndroidSdk = @import("android/Sdk.zig");

const LazyPath = std.Build.LazyPath;

fn installCapyDependencies(b: *std.Build, module: *std.Build.Module, options: CapyBuildOptions) !void {
    const target = module.resolved_target.?;
    const optimize = module.optimize.?;

    const zigimg_dep = b.dependency("zigimg", .{
        .target = target,
        .optimize = optimize,
    });
    const zigimg = zigimg_dep.module("zigimg");

    module.addImport("zigimg", zigimg);
    switch (target.result.os.tag) {
        .windows => {
            const zigwin32 = b.createModule(.{
                .root_source_file = b.path("vendor/zigwin32/win32.zig"),
            });
            module.addImport("zigwin32", zigwin32);

            module.linkSystemLibrary("comctl32", .{});
            module.linkSystemLibrary("gdi32", .{});
            module.linkSystemLibrary("gdiplus", .{});

            module.addWin32ResourceFile(.{ .file = b.path("src/backends/win32/res/resource.rc") });
            // switch (step.rootModuleTarget().cpu.arch) {
            // .x86_64 => module.addObjectFile(.{ .cwd_relative = prefix ++ "/src/backends/win32/res/x86_64.o" }),
            //.i386 => step.addObjectFile(prefix ++ "/src/backends/win32/res/i386.o"), // currently disabled due to problems with safe SEH
            // else => {}, // not much of a problem as it'll just lack styling
            // }
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
                if (b.lazyImport(@This(), "macos_sdk")) |macos_sdk| {
                    macos_sdk.addPathsModule(module);
                }
            }

            if (b.lazyDependency("zig-objc", .{ .target = target, .optimize = optimize })) |objc| {
                module.addImport("objc", objc.module("objc"));
            }

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
            if (target.result.abi.isAndroid()) {
                const sdk = AndroidSdk.init(b, null, .{});
                var libraries = std.ArrayList([]const u8).init(b.allocator);
                try libraries.append("android");
                try libraries.append("log");
                const config = AndroidSdk.AppConfig{
                    .target_version = options.android_version,
                    // This is displayed to the user
                    .display_name = options.app_name,
                    // This is used internally for ... things?
                    .app_name = "capyui_example",
                    // This is required for the APK name. This identifies your app, android will associate
                    // your signing key with this identifier and will prevent updates if the key changes.
                    .package_name = options.android_package_name,
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
                // TODO: other architectures
                sdk.configureModule(module, config, .aarch64);
                // TODO: find a way to contory ZigAndroidTemplate enough so it fits into the Zig build system
            } else {
                module.link_libc = true;
                module.linkSystemLibrary("gtk4", .{});
            }
        },
        .wasi => {
            if (target.result.cpu.arch.isWasm()) {
                // Things like the image reader require more stack than given by default
                // TODO: remove once ziglang/zig#12589 is merged
                module.export_symbol_names = &.{"_start"};
            } else {
                return error.UnsupportedOs;
            }
        },
        .freestanding => {
            if (target.result.cpu.arch.isWasm()) {
                std.log.warn("For targeting the Web, WebAssembly builds must now be compiled using the `wasm32-wasi` target.", .{});
            }
            return error.UnsupportedOs;
        },
        else => {
            return error.UnsupportedOs;
        },
    }
}

pub fn build(b: *std.Build) !void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const app_name = b.option([]const u8, "app_name", "The name of the application, to be used for packaging purposes.");

    const options = CapyBuildOptions{
        .target = target,
        .optimize = optimize,
        .app_name = app_name orelse "Capy Example",
    };

    const module = b.addModule("capy", .{
        .root_source_file = b.path("src/capy.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{},
    });
    try installCapyDependencies(b, module, options);

    const examples_dir_path = b.path("examples").getPath(b);
    var examples_dir = try std.fs.cwd().openDir(examples_dir_path, .{ .iterate = true });
    defer examples_dir.close();

    const broken = switch (target.result.os.tag) {
        .windows => &[_][]const u8{ "osm-viewer", "fade", "slide-viewer", "demo", "notepad", "dev-tools" },
        else => &[_][]const u8{},
    };

    var walker = try examples_dir.walk(b.allocator);
    defer walker.deinit();
    while (try walker.next()) |entry| {
        if (entry.kind == .file and std.mem.eql(u8, std.fs.path.extension(entry.path), ".zig")) {
            const name = try std.mem.replaceOwned(u8, b.allocator, entry.path[0 .. entry.path.len - 4], std.fs.path.sep_str, "-");
            defer b.allocator.free(name);

            // it is not freed as the path is used later for building
            const programPath = b.path(b.pathJoin(&.{ "examples", entry.path }));

            const exe: *std.Build.Step.Compile = b.addExecutable(.{
                .name = name,
                .root_source_file = programPath,
                .target = target,
                .optimize = optimize,
            });
            exe.root_module.addImport("capy", module);

            const install_step = b.addInstallArtifact(exe, .{});
            const is_working = blk: {
                for (broken) |broken_name| {
                    if (std.mem.eql(u8, name, broken_name))
                        break :blk false;
                }
                break :blk true;
            };
            if (is_working) {
                b.getInstallStep().dependOn(&install_step.step);
            } else {
                // std.log.warn("'{s}' is broken (disabled by default)", .{name});
            }
            const run_cmd = try runStep(exe, .{});

            const run_step = b.step(name, "Run this example");
            run_step.dependOn(run_cmd);
        }
    }

    const lib = b.addSharedLibrary(.{
        .name = "capy",
        .root_source_file = b.path("src/c_api.zig"),
        .version = std.SemanticVersion{ .major = 0, .minor = 4, .patch = 0 },
        .target = target,
        .optimize = optimize,
    });
    lib.linkLibC();
    lib.root_module.addImport("capy", module);
    // const h_install = b.addInstallFile(lib.getEmittedH(), "headers.h");
    // b.getInstallStep().dependOn(&h_install.step);
    const lib_install = b.addInstallArtifact(lib, .{});
    b.getInstallStep().dependOn(&lib_install.step);

    const buildc_step = b.step("shared", "Build capy as a shared library (with C ABI)");
    buildc_step.dependOn(&lib_install.step);

    //
    // Unit tests
    //
    const tests = b.addTest(.{
        .root_source_file = b.path("src/capy.zig"),
        .target = target,
        .optimize = optimize,
    });
    try installCapyDependencies(b, tests.root_module, options);
    const run_tests = try runStep(tests, .{});

    const test_step = b.step("test", "Run unit tests and also generate the documentation");
    test_step.dependOn(run_tests);

    //
    // Documentation generation
    //
    const docs = b.addObject(.{
        .name = "capy",
        .root_source_file = b.path("src/capy.zig"),
        .target = target,
        .optimize = .Debug,
    });
    try installCapyDependencies(b, docs.root_module, options);
    const install_docs = b.addInstallDirectory(.{
        .source_dir = docs.getEmittedDocs(),
        .install_dir = .prefix,
        .install_subdir = "docs",
    });

    const docs_step = b.step("docs", "Generate documentation and run unit tests");
    docs_step.dependOn(&install_docs.step);

    b.getInstallStep().dependOn(&install_docs.step);

    //
    // Coverage tests
    //
    const coverage_tests = b.addTest(.{
        .root_source_file = b.path("src/capy.zig"),
        .target = target,
        .optimize = optimize,
    });
    coverage_tests.setExecCmd(&.{ "kcov", "--clean", "--include-pattern=src/", "kcov-output", null });
    try installCapyDependencies(b, coverage_tests.root_module, options);

    const run_coverage_tests = b.addSystemCommand(&.{ "kcov", "--clean", "--include-pattern=src/", "kcov-output" });
    run_coverage_tests.addArtifactArg(coverage_tests);

    // const run_coverage_tests = b.addRunArtifact(coverage_tests);
    // run_coverage_tests.has_side_effects = true;

    const cov_step = b.step("coverage", "Perform code coverage of unit tests. This requires 'kcov' to be installed.");
    cov_step.dependOn(&run_coverage_tests.step);
}
