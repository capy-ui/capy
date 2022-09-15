const std = @import("std");

const Builder = std.build.Builder;

const packages = @import("deps.zig");

pub fn build(b: *Builder) void {
    const mode = b.standardReleaseOptions();
    const target = b.standardTargetOptions(.{});

    const lib_tests = b.addTest("src/main.zig");
    lib_tests.setBuildMode(mode);
    lib_tests.setTarget(target);

    if (@hasDecl(packages, "use_submodules")) { // submodules
        const package = getPackage(b) catch unreachable;

        for (package.dependencies.?) |dep| {
            lib_tests.addPackage(dep);
        }
    } else if (@hasDecl(packages, "addAllTo")) { // zigmod
        packages.addAllTo(lib_tests);
    } else if (@hasDecl(packages, "pkgs") and @hasDecl(packages.pkgs, "addAllTo")) { // gyro
        packages.pkgs.addAllTo(lib_tests);
    }

    const tests = b.step("test", "Run all library tests");
    tests.dependOn(&lib_tests.step);
}

fn getBuildPrefix() []const u8 {
    return std.fs.path.dirname(@src().file) orelse ".";
}

fn getDependency(comptime name: []const u8, comptime root: []const u8) !std.build.Pkg {
    const path = getBuildPrefix() ++ "/libs/" ++ name ++ "/" ++ root;

    // Make sure that the dependency has been checked out.
    std.fs.cwd().access(path, .{}) catch |err| switch (err) {
        error.FileNotFound => {
            std.log.err("zfetch: dependency '{s}' not checked out", .{name});

            return err;
        },
        else => return err,
    };

    return std.build.Pkg{
        .name = name,
        .source = .{ .path = path },
    };
}

pub fn getPackage(b: *Builder) !std.build.Pkg {
    var dependencies = b.allocator.alloc(std.build.Pkg, 3) catch unreachable;

    dependencies[0] = try getDependency("iguanaTLS", "src/main.zig");
    dependencies[1] = try getDependency("uri", "uri.zig");
    dependencies[2] = try getDependency("hzzp", "src/main.zig");

    return std.build.Pkg{
        .name = "zfetch",
        .source = .{ .path = getBuildPrefix() ++ "/src/main.zig" },
        .dependencies = dependencies,
    };
}
