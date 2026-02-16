const std = @import("std");
const build_capy = @import("build_capy.zig");
pub const runStep = build_capy.runStep;
pub const CapyBuildOptions = build_capy.CapyBuildOptions;
pub const CapyRunOptions = build_capy.CapyRunOptions;
const AndroidSdk = @import("android/Sdk.zig");

const LazyPath = std.Build.LazyPath;

fn installCapyDependencies(b: *std.Build, module: *std.Build.Module, options: CapyBuildOptions) !void {
    const target = module.resolved_target.?;
    const optimize = module.optimize.?;

    // Set up icon data module — uses write-files so the PNG is within the module's package path
    const wf = b.addWriteFiles();
    if (options.icon_path) |icon_path| {
        _ = wf.addCopyFile(b.path(icon_path), "icon.png");
        const icon_module = b.createModule(.{
            .root_source_file = wf.add("icon_data.zig",
                \\pub const data: ?[]const u8 = @embedFile("icon.png");
            ),
        });
        module.addImport("capy_icon_data", icon_module);
    } else {
        const icon_module = b.createModule(.{
            .root_source_file = wf.add("icon_data.zig",
                \\pub const data: ?[]const u8 = null;
            ),
        });
        module.addImport("capy_icon_data", icon_module);
    }

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
        },
        .macos => {
            if (@import("builtin").os.tag != .macos) {
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
                var libraries: std.ArrayList([]const u8) = .empty;
                try libraries.append(b.allocator, "android");
                try libraries.append(b.allocator, "log");
                const config = AndroidSdk.AppConfig{
                    .target_version = options.android_version,
                    .display_name = options.app_name,
                    .app_name = "capyui_example",
                    .package_name = options.android_package_name,
                    .resources = &[_]AndroidSdk.Resource{
                        .{ .path = "mipmap/icon.png", .content = b.path("android/default_icon.png") },
                    },
                    .aaudio = false,
                    .opensl = false,
                    .permissions = &[_][]const u8{
                        "android.permission.SET_RELEASE_APP",
                    },
                    .libraries = libraries.items,
                };
                sdk.configureModule(module, config, .aarch64);
            } else {
                module.link_libc = true;
                module.linkSystemLibrary("gtk4", .{});
            }
        },
        .wasi => {
            if (target.result.cpu.arch.isWasm()) {
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
    const icon_path = b.option([]const u8, "icon", "Path to app icon PNG (square, RGBA)");

    // Icon path fallback: -Dicon > assets/icon.png (if exists)
    const resolved_icon: ?[]const u8 = icon_path orelse blk: {
        if (std.fs.cwd().access(b.pathFromRoot("assets/icon.png"), .{}))
            break :blk "assets/icon.png"
        else |_|
            break :blk null;
    };

    const options = CapyBuildOptions{
        .target = target,
        .optimize = optimize,
        .app_name = app_name orelse "Capy Example",
        .icon_path = resolved_icon,
    };

    const module = b.addModule("capy", .{
        .root_source_file = b.path("src/capy.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{},
    });
    try installCapyDependencies(b, module, options);

    const is_macos = target.result.os.tag == .macos;

    // Pre-generate ICNS data for macOS .app bundles (read icon PNG once, wrap in ICNS header)
    const icns_data: ?[]const u8 = if (is_macos) blk: {
        if (resolved_icon) |icon_rel| {
            const file = try std.fs.cwd().openFile(b.pathFromRoot(icon_rel), .{});
            defer file.close();
            const png_data = try file.readToEndAlloc(b.allocator, 10 * 1024 * 1024);
            break :blk try build_capy.generateIcns(b.allocator, png_data);
        }
        break :blk null;
    } else null;

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

            const programPath = b.path(b.pathJoin(&.{ "examples", entry.path }));

            const exe = b.addExecutable(.{
                .name = name,
                .root_module = b.createModule(.{
                    .root_source_file = programPath,
                    .target = target,
                    .optimize = optimize,
                }),
            });
            exe.root_module.addImport("capy", module);

            const is_working = blk: {
                for (broken) |broken_name| {
                    if (std.mem.eql(u8, name, broken_name))
                        break :blk false;
                }
                break :blk true;
            };

            // macOS: create .app bundle; other platforms: install bare binary
            if (is_macos) {
                const exe_install = b.addInstallArtifact(exe, .{
                    .dest_dir = .{ .override = .{ .custom = b.fmt("bin/{s}.app/Contents/MacOS", .{name}) } },
                });

                const bundle_wf = b.addWriteFiles();
                const plist = try build_capy.generateInfoPlist(
                    b.allocator,
                    app_name orelse name,
                    name,
                    icns_data != null,
                );
                _ = bundle_wf.add(b.fmt("{s}.app/Contents/Info.plist", .{name}), plist);

                if (icns_data) |icns| {
                    _ = bundle_wf.add(b.fmt("{s}.app/Contents/Resources/app.icns", .{name}), icns);
                }

                const bundle_install = b.addInstallDirectory(.{
                    .source_dir = bundle_wf.getDirectory(),
                    .install_dir = .bin,
                    .install_subdir = "",
                });

                if (is_working) {
                    b.getInstallStep().dependOn(&exe_install.step);
                    b.getInstallStep().dependOn(&bundle_install.step);
                }
            } else {
                const install_step = b.addInstallArtifact(exe, .{});
                if (is_working) {
                    b.getInstallStep().dependOn(&install_step.step);
                }
            }

            const run_cmd = try runStep(exe, .{});

            const run_step = b.step(name, "Run this example");
            run_step.dependOn(run_cmd);
        }
    }

    const lib = b.addLibrary(.{
        .linkage = .dynamic,
        .name = "capy",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/c_api.zig"),
            .target = target,
            .optimize = optimize,
        }),
        .version = std.SemanticVersion{ .major = 0, .minor = 4, .patch = 0 },
    });
    lib.linkLibC();
    lib.root_module.addImport("capy", module);
    const lib_install = b.addInstallArtifact(lib, .{});
    b.getInstallStep().dependOn(&lib_install.step);

    const buildc_step = b.step("shared", "Build capy as a shared library (with C ABI)");
    buildc_step.dependOn(&lib_install.step);

    //
    // Unit tests
    //
    const tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/capy.zig"),
            .target = target,
            .optimize = optimize,
        }),
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
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/capy.zig"),
            .target = target,
            .optimize = .Debug,
        }),
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
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/capy.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    coverage_tests.setExecCmd(&.{ "kcov", "--clean", "--include-pattern=src/", "kcov-output", null });
    try installCapyDependencies(b, coverage_tests.root_module, options);

    const run_coverage_tests = b.addSystemCommand(&.{ "kcov", "--clean", "--include-pattern=src/", "kcov-output" });
    run_coverage_tests.addArtifactArg(coverage_tests);

    const cov_step = b.step("coverage", "Perform code coverage of unit tests. This requires 'kcov' to be installed.");
    cov_step.dependOn(&run_coverage_tests.step);
}
