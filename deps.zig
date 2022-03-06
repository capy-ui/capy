const std = @import("std");
const builtin = @import("builtin");
const Pkg = std.build.Pkg;
const string = []const u8;

pub const cache = ".zigmod/deps";

pub fn addAllTo(exe: *std.build.LibExeObjStep) void {
    checkMinZig(builtin.zig_version, exe);
    @setEvalBranchQuota(1_000_000);
    for (packages) |pkg| {
        exe.addPackage(pkg.pkg.?);
    }
    var llc = false;
    var vcpkg = false;
    inline for (comptime std.meta.declarations(package_data)) |decl| {
        const pkg = @as(Package, @field(package_data, decl.name));
        inline for (pkg.system_libs) |item| {
            exe.linkSystemLibrary(item);
            llc = true;
        }
        inline for (pkg.c_include_dirs) |item| {
            exe.addIncludeDir(@field(dirs, decl.name) ++ "/" ++ item);
            llc = true;
        }
        inline for (pkg.c_source_files) |item| {
            exe.addCSourceFile(@field(dirs, decl.name) ++ "/" ++ item, pkg.c_source_flags);
            llc = true;
        }
        vcpkg = vcpkg or pkg.vcpkg;
    }
    if (llc) exe.linkLibC();
    if (builtin.os.tag == .windows and vcpkg) exe.addVcpkgPaths(.static) catch |err| @panic(@errorName(err));
}

pub const Package = struct {
    directory: string,
    pkg: ?Pkg = null,
    c_include_dirs: []const string = &.{},
    c_source_files: []const string = &.{},
    c_source_flags: []const string = &.{},
    system_libs: []const string = &.{},
    vcpkg: bool = false,
};

fn checkMinZig(current: std.SemanticVersion, exe: *std.build.LibExeObjStep) void {
    const min = std.SemanticVersion.parse("null") catch return;
    if (current.order(min).compare(.lt)) @panic(exe.builder.fmt("Your Zig version v{} does not meet the minimum build requirement of v{}", .{current, min}));
}

pub const dirs = struct {
    pub const _root = "";
    pub const _deeztnhr07fk = cache ++ "/../..";
    pub const _hm449ur2xup4 = cache ++ "/git/github.com/Luukdegram/apple_pie";
};

pub const package_data = struct {
    pub const _deeztnhr07fk = Package{
        .directory = dirs._deeztnhr07fk,
        .pkg = Pkg{ .name = "zgt", .path = .{ .path = dirs._deeztnhr07fk ++ "/src/main.zig" }, .dependencies = null },
        .system_libs = &.{ "gtk+-3.0", "c" },
    };
    pub const _hm449ur2xup4 = Package{
        .directory = dirs._hm449ur2xup4,
        .pkg = Pkg{ .name = "apple_pie", .path = .{ .path = dirs._hm449ur2xup4 ++ "/src/apple_pie.zig" }, .dependencies = null },
    };
    pub const _root = Package{
        .directory = dirs._root,
    };
};

pub const packages = &[_]Package{
    package_data._deeztnhr07fk,
};

pub const pkgs = struct {
    pub const zgt = package_data._deeztnhr07fk;
};

pub const imports = struct {
    pub const apple_pie = @import(".zigmod/deps/git/github.com/Luukdegram/apple_pie/src/apple_pie.zig");
};
