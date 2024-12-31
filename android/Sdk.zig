//! External dependencies:
//! - `keytool` from OpenJDK
//! - `apksigner`, `aapt`, `zipalign`, and `adb` from the Android tools package

const std = @import("std");
const builtin = @import("builtin");

const auto_detect = @import("build/auto-detect.zig");

fn sdkRootIntern() []const u8 {
    return std.fs.path.dirname(@src().file) orelse ".";
}

fn sdkRoot() *const [sdkRootIntern().len]u8 {
    comptime var buffer = sdkRootIntern();
    return buffer[0..buffer.len];
}

// linux-x86_64
pub fn toolchainHostTag() []const u8 {
    const os = builtin.os.tag;
    const arch = builtin.cpu.arch;
    return @tagName(os) ++ "-" ++ @tagName(arch);
}

/// This file encodes a instance of an Android SDK interface.
const Sdk = @This();

/// The builder instance associated with this object.
b: *Builder,

/// A set of tools that run on the build host that are required to complete the
/// project build. Must be created with the `hostTools()` function that passes in
/// the correct relpath to the package.
host_tools: HostTools,

/// The configuration for all non-shipped system tools.
/// Contains the normal default config for each tool.
system_tools: SystemTools = .{},

/// Contains paths to each required input folder.
folders: UserConfig,

versions: ToolchainVersions,

launch_using: ADBLaunchMethod = .monkey,

pub const ADBLaunchMethod = enum {
    monkey,
    am,
};

/// Initializes the android SDK.
/// It requires some input on which versions of the tool chains should be used
pub fn init(b: *Builder, user_config: ?UserConfig, toolchains: ToolchainVersions) *Sdk {
    const actual_user_config_err = user_config orelse auto_detect.findUserConfig(b, toolchains);
    const actual_user_config = actual_user_config_err catch |err| @panic(@errorName(err));
    // const actual_user_config = user_config orelse auto_detect.findUserConfig(b, toolchains) catch |err| @panic(@errorName(err));

    const system_tools = blk: {
        const exe = if (builtin.os.tag == .windows) ".exe" else "";
        const bat = if (builtin.os.tag == .windows) ".bat" else "";

        const zipalign = std.fs.path.join(b.allocator, &[_][]const u8{ actual_user_config.android_sdk_root, "build-tools", toolchains.build_tools_version, "zipalign" ++ exe }) catch unreachable;
        const aapt = std.fs.path.join(b.allocator, &[_][]const u8{ actual_user_config.android_sdk_root, "build-tools", toolchains.build_tools_version, "aapt" ++ exe }) catch unreachable;
        const d8 = std.fs.path.join(b.allocator, &[_][]const u8{ actual_user_config.android_sdk_root, "build-tools", toolchains.build_tools_version, "d8" ++ exe }) catch unreachable;
        const adb = blk1: {
            const adb_sdk = std.fs.path.join(b.allocator, &[_][]const u8{ actual_user_config.android_sdk_root, "platform-tools", "adb" ++ exe }) catch unreachable;
            if (!auto_detect.fileExists(adb_sdk)) {
                break :blk1 auto_detect.findProgramPath(b.allocator, "adb") orelse @panic("No adb found");
            }
            break :blk1 adb_sdk;
        };
        const apksigner = std.fs.path.join(b.allocator, &[_][]const u8{ actual_user_config.android_sdk_root, "build-tools", toolchains.build_tools_version, "apksigner" ++ bat }) catch unreachable;
        const keytool = std.fs.path.join(b.allocator, &[_][]const u8{ actual_user_config.java_home, "bin", "keytool" ++ exe }) catch unreachable;
        const javac = std.fs.path.join(b.allocator, &[_][]const u8{ actual_user_config.java_home, "bin", "javac" ++ exe }) catch unreachable;

        break :blk SystemTools{
            .zipalign = zipalign,
            .aapt = aapt,
            .adb = adb,
            .apksigner = apksigner,
            .keytool = keytool,
            .javac = javac,
            .d8 = d8,
        };
    };

    // Compiles all required additional tools for toolchain.
    const host_tools = blk: {
        const zip_add = b.addExecutable(.{
            .name = "zip_add",
            .root_source_file = b.path(sdkRoot() ++ "/tools/zip_add.zig"),
            .target = b.resolveTargetQuery(.{}),
        });
        zip_add.addCSourceFile(.{
            .file = b.path(sdkRoot() ++ "/vendor/kuba-zip/zip.c"),
            .flags = &[_][]const u8{
                "-std=c99",
                "-fno-sanitize=undefined",
                "-D_POSIX_C_SOURCE=200112L",
            },
        });
        zip_add.addIncludePath(b.path(sdkRoot() ++ "/vendor/kuba-zip"));
        zip_add.linkLibC();

        break :blk HostTools{
            .zip_add = zip_add,
        };
    };

    const sdk = b.allocator.create(Sdk) catch @panic("out of memory");
    sdk.* = Sdk{
        .b = b,
        .host_tools = host_tools,
        .system_tools = system_tools,
        .folders = actual_user_config,
        .versions = toolchains,
    };
    return sdk;
}

pub const ToolchainVersions = struct {
    build_tools_version: []const u8 = "33.0.1",
    ndk_version: []const u8 = "25.1.8937393",
};

pub const AndroidVersion = enum(u16) {
    android4 = 19, // KitKat
    android5 = 21, // Lollipop
    android6 = 23, // Marshmallow
    android7 = 24, // Nougat
    android8 = 26, // Oreo
    android9 = 28, // Pie
    android10 = 29, // Quince Tart
    android11 = 30, // Red Velvet Cake
    android12 = 31, // Snow Cone
    android13 = 33, // Tiramisu
    android14 = 34, // Upside Down Cake
    android15 = 35, // Vanilla Ice Cream

    _, // we allow to overwrite the defaults
};

pub const UserConfig = struct {
    android_sdk_root: []const u8 = "",
    android_ndk_root: []const u8 = "",
    java_home: []const u8 = "",
};

/// Configuration of the Android toolchain.
pub const Config = struct {
    /// Path to the SDK root folder.
    /// Example: `/home/ziggy/android-sdk`.
    sdk_root: []const u8,

    /// Path to the NDK root folder.
    /// Example: `/home/ziggy/android-sdk/ndk/21.1.6352462`.
    ndk_root: []const u8,

    /// Path to the build tools folder.
    /// Example: `/home/ziggy/android-sdk/build-tools/28.0.3`.
    build_tools: []const u8,

    /// A key store. This is required when an APK is created and signed.
    /// If you don't care for production code, just use the default here
    /// and it will work. This needs to be changed to a *proper* key store
    /// when you want to publish the app.
    key_store: KeyStore = KeyStore{
        .file = ".zig-cache/",
        .alias = "default",
        .password = "ziguana",
    },
};

/// A resource that will be packed into the appliation.
pub const Resource = struct {
    /// This is the relative path to the resource root
    path: []const u8,
    /// This is the content of the file.
    content: std.Build.LazyPath,
};

/// Configuration of an application.
pub const AppConfig = struct {
    /// The display name of the application. This is shown to the users.
    display_name: []const u8,

    /// Application name, only lower case letters and underscores are allowed.
    app_name: []const u8,

    /// Java package name, usually the reverse top level domain + app name.
    /// Only lower case letters, dots and underscores are allowed.
    package_name: []const u8,

    /// The android version which is embedded in the manifset.
    /// The default is Android 9, it's more than 4 years old by now and should be widespread enough
    /// to be a reasonable default.
    target_version: AndroidVersion = .android9,

    /// The resource directory that will contain the manifest and other app resources.
    /// This should be a distinct directory per app.
    resources: []const Resource = &[_]Resource{},

    /// If true, the app will be started in "fullscreen" mode, this means that
    /// navigation buttons as well as the top bar are not shown.
    /// This is usually relevant for games.
    fullscreen: bool = false,

    /// If true, the app will be compiled with the AAudio library.
    aaudio: bool = false,

    /// If true, the app will be compiled with the OpenSL library
    opensl: bool = true,

    /// One or more asset directories. Each directory will be added into the app assets.
    asset_directories: []const []const u8 = &[_][]const u8{},

    permissions: []const []const u8 = &[_][]const u8{
        //"android.permission.SET_RELEASE_APP",
        //"android.permission.RECORD_AUDIO",
    },

    libraries: []const []const u8 = &app_libs,
};

pub const TargetConfig = struct {
    lib_dir: []const u8,
    include_dir: []const u8,
    out_dir: []const u8,
    target: std.Target.Query,
};

/// One of the legal targets android can be built for.
pub const Target = enum {
    aarch64,
    arm,
    x86,
    x86_64,

    pub fn getTargetConfig(self: Target) TargetConfig {
        const config: TargetConfig = switch (self) {
            .aarch64 => TargetConfig{
                .lib_dir = "aarch64-linux-android",
                .include_dir = "aarch64-linux-android",
                .out_dir = "arm64",
                .target = zig_targets.aarch64,
            },
            .arm => TargetConfig{
                .lib_dir = "arm-linux-androideabi",
                .include_dir = "arm-linux-androideabi",
                .out_dir = "armeabi",
                .target = zig_targets.arm,
            },
            .x86 => TargetConfig{
                .lib_dir = "i686-linux-android",
                .include_dir = "i686-linux-android",
                .out_dir = "x86",
                .target = zig_targets.x86,
            },
            .x86_64 => TargetConfig{
                .lib_dir = "x86_64-linux-android",
                .include_dir = "x86_64-linux-android",
                .out_dir = "x86_64",
                .target = zig_targets.x86_64,
            },
        };
        return config;
    }
};

pub const KeyStore = struct {
    file: []const u8,
    alias: []const u8,
    password: []const u8,
};

pub const HostTools = struct {
    zip_add: *std.Build.Step.Compile,
};

/// Configuration of the binary paths to all tools that are not included in the android SDK.
pub const SystemTools = struct {
    mkdir: []const u8 = "mkdir",
    rm: []const u8 = "rm",

    zipalign: []const u8 = "zipalign",
    aapt: []const u8 = "aapt",
    adb: []const u8 = "adb",
    apksigner: []const u8 = "apksigner",
    keytool: []const u8 = "keytool",
    javac: []const u8 = "javac",
    d8: []const u8 = "d8",
};

/// The configuration which targets a app should be built for.
pub const AppTargetConfig = struct {
    aarch64: ?bool = null,
    arm: ?bool = null,
    x86_64: ?bool = null,
    x86: ?bool = null,
};

pub const CreateAppStep = struct {
    sdk: *Sdk,
    first_step: *std.Build.Step,
    final_step: *std.Build.Step,

    libraries: []const *std.Build.Step.Compile,
    build_options: *BuildOptionStep,

    apk_file: std.Build.LazyPath,

    package_name: []const u8,

    pub fn getAndroidPackage(self: @This(), name: []const u8) std.Build.Pkg {
        return self.sdk.b.dupePkg(std.Build.Pkg{
            .name = name,
            .source = self.sdk.b.path(sdkRoot() ++ "/src/android-support.zig"),
            .dependencies = &[_]std.Build.Pkg{
                self.build_options.getPackage("build_options"),
            },
        });
    }

    pub fn install(self: @This()) *Step {
        return self.sdk.installApp(self.apk_file);
    }

    pub fn run(self: @This()) *Step {
        return self.sdk.startApp(self.package_name);
    }
};

const NdkVersionRange = struct {
    ndk: []const u8,
    min: u16,
    max: u16,

    pub fn validate(range: []const NdkVersionRange, ndk: []const u8, api: u16) void {
        const ndk_version = std.SemanticVersion.parse(ndk) catch {
            std.debug.print("Could not parse NDK version {s} as semantic version. Could not perform NDK validation!\n", .{ndk});
            return;
        };
        std.debug.assert(range.len > 0);

        for (range) |vers| {
            const r_version = std.SemanticVersion.parse(vers.ndk) catch unreachable;
            if (ndk_version.order(r_version) == .eq) {
                // Perfect version match
                if (api < vers.min) {
                    std.debug.print("WARNING: Selected NDK {s} does not support api level {d}. Minimum supported version is {d}!\n", .{
                        ndk,
                        api,
                        vers.min,
                    });
                }
                if (api > vers.max) {
                    std.debug.print("WARNING: Selected NDK {s} does not support api level {d}. Maximum supported version is {d}!\n", .{
                        ndk,
                        api,
                        vers.max,
                    });
                }
            }
            return;
        }

        // NDK old    X => min=5, max=8
        // NDK now    Y => api=7
        // NDK future Z => min=6, max=13

        var older_version: NdkVersionRange = range[0]; // biggest Y <= X
        for (range[1..]) |vers| {
            const r_version = std.SemanticVersion.parse(vers.ndk) catch unreachable;
            if (r_version.order(ndk_version) != .gt) { // r_version <= ndk_version
                older_version = vers;
            } else {
                // range is ordered, so we know that we can't find anything smaller now anyways
                break;
            }
        }
        var newer_version: NdkVersionRange = range[range.len - 1]; // smallest Z >= X
        for (range[1..]) |vers| {
            const r_version = std.SemanticVersion.parse(vers.ndk) catch unreachable;
            if (r_version.order(ndk_version) != .lt) {
                newer_version = vers;
                break;
            }
        }

        // take for max api, as we assume that an older NDK than Z might not support Z.max yet
        if (api < newer_version.min) {
            std.debug.print("WARNING: Selected NDK {s} might not support api level {d}. Minimum supported version is guessed as {d}, as NDK {s} only supports that!\n", .{
                ndk,
                api,
                newer_version.min,
                newer_version.ndk,
            });
        }
        // take for min api, as we assume that a newer NDK than X might not support X.min anymore
        if (api > older_version.max) {
            std.debug.print("WARNING: Selected NDK {s} might not support api level {d}. Maximum supported version is guessed as {d}, as NDK {s} only supports that!\n", .{
                ndk,
                api,
                older_version.max,
                older_version.ndk,
            });
        }
    }
};

// ls ~/software/android-sdk/ndk/*/toolchains/llvm/prebuilt/${hosttag}/sysroot/usr/lib/arm-linux-androideabi | code
const arm_ndk_ranges = [_]NdkVersionRange{
    NdkVersionRange{ .ndk = "19.2.5345600", .min = 16, .max = 28 },
    NdkVersionRange{ .ndk = "20.1.5948944", .min = 16, .max = 29 },
    NdkVersionRange{ .ndk = "21.4.7075529", .min = 16, .max = 30 },
    NdkVersionRange{ .ndk = "22.1.7171670", .min = 16, .max = 30 },
    NdkVersionRange{ .ndk = "23.2.8568313", .min = 16, .max = 31 },
    NdkVersionRange{ .ndk = "24.0.8215888", .min = 19, .max = 32 },
    NdkVersionRange{ .ndk = "25.1.8937393", .min = 19, .max = 33 },
};

// ls ~/software/android-sdk/ndk/*/toolchains/llvm/prebuilt/${hosttag}/sysroot/usr/lib/i686* | code
const i686_ndk_ranges = [_]NdkVersionRange{
    NdkVersionRange{ .ndk = "19.2.5345600", .min = 16, .max = 28 },
    NdkVersionRange{ .ndk = "20.1.5948944", .min = 16, .max = 29 },
    NdkVersionRange{ .ndk = "21.4.7075529", .min = 16, .max = 30 },
    NdkVersionRange{ .ndk = "22.1.7171670", .min = 16, .max = 30 },
    NdkVersionRange{ .ndk = "23.2.8568313", .min = 16, .max = 31 },
    NdkVersionRange{ .ndk = "24.0.8215888", .min = 19, .max = 32 },
    NdkVersionRange{ .ndk = "25.1.8937393", .min = 19, .max = 33 },
};

// ls ~/software/android-sdk/ndk/*/toolchains/llvm/prebuilt/${hosttag}/sysroot/usr/lib/x86_64-linux-android | code
const x86_64_ndk_ranges = [_]NdkVersionRange{
    NdkVersionRange{ .ndk = "19.2.5345600", .min = 21, .max = 28 },
    NdkVersionRange{ .ndk = "20.1.5948944", .min = 21, .max = 29 },
    NdkVersionRange{ .ndk = "21.4.7075529", .min = 21, .max = 30 },
    NdkVersionRange{ .ndk = "22.1.7171670", .min = 21, .max = 30 },
    NdkVersionRange{ .ndk = "23.2.8568313", .min = 21, .max = 31 },
    NdkVersionRange{ .ndk = "24.0.8215888", .min = 21, .max = 32 },
    NdkVersionRange{ .ndk = "25.1.8937393", .min = 21, .max = 33 },
};

// ls ~/software/android-sdk/ndk/*/toolchains/llvm/prebuilt/${hosttag}/sysroot/usr/lib/aarch64-linux-android | code
const aarch64_ndk_ranges = [_]NdkVersionRange{
    NdkVersionRange{ .ndk = "19.2.5345600", .min = 21, .max = 28 },
    NdkVersionRange{ .ndk = "20.1.5948944", .min = 21, .max = 29 },
    NdkVersionRange{ .ndk = "21.4.7075529", .min = 21, .max = 30 },
    NdkVersionRange{ .ndk = "22.1.7171670", .min = 21, .max = 30 },
    NdkVersionRange{ .ndk = "23.2.8568313", .min = 21, .max = 31 },
    NdkVersionRange{ .ndk = "24.0.8215888", .min = 21, .max = 32 },
    NdkVersionRange{ .ndk = "25.1.8937393", .min = 21, .max = 33 },
};

/// Instantiates the full build pipeline to create an APK file.
///
pub fn createApp(
    sdk: *Sdk,
    apk_filename: []const u8,
    src_file: []const u8,
    java_files_opt: ?[]const []const u8,
    app_config: AppConfig,
    mode: std.builtin.Mode,
    wanted_targets: AppTargetConfig,
    key_store: KeyStore,
) CreateAppStep {
    const write_xml_step = sdk.b.addWriteFiles();
    const write_xml_file_source = write_xml_step.add("strings.xml", blk: {
        var buf = std.ArrayList(u8).init(sdk.b.allocator);
        errdefer buf.deinit();

        var writer = buf.writer();

        writer.writeAll(
            \\<?xml version="1.0" encoding="utf-8"?>
            \\<resources>
            \\
        ) catch unreachable;

        writer.print(
            \\    <string name="app_name">{s}</string>
            \\    <string name="lib_name">{s}</string>
            \\    <string name="package_name">{s}</string>
            \\
        , .{
            app_config.display_name,
            app_config.app_name,
            app_config.package_name,
        }) catch unreachable;

        writer.writeAll(
            \\</resources>
            \\
        ) catch unreachable;

        break :blk buf.toOwnedSlice() catch unreachable;
    });

    const manifest_step = sdk.b.addWriteFiles();
    const manifest_file_source = manifest_step.add("AndroidManifest.xml", blk: {
        var buf = std.ArrayList(u8).init(sdk.b.allocator);
        errdefer buf.deinit();

        var writer = buf.writer();

        @setEvalBranchQuota(1_000_000);
        writer.print(
            \\<?xml version="1.0" encoding="utf-8" standalone="no"?><manifest xmlns:tools="http://schemas.android.com/tools" xmlns:android="http://schemas.android.com/apk/res/android" package="{s}">
            \\
        , .{app_config.package_name}) catch unreachable;
        for (app_config.permissions) |perm| {
            writer.print(
                \\    <uses-permission android:name="{s}"/>
                \\
            , .{perm}) catch unreachable;
        }

        const theme = if (app_config.fullscreen)
            \\android:theme="@android:style/Theme.NoTitleBar.Fullscreen"
        else
            \\
            ;

        writer.print(
            \\    <application android:debuggable="true" android:hasCode="{[hasCode]}" android:label="@string/app_name" {[theme]s} tools:replace="android:icon,android:theme,android:allowBackup,label" android:icon="@mipmap/icon" >
            \\        <activity android:configChanges="keyboardHidden|orientation" android:name="android.app.NativeActivity">
            \\            <meta-data android:name="android.app.lib_name" android:value="@string/lib_name"/>
            \\            <intent-filter>
            \\                <action android:name="android.intent.action.MAIN"/>
            \\                <category android:name="android.intent.category.LAUNCHER"/>
            \\            </intent-filter>
            \\        </activity>
            \\    </application>
            \\</manifest>
            \\
        , .{
            .hasCode = java_files_opt != null,
            .theme = theme,
        }) catch unreachable;

        break :blk buf.toOwnedSlice() catch unreachable;
    });

    const resource_dir_step = CreateResourceDirectory.create(sdk.b);
    for (app_config.resources) |res| {
        resource_dir_step.add(res);
    }
    resource_dir_step.add(Resource{
        .path = "values/strings.xml",
        .content = write_xml_file_source,
    });

    const sdk_version_int = @intFromEnum(app_config.target_version);

    if (sdk_version_int < 16) @panic("Minimum supported sdk version is 16.");

    const targets = AppTargetConfig{
        .aarch64 = wanted_targets.aarch64 orelse (sdk_version_int >= 21),
        .x86_64 = wanted_targets.x86_64 orelse (sdk_version_int >= 21),
        .x86 = wanted_targets.x86 orelse (sdk_version_int >= 16),
        .arm = wanted_targets.arm orelse (sdk_version_int >= 16),
    };

    // These are hard assumptions
    if (targets.aarch64.? and sdk_version_int < 21) @panic("Aarch64 android is only available since sdk version 21.");
    if (targets.x86_64.? and sdk_version_int < 21) @panic("x86_64 android is only available since sdk version 21.");
    if (targets.x86.? and sdk_version_int < 16) @panic("x86 android is only available since sdk version 16.");
    if (targets.arm.? and sdk_version_int < 16) @panic("arm android is only available since sdk version 16.");

    // Also perform a soft check for known NDK versions
    if (targets.aarch64.?) NdkVersionRange.validate(&aarch64_ndk_ranges, sdk.versions.ndk_version, sdk_version_int);
    if (targets.x86_64.?) NdkVersionRange.validate(&x86_64_ndk_ranges, sdk.versions.ndk_version, sdk_version_int);
    if (targets.x86.?) NdkVersionRange.validate(&x86_64_ndk_ranges, sdk.versions.ndk_version, sdk_version_int);
    if (targets.arm.?) NdkVersionRange.validate(&arm_ndk_ranges, sdk.versions.ndk_version, sdk_version_int);

    const root_jar = std.fs.path.resolve(sdk.b.allocator, &[_][]const u8{
        sdk.folders.android_sdk_root,
        "platforms",
        sdk.b.fmt("android-{d}", .{sdk_version_int}),
        "android.jar",
    }) catch unreachable;

    const unaligned_apk_name = sdk.b.fmt("unaligned-{s}", .{std.fs.path.basename(apk_filename)});

    const make_unsigned_apk = sdk.b.addSystemCommand(&[_][]const u8{
        sdk.system_tools.aapt,
        "package",
        "-f", // force overwrite of existing files
        "-I", // add an existing package to base include set
        root_jar,
        "-F", // specify the apk file to output
    });
    const unaligned_apk_file = make_unsigned_apk.addOutputFileArg(unaligned_apk_name);

    make_unsigned_apk.addArg("-M"); // specify full path to AndroidManifest.xml to include in zip
    make_unsigned_apk.addFileArg(manifest_file_source);

    make_unsigned_apk.addArg("-S"); // directory in which to find resources.  Multiple directories will be scanned and the first match found (left to right) will take precedence
    make_unsigned_apk.addDirectorySourceArg(resource_dir_step.getOutputDirectory());

    make_unsigned_apk.addArgs(&[_][]const u8{
        "-v",
        "--target-sdk-version",
        sdk.b.fmt("{d}", .{sdk_version_int}),
    });
    for (app_config.asset_directories) |dir| {
        make_unsigned_apk.addArg("-A"); // additional directory in which to find raw asset files
        make_unsigned_apk.addArg(sdk.b.pathFromRoot(dir));
    }

    const copy_to_zip_step = WriteToZip.init(sdk, unaligned_apk_file, unaligned_apk_name);
    copy_to_zip_step.run_step.step.dependOn(&make_unsigned_apk.step);

    var libs = std.ArrayList(*std.Build.Step.Compile).init(sdk.b.allocator);
    defer libs.deinit();

    const build_options = BuildOptionStep.create(sdk.b);
    build_options.add([]const u8, "app_name", app_config.app_name);
    build_options.add(u16, "android_sdk_version", sdk_version_int);
    build_options.add(bool, "fullscreen", app_config.fullscreen);
    build_options.add(bool, "enable_aaudio", app_config.aaudio);
    build_options.add(bool, "enable_opensl", app_config.opensl);

    const android_module = sdk.b.addModule("android", .{
        .root_source_file = sdk.b.path("android/src/android-support.zig"),
        .imports = &.{.{
            .name = "build_options",
            .module = build_options.getModule(),
        }},
    });
    _ = android_module;

    const align_step = sdk.b.addSystemCommand(&[_][]const u8{
        sdk.system_tools.zipalign,
        "-p", // ensure shared libraries are aligned to 4KiB
        "-f", // overwrite existing files
        "-v", // verbose
        "4",
    });
    align_step.addFileArg(copy_to_zip_step.output_source);
    align_step.step.dependOn(&make_unsigned_apk.step);
    const apk_file = align_step.addOutputFileArg(apk_filename);

    const apk_install = sdk.b.addInstallBinFile(apk_file, apk_filename);
    sdk.b.getInstallStep().dependOn(&apk_install.step);

    const java_dir = sdk.b.getInstallPath(.lib, "java");
    if (java_files_opt) |java_files| {
        const d8_cmd_builder = sdk.b.addSystemCommand(&[_][]const u8{sdk.system_tools.d8});

        d8_cmd_builder.addArg("--lib");
        d8_cmd_builder.addArg(root_jar);

        for (java_files) |java_file| {
            const javac_cmd = sdk.b.addSystemCommand(&[_][]const u8{
                sdk.system_tools.javac,
                "-cp",
                root_jar,
                "-d",
                java_dir,
            });
            javac_cmd.addFileArg(sdk.b.path(java_file));

            const name = std.fs.path.stem(java_file);
            const name_ext = sdk.b.fmt("{s}.class", .{name});
            const class_file = std.fs.path.resolve(sdk.b.allocator, &[_][]const u8{ java_dir, name_ext }) catch unreachable;

            d8_cmd_builder.addFileArg(sdk.b.path(class_file));
            d8_cmd_builder.step.dependOn(&javac_cmd.step);
        }

        d8_cmd_builder.addArg("--classpath");
        d8_cmd_builder.addArg(java_dir);
        d8_cmd_builder.addArg("--output");
        d8_cmd_builder.addArg(java_dir);
        // make_unsigned_apk.step.dependOn(&d8_cmd_builder.step);
        d8_cmd_builder.step.dependOn(&make_unsigned_apk.step);

        const dex_file = std.fs.path.resolve(sdk.b.allocator, &[_][]const u8{ java_dir, "classes.dex" }) catch unreachable;
        // make_unsigned_apk.addArg("-I");
        // make_unsigned_apk.addArg(dex_file);
        copy_to_zip_step.addFile(sdk.b.path(dex_file), "classes.dex");
        copy_to_zip_step.run_step.step.dependOn(&d8_cmd_builder.step);
        copy_to_zip_step.run_step.step.dependOn(&make_unsigned_apk.step); // enforces creation of APK before the execution
        align_step.step.dependOn(&copy_to_zip_step.run_step.step);
    }

    // const sign_step = sdk.signApk(apk_filename, key_store);
    const sign_step = sdk.b.addSystemCommand(&[_][]const u8{
        sdk.system_tools.apksigner,
        "sign",
        "--ks", // keystore
        key_store.file,
    });
    sign_step.step.dependOn(&align_step.step);
    {
        const pass = sdk.b.fmt("pass:{s}", .{key_store.password});
        sign_step.addArgs(&.{ "--ks-pass", pass });
        sign_step.addFileArg(apk_file);
    }

    inline for (std.meta.fields(AppTargetConfig)) |fld| {
        const target_name = @field(Target, fld.name);
        if (@field(targets, fld.name).?) {
            const step = sdk.compileAppLibrary(
                src_file,
                app_config,
                mode,
                target_name,
                //   build_options.getPackage("build_options"),
            );
            libs.append(step) catch unreachable;

            // https://developer.android.com/ndk/guides/abis#native-code-in-app-packages
            const so_dir = switch (target_name) {
                .aarch64 => "lib/arm64-v8a/",
                .arm => "lib/armeabi-v7a/",
                .x86_64 => "lib/x86_64/",
                .x86 => "lib/x86/",
            };

            const target_filename = sdk.b.fmt("{s}lib{s}.so", .{ so_dir, app_config.app_name });

            copy_to_zip_step.addFile(step.getEmittedBin(), target_filename);
            copy_to_zip_step.run_step.step.dependOn(&step.step);
            align_step.step.dependOn(&copy_to_zip_step.run_step.step);
        }
    }

    // const compress_step = compressApk(b, android_config, apk_file, "zig-out/demo.packed.apk");
    // compress_step.dependOn(sign_step);

    return CreateAppStep{
        .sdk = sdk,
        .first_step = &make_unsigned_apk.step,
        .final_step = &sign_step.step,
        .libraries = libs.toOwnedSlice() catch unreachable,
        .build_options = build_options,
        .package_name = sdk.b.dupe(app_config.package_name),
        .apk_file = apk_file.dupe(sdk.b),
    };
}

const CreateResourceDirectory = struct {
    const Self = @This();
    builder: *std.Build,
    step: std.Build.Step,

    resources: std.ArrayList(Resource),
    directory: std.Build.GeneratedFile,

    pub fn create(b: *std.Build) *Self {
        const self = b.allocator.create(Self) catch @panic("out of memory");
        self.* = Self{
            .builder = b,
            .step = Step.init(.{
                .id = .custom,
                .name = "populate resource directory",
                .owner = b,
                .makeFn = CreateResourceDirectory.make,
            }),
            .directory = .{ .step = &self.step },
            .resources = std.ArrayList(Resource).init(b.allocator),
        };
        return self;
    }

    pub fn add(self: *Self, resource: Resource) void {
        self.resources.append(Resource{
            .path = self.builder.dupe(resource.path),
            .content = resource.content.dupe(self.builder),
        }) catch @panic("out of memory");
        resource.content.addStepDependencies(&self.step);
    }

    pub fn getOutputDirectory(self: *Self) std.Build.LazyPath {
        return .{ .generated = .{ .file = &self.directory } };
    }

    fn make(step: *Step, progress: std.Progress.Node) !void {
        _ = progress;
        const self: *Self = @fieldParentPtr("step", step);

        // if (std.fs.path.dirname(strings_xml)) |dir| {
        //     std.fs.cwd().makePath(dir) catch unreachable;
        // }

        var cacher = createCacheBuilder(self.builder);
        for (self.resources.items) |res| {
            cacher.addBytes(res.path);
            try cacher.addFile(res.content);
        }

        const root = try cacher.createAndGetDir();
        for (self.resources.items) |res| {
            if (std.fs.path.dirname(res.path)) |folder| {
                try root.dir.makePath(folder);
            }

            const src_path = res.content.getPath(self.builder);
            try std.fs.Dir.copyFile(
                std.fs.cwd(),
                src_path,
                root.dir,
                res.path,
                .{},
            );
        }

        self.directory.path = root.path;
    }
};

fn run_copy_to_zip(sdk: *Sdk, input_file: std.Build.LazyPath, apk_file: std.Build.LazyPath, target_file: []const u8) *std.Build.RunStep {
    const run_cp = sdk.b.addRunArtifact(sdk.host_tools.zip_add);

    run_cp.addFileArg(apk_file);
    run_cp.addFileArg(input_file);
    run_cp.addArg(target_file);

    return run_cp;
}

const WriteToZip = struct {
    output_source: std.Build.LazyPath,
    run_step: *std.Build.Step.Run,

    pub fn init(sdk: *Sdk, zip_file: std.Build.LazyPath, out_name: []const u8) WriteToZip {
        const run_cp = sdk.b.addRunArtifact(sdk.host_tools.zip_add);

        run_cp.addFileArg(zip_file);
        const output_source = run_cp.addOutputFileArg(out_name);

        return WriteToZip{
            .output_source = output_source,
            .run_step = run_cp,
        };
    }

    pub fn addFile(step: *const WriteToZip, input_file: std.Build.LazyPath, target_file: []const u8) void {
        step.run_step.addFileArg(input_file);
        step.run_step.addArg(target_file);
    }
};

// Note that this function must be accompanied by `configureStep`
pub fn configureModule(
    sdk: *const Sdk,
    module: *std.Build.Module,
    app_config: AppConfig,
    target: Target,
) void {
    const ndk_root = sdk.b.pathFromRoot(sdk.folders.android_ndk_root);

    const config = target.getTargetConfig();
    const lib_dir = sdk.b.fmt("{s}/toolchains/llvm/prebuilt/{s}/sysroot/usr/lib/{s}/{d}/", .{
        ndk_root,
        toolchainHostTag(),
        config.lib_dir,
        @intFromEnum(app_config.target_version),
    });

    const include_dir = std.fs.path.resolve(sdk.b.allocator, &[_][]const u8{
        ndk_root,
        "toolchains",
        "llvm",
        "prebuilt",
        toolchainHostTag(),
        "sysroot",
        "usr",
        "include",
    }) catch unreachable;
    const system_include_dir = std.fs.path.resolve(sdk.b.allocator, &[_][]const u8{ include_dir, config.include_dir }) catch unreachable;

    module.resolved_target = sdk.b.resolveTargetQuery(config.target);
    module.addCMacro("ANDROID", "1");
    module.link_libc = true;
    module.strip = (module.optimize orelse .Debug) == .ReleaseSmall;

    for (app_config.libraries) |lib| {
        module.linkSystemLibrary(lib, .{ .use_pkg_config = .no });
    }

    module.addLibraryPath(sdk.b.path(lib_dir));

    module.addIncludePath(sdk.b.path(include_dir));
    module.addIncludePath(sdk.b.path(system_include_dir));
}

pub fn configureStep(
    sdk: *const Sdk,
    exe: *std.Build.Step.Compile,
    app_config: AppConfig,
    target: Target,
) void {
    const ndk_root = sdk.b.pathFromRoot(sdk.folders.android_ndk_root);

    const config = target.getTargetConfig();
    const lib_dir = sdk.b.fmt("{s}/toolchains/llvm/prebuilt/{s}/sysroot/usr/lib/{s}/{d}/", .{
        ndk_root,
        toolchainHostTag(),
        config.lib_dir,
        @intFromEnum(app_config.target_version),
    });

    const include_dir = std.fs.path.resolve(sdk.b.allocator, &[_][]const u8{
        ndk_root,
        "toolchains",
        "llvm",
        "prebuilt",
        toolchainHostTag(),
        "sysroot",
        "usr",
        "include",
    }) catch unreachable;
    const system_include_dir = std.fs.path.resolve(sdk.b.allocator, &[_][]const u8{ include_dir, config.include_dir }) catch unreachable;

    configureModule(sdk, exe.root_module, app_config, target);
    exe.link_emit_relocs = true;
    exe.link_eh_frame_hdr = true;
    exe.root_module.pic = true;
    exe.link_function_sections = true;
    exe.bundle_compiler_rt = true;
    exe.export_table = true;

    exe.setLibCFile(sdk.createLibCFile(app_config.target_version, config.out_dir, include_dir, system_include_dir, lib_dir) catch unreachable);
    exe.libc_file.?.addStepDependencies(&exe.step);

    // TODO: Remove when https://github.com/ziglang/zig/issues/7935 is resolved:
    if (exe.rootModuleTarget().cpu.arch == .x86) {
        exe.link_z_notext = true;
    }
}

/// Compiles a single .so file for the given platform.
/// Note that this function assumes your build script only uses a single `android_config`!
pub fn compileAppLibrary(
    sdk: *const Sdk,
    src_file: []const u8,
    app_config: AppConfig,
    mode: std.builtin.Mode,
    target: Target,
    // build_options: std.Build.Pkg,
) *std.Build.Step.Compile {
    const exe = sdk.b.addSharedLibrary(.{
        .name = app_config.app_name,
        .root_source_file = sdk.b.path(src_file),
        .target = sdk.b.resolveTargetQuery(target.getTargetConfig().target),
        .optimize = mode,
    });
    configureStep(
        sdk,
        exe,
        app_config,
        target,
    );
    return exe;
}

fn createLibCFile(sdk: *const Sdk, version: AndroidVersion, folder_name: []const u8, include_dir: []const u8, sys_include_dir: []const u8, crt_dir: []const u8) !std.Build.LazyPath {
    const fname = sdk.b.fmt("android-{d}-{s}.conf", .{ @intFromEnum(version), folder_name });

    var contents = std.ArrayList(u8).init(sdk.b.allocator);
    errdefer contents.deinit();

    var writer = contents.writer();

    //  The directory that contains `stdlib.h`.
    //  On POSIX-like systems, include directories be found with: `cc -E -Wp,-v -xc /dev/null
    try writer.print("include_dir={s}\n", .{include_dir});

    // The system-specific include directory. May be the same as `include_dir`.
    // On Windows it's the directory that includes `vcruntime.h`.
    // On POSIX it's the directory that includes `sys/errno.h`.
    try writer.print("sys_include_dir={s}\n", .{sys_include_dir});

    try writer.print("crt_dir={s}\n", .{crt_dir});
    try writer.writeAll("msvc_lib_dir=\n");
    try writer.writeAll("kernel32_lib_dir=\n");
    try writer.writeAll("gcc_dir=\n");

    const step = sdk.b.addWriteFiles();
    const file_source = step.add(fname, contents.items);
    return file_source;
}

pub fn compressApk(sdk: Sdk, input_apk_file: []const u8, output_apk_file: []const u8) *Step {
    const temp_folder = sdk.b.pathFromRoot("zig-cache/apk-compress-folder");

    const mkdir_cmd = sdk.b.addSystemCommand(&[_][]const u8{
        sdk.system_tools.mkdir,
        temp_folder,
    });

    const unpack_apk = sdk.b.addSystemCommand(&[_][]const u8{
        "unzip",
        "-o",
        sdk.builder.pathFromRoot(input_apk_file),
        "-d",
        temp_folder,
    });
    unpack_apk.step.dependOn(&mkdir_cmd.step);

    const repack_apk = sdk.b.addSystemCommand(&[_][]const u8{
        "zip",
        "-D9r",
        sdk.builder.pathFromRoot(output_apk_file),
        ".",
    });
    repack_apk.cwd = temp_folder;
    repack_apk.step.dependOn(&unpack_apk.step);

    const rmdir_cmd = sdk.b.addSystemCommand(&[_][]const u8{
        sdk.system_tools.rm,
        "-rf",
        temp_folder,
    });
    rmdir_cmd.step.dependOn(&repack_apk.step);
    return &rmdir_cmd.step;
}

pub fn installApp(sdk: Sdk, apk_file: std.Build.LazyPath) *Step {
    const step = sdk.b.addSystemCommand(&[_][]const u8{ sdk.system_tools.adb, "install" });
    step.addFileArg(apk_file);
    return &step.step;
}

pub fn startApp(sdk: Sdk, package_name: []const u8) *Step {
    const command: []const []const u8 = switch (sdk.launch_using) {
        .am => &.{
            sdk.system_tools.adb,
            "shell",
            "am",
            "start",
            "-n",
            sdk.b.fmt("{s}/android.app.NativeActivity", .{package_name}),
        },
        .monkey => &.{
            sdk.system_tools.adb,
            "shell",
            "monkey",
            "-p",
            package_name,
            "1",
        },
    };
    const step = sdk.b.addSystemCommand(command);
    return &step.step;
}

/// Configuration for a signing key.
pub const KeyConfig = struct {
    pub const Algorithm = enum { RSA };
    key_algorithm: Algorithm = .RSA,
    key_size: u32 = 2048, // bits
    validity: u32 = 10_000, // days
    distinguished_name: []const u8 = "CN=example.com, OU=ID, O=Example, L=Doe, S=John, C=GB",
};
/// A build step that initializes a new key store from the given configuration.
/// `android_config.key_store` must be non-`null` as it is used to initialize the key store.
pub fn initKeystore(sdk: Sdk, key_store: KeyStore, key_config: KeyConfig) *Step {
    if (auto_detect.fileExists(key_store.file)) {
        std.log.warn("keystore already exists: {s}", .{key_store.file});
        return sdk.b.step("init_keystore_noop", "Do nothing, since key exists");
    } else {
        const step = sdk.b.addSystemCommand(&[_][]const u8{
            sdk.system_tools.keytool,
            "-genkey",
            "-v",
            "-keystore",
            key_store.file,
            "-alias",
            key_store.alias,
            "-keyalg",
            @tagName(key_config.key_algorithm),
            "-keysize",
            sdk.b.fmt("{d}", .{key_config.key_size}),
            "-validity",
            sdk.b.fmt("{d}", .{key_config.validity}),
            "-storepass",
            key_store.password,
            "-keypass",
            key_store.password,
            "-dname",
            key_config.distinguished_name,
        });
        return &step.step;
    }
}

const Builder = std.Build;
const Step = std.Build.Step;

const android_os = .linux;
const android_abi = .android;

const zig_targets = struct {
    const aarch64 = std.Target.Query{
        .cpu_arch = .aarch64,
        .os_tag = android_os,
        .abi = android_abi,
        .cpu_model = .baseline,
        .cpu_features_add = std.Target.aarch64.featureSet(&.{.v8a}),
    };

    const arm = std.Target.Query{
        .cpu_arch = .arm,
        .os_tag = android_os,
        .abi = android_abi,
        .cpu_model = .baseline,
        .cpu_features_add = std.Target.arm.featureSet(&.{.v7a}),
    };

    const x86 = std.Target.Query{
        .cpu_arch = .x86,
        .os_tag = android_os,
        .abi = android_abi,
        .cpu_model = .baseline,
    };

    const x86_64 = std.Target.Query{
        .cpu_arch = .x86_64,
        .os_tag = android_os,
        .abi = android_abi,
        .cpu_model = .baseline,
    };
};

const app_libs = [_][]const u8{ "GLESv2", "EGL", "android", "log", "aaudio" };

const BuildOptionStep = struct {
    const Self = @This();

    step: Step,
    builder: *std.Build,
    file_content: std.ArrayList(u8),
    package_file: std.Build.GeneratedFile,

    pub fn create(b: *Builder) *Self {
        const options = b.allocator.create(Self) catch @panic("out of memory");

        options.* = Self{
            .builder = b,
            .step = Step.init(.{
                .id = .custom,
                .name = "render build options",
                .owner = b,
                .makeFn = make,
            }),
            .file_content = std.ArrayList(u8).init(b.allocator),
            .package_file = std.Build.GeneratedFile{ .step = &options.step },
        };
        const build_options = b.addModule("build_options", .{
            .root_source_file = .{ .generated = .{ .file = &options.package_file } },
        });
        _ = build_options;

        return options;
    }

    pub fn getModule(self: *Self) *std.Build.Module {
        return self.builder.modules.get("build_options") orelse unreachable;
    }

    pub fn getPackage(self: *Self, name: []const u8) std.Build.Pkg {
        return self.builder.dupePkg(std.Build.Pkg{
            .name = name,
            .source = .{ .generated = &self.package_file },
        });
    }

    pub fn add(self: *Self, comptime T: type, name: []const u8, value: T) void {
        const out = self.file_content.writer();
        switch (T) {
            []const []const u8 => {
                out.print("pub const {}: []const []const u8 = &[_][]const u8{{\n", .{std.zig.fmtId(name)}) catch unreachable;
                for (value) |slice| {
                    out.print("    \"{}\",\n", .{std.zig.fmtEscapes(slice)}) catch unreachable;
                }
                out.writeAll("};\n") catch unreachable;
                return;
            },
            [:0]const u8 => {
                out.print("pub const {}: [:0]const u8 = \"{}\";\n", .{ std.zig.fmtId(name), std.zig.fmtEscapes(value) }) catch unreachable;
                return;
            },
            []const u8 => {
                out.print("pub const {}: []const u8 = \"{}\";\n", .{ std.zig.fmtId(name), std.zig.fmtEscapes(value) }) catch unreachable;
                return;
            },
            ?[:0]const u8 => {
                out.print("pub const {}: ?[:0]const u8 = ", .{std.zig.fmtId(name)}) catch unreachable;
                if (value) |payload| {
                    out.print("\"{}\";\n", .{std.zig.fmtEscapes(payload)}) catch unreachable;
                } else {
                    out.writeAll("null;\n") catch unreachable;
                }
                return;
            },
            ?[]const u8 => {
                out.print("pub const {}: ?[]const u8 = ", .{std.zig.fmtId(name)}) catch unreachable;
                if (value) |payload| {
                    out.print("\"{}\";\n", .{std.zig.fmtEscapes(payload)}) catch unreachable;
                } else {
                    out.writeAll("null;\n") catch unreachable;
                }
                return;
            },
            std.SemanticVersion => {
                out.print(
                    \\pub const {}: @import("std").SemanticVersion = .{{
                    \\    .major = {d},
                    \\    .minor = {d},
                    \\    .patch = {d},
                    \\
                , .{
                    std.zig.fmtId(name),

                    value.major,
                    value.minor,
                    value.patch,
                }) catch unreachable;
                if (value.pre) |some| {
                    out.print("    .pre = \"{}\",\n", .{std.zig.fmtEscapes(some)}) catch unreachable;
                }
                if (value.build) |some| {
                    out.print("    .build = \"{}\",\n", .{std.zig.fmtEscapes(some)}) catch unreachable;
                }
                out.writeAll("};\n") catch unreachable;
                return;
            },
            else => {},
        }
        switch (@typeInfo(T)) {
            .Enum => |enum_info| {
                out.print("pub const {} = enum {{\n", .{std.zig.fmtId(@typeName(T))}) catch unreachable;
                inline for (enum_info.fields) |field| {
                    out.print("    {},\n", .{std.zig.fmtId(field.name)}) catch unreachable;
                }
                out.writeAll("};\n") catch unreachable;
            },
            else => {},
        }
        out.print("pub const {}: {s} = {};\n", .{ std.zig.fmtId(name), @typeName(T), value }) catch unreachable;
    }

    fn make(step: *Step, progress: std.Progress.Node) !void {
        _ = progress;
        const self: *Self = @fieldParentPtr("step", step);

        var cacher = createCacheBuilder(self.builder);
        cacher.addBytes(self.file_content.items);

        const root_path = try cacher.createAndGetPath();

        self.package_file.path = try std.fs.path.join(self.builder.allocator, &[_][]const u8{
            root_path,
            "build_options.zig",
        });

        try std.fs.cwd().writeFile(.{
            .sub_path = self.package_file.path.?,
            .data = self.file_content.items,
        });
    }
};

fn createCacheBuilder(b: *std.Build) CacheBuilder {
    return CacheBuilder.init(b, "android-sdk");
}

const CacheBuilder = struct {
    const Self = @This();

    builder: *std.Build,
    hasher: std.crypto.hash.Sha1,
    subdir: ?[]const u8,

    pub fn init(builder: *std.Build, subdir: ?[]const u8) Self {
        return Self{
            .builder = builder,
            .hasher = std.crypto.hash.Sha1.init(.{}),
            .subdir = if (subdir) |s|
                builder.dupe(s)
            else
                null,
        };
    }

    pub fn addBytes(self: *Self, bytes: []const u8) void {
        self.hasher.update(bytes);
    }

    pub fn addFile(self: *Self, file: std.Build.LazyPath) !void {
        const path = file.getPath(self.builder);

        const data = try std.fs.cwd().readFileAlloc(self.builder.allocator, path, 1 << 32); // 4 GB
        defer self.builder.allocator.free(data);

        self.addBytes(data);
    }

    fn createPath(self: *Self) ![]const u8 {
        var hash: [20]u8 = undefined;
        self.hasher.final(&hash);

        const path = if (self.subdir) |subdir|
            try std.fmt.allocPrint(
                self.builder.allocator,
                "{s}/{s}/o/{}",
                .{
                    self.builder.cache_root.path.?,
                    subdir,
                    std.fmt.fmtSliceHexLower(&hash),
                },
            )
        else
            try std.fmt.allocPrint(
                self.builder.allocator,
                "{s}/o/{}",
                .{
                    self.builder.cache_root.path.?,
                    std.fmt.fmtSliceHexLower(&hash),
                },
            );

        return path;
    }

    pub const DirAndPath = struct {
        dir: std.fs.Dir,
        path: []const u8,
    };
    pub fn createAndGetDir(self: *Self) !DirAndPath {
        const path = try self.createPath();
        return DirAndPath{
            .path = path,
            .dir = try std.fs.cwd().makeOpenPath(path, .{}),
        };
    }

    pub fn createAndGetPath(self: *Self) ![]const u8 {
        const path = try self.createPath();
        try std.fs.cwd().makePath(path);
        return path;
    }
};

/// A enumeration of all permissions.
/// See: https://developer.android.com/reference/android/Manifest.permission
pub const Permission = enum {
    accept_handover,
    access_background_location,
    access_blobs_across_users,
    access_checkin_properties,
    access_coarse_location,
    access_fine_location,
    access_location_extra_commands,
    access_media_location,
    access_network_state,
    access_notification_policy,
    access_wifi_state,
    account_manager,
    activity_recognition,
    add_voicemail,
    answer_phone_calls,
    battery_stats,
    bind_accessibility_service,
    bind_appwidget,
    bind_autofill_service,
    bind_call_redirection_service,
    bind_carrier_messaging_client_service,
    bind_carrier_messaging_service,
    bind_carrier_services,
    bind_chooser_target_service,
    bind_companion_device_service,
    bind_condition_provider_service,
    bind_controls,
    bind_device_admin,
    bind_dream_service,
    bind_incall_service,
    bind_input_method,
    bind_midi_device_service,
    bind_nfc_service,
    bind_notification_listener_service,
    bind_print_service,
    bind_quick_access_wallet_service,
    bind_quick_settings_tile,
    bind_remoteviews,
    bind_screening_service,
    bind_telecom_connection_service,
    bind_text_service,
    bind_tv_input,
    bind_visual_voicemail_service,
    bind_voice_interaction,
    bind_vpn_service,
    bind_vr_listener_service,
    bind_wallpaper,
    bluetooth,
    bluetooth_admin,
    bluetooth_advertise,
    bluetooth_connect,
    bluetooth_privileged,
    bluetooth_scan,
    body_sensors,
    broadcast_package_removed,
    broadcast_sms,
    broadcast_sticky,
    broadcast_wap_push,
    call_companion_app,
    call_phone,
    call_privileged,
    camera,
    capture_audio_output,
    change_component_enabled_state,
    change_configuration,
    change_network_state,
    change_wifi_multicast_state,
    change_wifi_state,
    clear_app_cache,
    control_location_updates,
    delete_cache_files,
    delete_packages,
    diagnostic,
    disable_keyguard,
    dump,
    expand_status_bar,
    factory_test,
    foreground_service,
    get_accounts,
    get_accounts_privileged,
    get_package_size,
    get_tasks,
    global_search,
    hide_overlay_windows,
    high_sampling_rate_sensors,
    install_location_provider,
    install_packages,
    install_shortcut,
    instant_app_foreground_service,
    interact_across_profiles,
    internet,
    kill_background_processes,
    launch_two_pane_settings_deep_link,
    loader_usage_stats,
    location_hardware,
    manage_documents,
    manage_external_storage,
    manage_media,
    manage_ongoing_calls,
    manage_own_calls,
    master_clear,
    media_content_control,
    modify_audio_settings,
    modify_phone_state,
    mount_format_filesystems,
    mount_unmount_filesystems,
    nfc,
    nfc_preferred_payment_info,
    nfc_transaction_event,
    package_usage_stats,
    persistent_activity,
    process_outgoing_calls,
    query_all_packages,
    read_calendar,
    read_call_log,
    read_contacts,
    read_external_storage,
    read_input_state,
    read_logs,
    read_phone_numbers,
    read_phone_state,
    read_precise_phone_state,
    read_sms,
    read_sync_settings,
    read_sync_stats,
    read_voicemail,
    reboot,
    receive_boot_completed,
    receive_mms,
    receive_sms,
    receive_wap_push,
    record_audio,
    reorder_tasks,
    request_companion_profile_watch,
    request_companion_run_in_background,
    request_companion_start_foreground_services_from_background,
    request_companion_use_data_in_background,
    request_delete_packages,
    request_ignore_battery_optimizations,
    request_install_packages,
    request_observe_companion_device_presence,
    request_password_complexity,
    schedule_exact_alarm,
    send_respond_via_message,
    send_sms,
    set_alarm,
    set_always_finish,
    set_animation_scale,
    set_debug_app,
    set_process_limit,
    set_time,
    set_time_zone,
    set_wallpaper,
    set_wallpaper_hints,
    signal_persistent_processes,
    sms_financial_transactions,
    start_foreground_services_from_background,
    start_view_permission_usage,
    status_bar,
    system_alert_window,
    transmit_ir,
    uninstall_shortcut,
    update_device_stats,
    update_packages_without_user_action,
    use_biometric,
    use_fingerprint,
    use_full_screen_intent,
    use_icc_auth_with_device_identifier,
    use_sip,
    uwb_ranging,
    vibrate,
    wake_lock,
    write_apn_settings,
    write_calendar,
    write_call_log,
    write_contacts,
    write_external_storage,
    write_gservices,
    write_secure_settings,
    write_settings,
    write_sync_settings,
    write_voicemail,

    pub fn toString(self: Permission) []const u8 {
        @setEvalBranchQuota(10_000);
        inline for (std.meta.fields(Permission)) |fld| {
            if (self == @field(Permission, fld.name)) {
                return comptime blk: {
                    var name: [fld.name.len]u8 = undefined;
                    break :blk "android.permission." ++ std.ascii.upperString(&name, fld.name);
                };
            }
        }
        unreachable;
    }
};
