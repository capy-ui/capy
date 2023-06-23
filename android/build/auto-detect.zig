const std = @import("std");
const builtin = @import("builtin");
const Builder = std.build.Builder;

const Sdk = @import("../Sdk.zig");
const UserConfig = Sdk.UserConfig;

// This config stores tool paths for the current machine
const build_config_dir = ".build_config";
const local_config_file = "android.json";

const print = std.debug.print;

pub fn findUserConfig(b: *Builder, versions: Sdk.ToolchainVersions) !UserConfig {
    // var str_buf: [5]u8 = undefined;

    var config = UserConfig{};
    var config_dirty: bool = false;

    const local_config_path = pathConcat(b, build_config_dir, local_config_file);
    const config_path = b.pathFromRoot(local_config_path);
    const config_dir = b.pathFromRoot(build_config_dir);

    // Check for a user config file.
    if (std.fs.cwd().openFile(config_path, .{})) |file| {
        defer file.close();
        const bytes = file.readToEndAlloc(b.allocator, 1 * 1000 * 1000) catch |err| {
            print("Unexpected error reading {s}: {s}\n", .{ config_path, @errorName(err) });
            return err;
        };
        if (std.json.parseFromSlice(UserConfig, b.allocator, bytes, .{})) |conf| {
            config = conf.value;
        } else |err| {
            print("Could not parse {s} ({s}).\n", .{ config_path, @errorName(err) });
            return err;
        }
    } else |err| switch (err) {
        error.FileNotFound => {
            config_dirty = true;
        },
        else => {
            print("Unexpected error opening {s}: {s}\n", .{ config_path, @errorName(err) });
            return err;
        },
    }

    // Verify the user config and set new values if needed
    // First the android home
    if (config.android_sdk_root.len > 0) {
        if (findProblemWithAndroidSdk(b, versions, config.android_sdk_root)) |problem| {
            print("Invalid android root directory: {s}\n    {s}\n    Looking for a new one.\n", .{ config.android_sdk_root, problem });
            config.android_sdk_root = "";
            // N.B. Don't dirty the file for this.  We don't want to nuke the file if we can't find a replacement.
        }
    }

    if (config.android_sdk_root.len == 0) {
        // try to find the android home
        if (std.process.getEnvVarOwned(b.allocator, "ANDROID_HOME")) |value| {
            if (value.len > 0) {
                if (findProblemWithAndroidSdk(b, versions, value)) |problem| {
                    print("Cannot use ANDROID_HOME ({s}):\n    {s}\n", .{ value, problem });
                } else {
                    print("Using android sdk at ANDROID_HOME: {s}\n", .{value});
                    config.android_sdk_root = value;
                    config_dirty = true;
                }
            }
        } else |_| {
            // ignore if env var is not found
        }
    }

    if (config.android_sdk_root.len == 0) {
        // try to find the android home
        if (std.process.getEnvVarOwned(b.allocator, "ANDROID_SDK_ROOT")) |value| {
            if (value.len > 0) {
                if (findProblemWithAndroidSdk(b, versions, value)) |problem| {
                    print("Cannot use ANDROID_SDK_ROOT ({s}):\n    {s}\n", .{ value, problem });
                } else {
                    print("Using android sdk at ANDROID_SDK_ROOT: {s}\n", .{value});
                    config.android_sdk_root = value;
                    config_dirty = true;
                }
            }
        } else |_| {
            // ignore environment variable failure
        }
    }

    var android_studio_path: []const u8 = "";

    // On windows, check for an android studio install.
    // If it's present, it may have the sdk path stored in the registry.
    // If not, check the default install location.
    if (builtin.os.tag == .windows) {
        const HKEY = ?*opaque {};
        const LSTATUS = u32;
        const DWORD = u32;

        // const HKEY_CLASSES_ROOT = @intToPtr(HKEY, 0x80000000);
        const HKEY_CURRENT_USER = @ptrFromInt(HKEY, 0x80000001);
        const HKEY_LOCAL_MACHINE = @ptrFromInt(HKEY, 0x80000002);
        // const HKEY_USERS = @intToPtr(HKEY, 0x80000003);

        // const RRF_RT_ANY: DWORD = 0xFFFF;
        // const RRF_RT_REG_BINARY: DWORD = 0x08;
        // const RRF_RT_REG_DWORD: DWORD = 0x10;
        // const RRF_RT_REG_EXPAND_SZ: DWORD = 0x04;
        // const RRF_RT_REG_MULTI_SZ: DWORD = 0x20;
        // const RRF_RT_REG_NONE: DWORD = 0x01;
        // const RRF_RT_REG_QWORD: DWORD = 0x40;
        const RRF_RT_REG_SZ: DWORD = 0x02;
        // const RRF_RT_DWORD = RRF_RT_REG_DWORD | RRF_RT_REG_BINARY;
        // const RRF_RT_QWORD = RRF_RT_REG_QWORD | RRF_RT_REG_BINARY;

        // const RRF_NOEXPAND: DWORD = 0x10000000;
        // const RRF_ZEROONFAILURE: DWORD = 0x20000000;
        // const RRF_SUBKEY_WOW6464KEY: DWORD = 0x00010000;
        // const RRF_SUBKEY_WOW6432KEY: DWORD = 0x00020000;

        const ERROR_SUCCESS: LSTATUS = 0;
        const ERROR_MORE_DATA: LSTATUS = 234;

        const reg = struct {
            extern "Advapi32" fn RegOpenKeyA(key: HKEY, subKey: [*:0]const u8, result: *HKEY) LSTATUS;
            extern "Advapi32" fn RegCloseKey(key: HKEY) LSTATUS;
            extern "Advapi32" fn RegGetValueA(key: HKEY, subKey: ?[*:0]const u8, value: [*:0]const u8, flags: DWORD, type: ?*DWORD, data: ?*anyopaque, len: ?*DWORD) LSTATUS;

            fn getStringAlloc(allocator: std.mem.Allocator, key: HKEY, value: [*:0]const u8) ?[]const u8 {
                // query the length
                var len: DWORD = 0;
                var res = RegGetValueA(key, null, value, RRF_RT_REG_SZ, null, null, &len);
                if (res == ERROR_SUCCESS) {
                    if (len == 0) {
                        return &[_]u8{};
                    }
                } else if (res != ERROR_MORE_DATA) {
                    return null;
                }

                // get the data
                const buffer = allocator.alloc(u8, len) catch unreachable;
                len = @intCast(DWORD, buffer.len);
                res = RegGetValueA(key, null, value, RRF_RT_REG_SZ, null, buffer.ptr, &len);
                if (res == ERROR_SUCCESS) {
                    for (buffer[0..len], 0..) |c, i| {
                        if (c == 0) return buffer[0..i];
                    }
                    return buffer[0..len];
                }
                allocator.free(buffer);
                return null;
            }
        };

        // Get the android studio registry entry
        var android_studio_key: HKEY = for ([_]HKEY{ HKEY_CURRENT_USER, HKEY_LOCAL_MACHINE }) |root_key| {
            var software: HKEY = null;
            if (reg.RegOpenKeyA(root_key, "software", &software) == ERROR_SUCCESS) {
                defer _ = reg.RegCloseKey(software);
                var android: HKEY = null;
                if (reg.RegOpenKeyA(software, "Android Studio", &android) == ERROR_SUCCESS) {
                    if (android != null) break android;
                }
            }
        } else null;

        // Grab the paths to the android studio install and the sdk install.
        if (android_studio_key != null) {
            defer _ = reg.RegCloseKey(android_studio_key);
            if (reg.getStringAlloc(b.allocator, android_studio_key, "Path")) |path| {
                android_studio_path = path;
            } else {
                print("Could not get android studio path\n", .{});
            }
            if (reg.getStringAlloc(b.allocator, android_studio_key, "SdkPath")) |sdk_path| {
                if (sdk_path.len > 0) {
                    if (findProblemWithAndroidSdk(b, versions, sdk_path)) |problem| {
                        print("Cannot use Android Studio sdk ({s}):\n    {s}\n", .{ sdk_path, problem });
                    } else {
                        print("Using android sdk from Android Studio: {s}\n", .{sdk_path});
                        config.android_sdk_root = sdk_path;
                        config_dirty = true;
                    }
                }
            }
        }

        // If we didn't find an sdk in the registry, check the default install location.
        // On windows, this is AppData/Local/Android.
        if (config.android_sdk_root.len == 0) {
            if (std.process.getEnvVarOwned(b.allocator, "LOCALAPPDATA")) |appdata_local| {
                const sdk_path = pathConcat(b, appdata_local, "Android");
                if (findProblemWithAndroidSdk(b, versions, sdk_path)) |problem| {
                    print("Cannot use default Android Studio SDK\n    at {s}:\n    {s}\n", .{ sdk_path, problem });
                } else {
                    print("Using android sdk from Android Studio: {s}\n", .{sdk_path});
                    config.android_sdk_root = sdk_path;
                    config_dirty = true;
                }
            } else |_| {
                // ignore env
            }
        }
    }

    // Finally, if we still don't have an sdk, see if `adb` is on the path and try to use that.
    if (config.android_sdk_root.len == 0) {
        if (findProgramPath(b.allocator, "adb")) |path| {
            const sep = std.fs.path.sep;
            if (std.mem.lastIndexOfScalar(u8, path, sep)) |index| {
                var rest = path[0..index];
                const parent = "platform-tools";
                if (std.mem.endsWith(u8, rest, parent) and rest[rest.len - parent.len - 1] == sep) {
                    const sdk_path = rest[0 .. rest.len - parent.len - 1];
                    if (findProblemWithAndroidSdk(b, versions, sdk_path)) |problem| {
                        print("Cannot use SDK near adb\n    at {s}:\n    {s}\n", .{ sdk_path, problem });
                    } else {
                        print("Using android sdk near adb: {s}\n", .{sdk_path});
                        config.android_sdk_root = sdk_path;
                        config_dirty = true;
                    }
                }
            }
        }
    }

    // Next up, NDK.
    if (config.android_ndk_root.len > 0) {
        if (findProblemWithAndroidNdk(b, versions, config.android_ndk_root)) |problem| {
            print("Saved NDK is invalid ({s})\n{s}\n", .{ config.android_ndk_root, problem });
            config.android_ndk_root = "";
        }
    }

    // first, check ANDROID_NDK_ROOT
    if (config.android_ndk_root.len == 0) {
        if (std.process.getEnvVarOwned(b.allocator, "ANDROID_NDK_ROOT")) |value| {
            if (value.len > 0) {
                if (findProblemWithAndroidNdk(b, versions, value)) |problem| {
                    print("Cannot use ANDROID_NDK_ROOT ({s}):\n    {s}\n", .{ value, problem });
                } else {
                    print("Using android ndk at ANDROID_NDK_ROOT: {s}\n", .{value});
                    config.android_ndk_root = value;
                    config_dirty = true;
                }
            }
        } else |_| {}
    }

    // Then check for a side-by-side install
    if (config.android_ndk_root.len == 0) {
        if (config.android_sdk_root.len > 0) {
            const ndk_root = std.fs.path.join(b.allocator, &[_][]const u8{
                config.android_sdk_root,
                "ndk",
                versions.ndk_version,
            }) catch unreachable;
            if (findProblemWithAndroidNdk(b, versions, ndk_root)) |problem| {
                print("Cannot use side by side NDK ({s}):\n    {s}\n", .{ ndk_root, problem });
            } else {
                print("Using side by side NDK install: {s}\n", .{ndk_root});
                config.android_ndk_root = ndk_root;
                config_dirty = true;
            }
        }
    }

    // Finally, we need to find the JDK, for jarsigner.
    if (config.java_home.len > 0) {
        if (findProblemWithJdk(b, config.java_home)) |problem| {
            print("Cannot use configured java install {s}: {s}\n", .{ config.java_home, problem });
            config.java_home = "";
        }
    }

    // Check the JAVA_HOME variable
    if (config.java_home.len == 0) {
        if (std.process.getEnvVarOwned(b.allocator, "JAVA_HOME")) |value| {
            if (value.len > 0) {
                if (findProblemWithJdk(b, value)) |problem| {
                    print("Cannot use JAVA_HOME ({s}):\n    {s}\n", .{ value, problem });
                } else {
                    print("Using java JAVA_HOME: {s}\n", .{value});
                    config.java_home = value;
                    config_dirty = true;
                }
            }
        } else |_| {}
    }

    // Look for `where jarsigner`
    if (config.java_home.len == 0) {
        if (findProgramPath(b.allocator, "jarsigner")) |path| {
            const sep = std.fs.path.sep;
            if (std.mem.lastIndexOfScalar(u8, path, sep)) |last_slash| {
                if (std.mem.lastIndexOfScalar(u8, path[0..last_slash], sep)) |second_slash| {
                    const home = path[0..second_slash];
                    if (findProblemWithJdk(b, home)) |problem| {
                        print("Cannot use java at ({s}):\n    {s}\n", .{ home, problem });
                    } else {
                        print("Using java at {s}\n", .{home});
                        config.java_home = home;
                        config_dirty = true;
                    }
                }
            }
        }
    }

    // If we have Android Studio installed, it packages a JDK.
    // Check for that.
    if (config.java_home.len == 0) {
        if (android_studio_path.len > 0) {
            const packaged_jre = pathConcat(b, android_studio_path, "jre");
            if (findProblemWithJdk(b, packaged_jre)) |problem| {
                print("Cannot use Android Studio java at ({s}):\n    {s}\n", .{ packaged_jre, problem });
            } else {
                print("Using java from Android Studio: {s}\n", .{packaged_jre});
                config.java_home = packaged_jre;
                config_dirty = true;
            }
        }
    }

    // Write out the new config
    if (config_dirty) {
        std.fs.cwd().makeDir(config_dir) catch {};
        var file = std.fs.cwd().createFile(config_path, .{}) catch |err| {
            print("Couldn't write config file {s}: {s}\n\n", .{ config_path, @errorName(err) });
            return err;
        };
        defer file.close();

        var buf_writer = std.io.bufferedWriter(file.writer());

        std.json.stringify(config, .{}, buf_writer.writer()) catch |err| {
            print("Error writing config file {s}: {s}\n", .{ config_path, @errorName(err) });
            return err;
        };
        buf_writer.flush() catch |err| {
            print("Error writing config file {s}: {s}\n", .{ config_path, @errorName(err) });
            return err;
        };
    }

    // Check if the config is invalid.
    if (config.android_sdk_root.len == 0 or
        config.android_ndk_root.len == 0 or
        config.java_home.len == 0)
    {
        print("\nCould not find all needed tools. Please edit {s} to specify their paths.\n\n", .{local_config_path});
        if (config.android_sdk_root.len == 0) {
            print("Android SDK root is missing. Edit the config file, or set ANDROID_SDK_ROOT to your android install.\n", .{});
            print("You will need build tools version {s} and android sdk platform {s}\n\n", .{ versions.build_tools_version, "TODO: ???" });
        }
        if (config.android_ndk_root.len == 0) {
            print("Android NDK root is missing. Edit the config file, or set ANDROID_NDK_ROOT to your android NDK install.\n", .{});
            print("You will need NDK version {s}\n\n", .{versions.ndk_version});
        }
        if (config.java_home.len == 0) {
            print("Java JDK is missing. Edit the config file, or set JAVA_HOME to your JDK install.\n", .{});
            if (builtin.os.tag == .windows) {
                print("Installing Android Studio will also install a suitable JDK.\n", .{});
            }
            print("\n", .{});
        }

        std.os.exit(1);
    }

    if (config_dirty) {
        print("New configuration:\nSDK: {s}\nNDK: {s}\nJDK: {s}\n", .{ config.android_sdk_root, config.android_ndk_root, config.java_home });
    }

    return config;
}

pub fn findProgramPath(allocator: std.mem.Allocator, program: []const u8) ?[]const u8 {
    const args: []const []const u8 = if (builtin.os.tag == .windows)
        &[_][]const u8{ "where", program }
    else
        &[_][]const u8{ "which", program };

    var proc = std.ChildProcess.init(args, allocator);

    proc.stderr_behavior = .Close;
    proc.stdout_behavior = .Pipe;
    proc.stdin_behavior = .Close;

    proc.spawn() catch return null;

    const stdout = proc.stdout.?.readToEndAlloc(allocator, 1024) catch return null;
    const term = proc.wait() catch return null;
    switch (term) {
        .Exited => |rc| {
            if (rc != 0) return null;
        },
        else => return null,
    }

    var path = std.mem.trim(u8, stdout, " \t\r\n");
    if (std.mem.indexOfScalar(u8, path, '\n')) |index| {
        path = std.mem.trim(u8, path[0..index], " \t\r\n");
    }
    if (path.len > 0) return path;

    return null;
}

// Returns the problem with an android_home path.
// If it seems alright, returns null.
fn findProblemWithAndroidSdk(b: *Builder, versions: Sdk.ToolchainVersions, path: []const u8) ?[]const u8 {
    std.fs.cwd().access(path, .{}) catch |err| {
        if (err == error.FileNotFound) return "Directory does not exist";
        return b.fmt("Cannot access {s}, {s}", .{ path, @errorName(err) });
    };

    const build_tools = pathConcat(b, path, "build-tools");
    std.fs.cwd().access(build_tools, .{}) catch |err| {
        return b.fmt("Cannot access build-tools/, {s}", .{@errorName(err)});
    };

    const versioned_tools = pathConcat(b, build_tools, versions.build_tools_version);
    std.fs.cwd().access(versioned_tools, .{}) catch |err| {
        if (err == error.FileNotFound) {
            return b.fmt("Missing build tools version {s}", .{versions.build_tools_version});
        } else {
            return b.fmt("Cannot access build-tools/{s}/, {s}", .{ versions.build_tools_version, @errorName(err) });
        }
    };

    // var str_buf: [5]u8 = undefined;
    // const android_version_str = "TODO: ???"; // versions.androidSdkString(&str_buf);

    // const platforms = pathConcat(b, path, "platforms");
    // const platform_version = pathConcat(b, platforms, b.fmt("android-{d}", .{versions.android_sdk_version}));
    // std.fs.cwd().access(platform_version, .{}) catch |err| {
    //     if (err == error.FileNotFound) {
    //         return b.fmt("Missing android platform version {s}", .{android_version_str});
    //     } else {
    //         return b.fmt("Cannot access platforms/android-{s}, {s}", .{ android_version_str, @errorName(err) });
    //     }
    // };

    return null;
}

// Returns the problem with an android ndk path.
// If it seems alright, returns null.
fn findProblemWithAndroidNdk(b: *Builder, versions: Sdk.ToolchainVersions, path: []const u8) ?[]const u8 {
    std.fs.cwd().access(path, .{}) catch |err| {
        if (err == error.FileNotFound) return "Directory does not exist";
        return b.fmt("Cannot access {s}, {s}", .{ path, @errorName(err) });
    };

    const ndk_include_path = std.fs.path.join(b.allocator, &[_][]const u8{
        path,
        "toolchains",
        "llvm",
        "prebuilt",
        Sdk.toolchainHostTag(),
        "sysroot",
        "usr",
        "include",
    }) catch unreachable;
    std.fs.cwd().access(ndk_include_path, .{}) catch |err| {
        return b.fmt("Cannot access {s}, {s}\nMake sure you are using NDK {s}.", .{ ndk_include_path, @errorName(err), versions.ndk_version });
    };

    return null;
}

// Returns the problem with a jdk install.
// If it seems alright, returns null.
fn findProblemWithJdk(b: *Builder, path: []const u8) ?[]const u8 {
    std.fs.cwd().access(path, .{}) catch |err| {
        if (err == error.FileNotFound) return "Directory does not exist";
        return b.fmt("Cannot access {s}, {s}", .{ path, @errorName(err) });
    };

    const target_executable = if (builtin.os.tag == .windows) "bin\\jarsigner.exe" else "bin/jarsigner";
    const target_path = pathConcat(b, path, target_executable);
    std.fs.cwd().access(target_path, .{}) catch |err| {
        return b.fmt("Cannot access jarsigner, {s}", .{@errorName(err)});
    };

    return null;
}

fn pathConcat(b: *Builder, left: []const u8, right: []const u8) []const u8 {
    return std.fs.path.join(b.allocator, &[_][]const u8{ left, right }) catch unreachable;
}

pub fn fileExists(path: []const u8) bool {
    std.fs.cwd().access(path, .{}) catch |err| {
        if (err == error.FileNotFound) return false;
        std.log.debug("Cannot access {s}, {s}", .{ path, @errorName(err) });
        return false;
    };
    return true;
}
