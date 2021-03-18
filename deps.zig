const std = @import("std");
const build = std.build;

pub const cache = ".zigmod/deps";

pub fn addAllTo(exe: *build.LibExeObjStep) void {
    @setEvalBranchQuota(1_000_000);
    for (packages) |pkg| {
        exe.addPackage(pkg);
    }
    if (c_include_dirs.len > 0 or c_source_files.len > 0) {
        exe.linkLibC();
    }
    for (c_include_dirs) |dir| {
        exe.addIncludeDir(dir);
    }
    inline for (c_source_files) |fpath| {
        exe.addCSourceFile(fpath[1], @field(c_source_flags, fpath[0]));
    }
    for (system_libs) |lib| {
        exe.linkSystemLibrary(lib);
    }
}

fn get_flags(comptime index: usize) []const u8 {
    return @field(c_source_flags, _paths[index]);
}

pub const _ids = .{
    "deeztnhr07fkixemzrksabk1elbzfz1clpervtjjcgxntyop",
};

pub const _paths = .{
    "",
};

pub const package_data = struct {
};

pub const packages = &[_]build.Pkg{
};

pub const pkgs = struct {
};

pub const c_include_dirs = &[_][]const u8{
};

pub const c_source_flags = struct {
};

pub const c_source_files = &[_][2][]const u8{
};

pub const system_libs = &[_][]const u8{
    "gtk+-3.0",
    "c",
};

