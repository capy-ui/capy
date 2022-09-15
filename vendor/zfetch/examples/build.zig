const std = @import("std");

const Builder = std.build.Builder;

const examples = [_][]const u8{ "get", "post", "download", "evented" };

const packages = @import("deps.zig");

pub fn build(b: *Builder) void {
    const target = b.standardTargetOptions(.{});
    const mode = b.standardReleaseOptions();

    inline for (examples) |name| {
        const example = b.addExecutable(name, name ++ ".zig");
        example.setBuildMode(mode);
        example.setTarget(target);
        example.install();

        if (@hasDecl(packages, "use_submodules")) {
            example.addPackage(getPackage(b) catch unreachable);
        } else {
            if (@hasDecl(packages, "addAllTo")) { // zigmod
                packages.addAllTo(example);
            } else if (@hasDecl(packages, "pkgs") and @hasDecl(packages.pkgs, "addAllTo")) { // gyro
                packages.pkgs.addAllTo(example);
            }
        }

        const example_step = b.step(name, "Build the " ++ name ++ " example");
        example_step.dependOn(&example.step);

        const example_run_step = b.step("run-" ++ name, "Run the " ++ name ++ " example");

        const example_run = example.run();
        example_run_step.dependOn(&example_run.step);
    }
}

// we can't use zfetch_build.getPackage() because its outside of this build's package path

fn getBuildPrefix() []const u8 {
    return std.fs.path.dirname(@src().file) orelse ".";
}

fn getDependency(comptime name: []const u8, comptime root: []const u8) !std.build.Pkg {
    const path = getBuildPrefix() ++ "/../libs/" ++ name ++ "/" ++ root;

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
        .source = .{ .path = getBuildPrefix() ++ "/../src/main.zig" },
        .dependencies = dependencies,
    };
}
