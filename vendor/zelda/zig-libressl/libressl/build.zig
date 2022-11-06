// TODO(haze): explicit_bzero needs -O0

const std = @import("std");
const out = std.log.scoped(.libressl_build);

const CIncludeDependencyBundle = struct {
    headers: []const []const u8,
    c_flag: []const u8,
};

pub const CIncludeDependencies = [_]CIncludeDependencyBundle{
    .{
        .headers = &[_][]const u8{"endian.h"},
        .c_flag = "-DHAVE_ENDIAN_H",
    },
    .{
        .headers = &[_][]const u8{"err.h"},
        .c_flag = "-DHAVE_ERR_H",
    },
    .{
        .headers = &[_][]const u8{ "sys/types.h", "arpa/inet.h", "netinet/ip.h" },
        .c_flag = "-DHAVE_NETINET_IP_H",
    },
};

// Mapping from Target to CBackupSourceFiles
pub const CFunctionDependencyTargetMap = std.enums.directEnumArray(std.Target.Os.Tag, ?type, 0, .{
    .windows = CFunctionDependencyWindowsBackupSourceFiles,
    .ios = CFunctionDependencyDarwinBackupSourceFiles,
    .tvos = CFunctionDependencyDarwinBackupSourceFiles,
    .watchos = CFunctionDependencyDarwinBackupSourceFiles,
    .macos = CFunctionDependencyDarwinBackupSourceFiles,
    .linux = CFunctionDependencyLinuxBackupSourceFiles,
    .freebsd = null,
    .freestanding = null,
    .ananas = null,
    .cloudabi = null,
    .dragonfly = null,
    .fuchsia = null,
    .kfreebsd = null,
    .lv2 = null,
    .netbsd = null,
    .openbsd = null,
    .solaris = null,
    .zos = null,
    .haiku = null,
    .minix = null,
    .rtems = null,
    .nacl = null,
    .aix = null,
    .cuda = null,
    .nvcl = null,
    .amdhsa = null,
    .ps4 = null,
    .ps5 = null,
    .elfiamcu = null,
    .driverkit = null,
    .mesa3d = null,
    .contiki = null,
    .amdpal = null,
    .hermit = null,
    .hurd = null,
    .wasi = null,
    .emscripten = null,
    .shadermodel = null,
    .uefi = null,
    .opencl = null,
    .glsl450 = null,
    .vulkan = null,
    .plan9 = null,
    .other = null,
});

pub const CFunctionDependency = enum {
    asprintf,
    recallocarray,
    reallocarray,
    strcasecmp,
    strlcat,
    strlcpy,
    strndup,
    strsep,
    timegm,
    freezero,
    arc4random_buf,
    arc4random_uniform,
    explicit_bzero,
    getauxval,
    getentropy,
    getpagesize,
    getprogname,
    strtonum,
    syslog_r,
    syslog,
    timespecsub,
    timingsafe_bcmp,
    timingsafe_memcmp,
    memmem,
    clock_gettime,
};

pub const CFunctionDependencyDependencies = struct {
    const getentropy = [_]CFunctionDependency{.arc4random_buf};
};

pub const CFunctionDependencyHeaders = struct {
    const clock_gettime = [_][]const u8{"time.h"};
};

pub const CFunctionDependencyUniversalBackupSourceFiles = struct {
    const asprintf = [_][]const u8{"crypto/compat/bsd-asprintf.c"};
    const freezero = [_][]const u8{"crypto/compat/freezero.c"};
    const getpagesize = [_][]const u8{"crypto/compat/getpagesize.c"};
    const reallocarray = [_][]const u8{"crypto/compat/reallocarray.c"};
    const recallocarray = [_][]const u8{"crypto/compat/recallocarray.c"};
    const strcasecmp = [_][]const u8{"crypto/compat/strcasecmp.c"};
    const strlcat = [_][]const u8{"crypto/compat/strlcat.c"};
    const strlcpy = [_][]const u8{"crypto/compat/strlcpy.c"};
    const strndup = [_][]const u8{"crypto/compat/strndup.c"};
    const strnlen = [_][]const u8{"crypto/compat/strnlen.c"};
    const strsep = [_][]const u8{"crypto/compat/strsep.c"};
    const strtonum = [_][]const u8{"crypto/compat/strtonum.c"};
    const syslog_r = [_][]const u8{"crypto/compat/syslog_r.c"};
    const timegm = [_][]const u8{"crypto/compat/timegm.c"};
    const timingsafe_memcmp = [_][]const u8{"crypto/compat/timingsafe_memcmp.c"};
    const timingsafe_bcmp = [_][]const u8{"crypto/compat/timingsafe_bcmp.c"};
    const arc4random_buf = [_][]const u8{"crypto/compat/arc4random.c"};
    const arc4random_uniform = [_][]const u8{"crypto/compat/arc4random_uniform.c"};
    const explicit_bzero = [_][]const u8{"crypto/compat/explicit_bzero.c"};
    const getprogname = [_][]const u8{"compat/getprogname_unimpl.c"};

    // const getauxval = null;
    // const getentropy = null;
    // const syslog = null;
    // const clock_gettime = null;
    // const memmem = null;
    // const timespecsub = null;
};

pub const CFunctionDependencyWindowsBackupSourceFiles = struct {
    const explicit_bzero = [_][]const u8{"crypto/compat/explicit_bzero_win.c"};
    const getprogname = [_][]const u8{"crypto/compat/getprogname_windows.c"};
    const getentropy = [_][]const u8{"crypto/compat/getentropy_win.c"};
};

pub const CFunctionDependencyLinuxBackupSourceFiles = struct {
    const getprogname = [_][]const u8{"crypto/compat/getprogname_linux.c"};
    const getentropy = [_][]const u8{"crypto/compat/getentropy_linux.c"};
};

pub const CFunctionDependencyDarwinBackupSourceFiles = struct {
    const getentropy = [_][]const u8{"crypto/compat/getentropy_osx.c"};
};

/// Check the target for specific c functions and includes
const WideCDependencyStep = struct {
    const DependencyInfo = struct {
        maybe_target_has_symbol: ?bool,
        symbol_has_backup: bool = false,
    };
    const DependencyInfoMap = std.EnumMap(CFunctionDependency, DependencyInfo);

    c_function_dependency_map: DependencyInfoMap,
    c_flags: std.ArrayList([]const u8),
    c_source_files: std.ArrayList([]const u8),
    c_include_directories: std.ArrayList([]const u8),

    step: std.build.Step,
    builder: *std.build.Builder,
    c_function_dependencies: []const CFunctionDependency,
    c_include_dependencies: []const CIncludeDependencyBundle,

    pub fn init(
        builder: *std.build.Builder,
        comptime c_function_dependencies: []const CFunctionDependency,
        c_include_dependencies: []const CIncludeDependencyBundle,
        target: std.zig.CrossTarget,
    ) *WideCDependencyStep {
        const dependency_step = builder.allocator.create(WideCDependencyStep) catch unreachable;

        dependency_step.step = std.build.Step.init(
            .custom,
            @typeName(@This()),
            builder.allocator,
            WideCDependencyStep.make,
        );

        inline for (c_function_dependencies) |c_function_dependency| {
            CDependencyTestStep.addFunctionAsDependencyToStepWithBackupSource(
                builder,
                target,
                dependency_step,
                c_function_dependency,
                switch (target.getOsTag()) {
                    .windows => if (@hasDecl(CFunctionDependencyWindowsBackupSourceFiles, @tagName(c_function_dependency)))
                        &@field(CFunctionDependencyWindowsBackupSourceFiles, @tagName(c_function_dependency))
                    else if (@hasDecl(CFunctionDependencyUniversalBackupSourceFiles, @tagName(c_function_dependency)))
                        &@field(CFunctionDependencyUniversalBackupSourceFiles, @tagName(c_function_dependency))
                    else
                        null,
                    .linux => if (@hasDecl(CFunctionDependencyLinuxBackupSourceFiles, @tagName(c_function_dependency)))
                        &@field(CFunctionDependencyLinuxBackupSourceFiles, @tagName(c_function_dependency))
                    else if (@hasDecl(CFunctionDependencyUniversalBackupSourceFiles, @tagName(c_function_dependency)))
                        &@field(CFunctionDependencyUniversalBackupSourceFiles, @tagName(c_function_dependency))
                    else
                        null,
                    .macos => if (@hasDecl(CFunctionDependencyDarwinBackupSourceFiles, @tagName(c_function_dependency)))
                        &@field(CFunctionDependencyDarwinBackupSourceFiles, @tagName(c_function_dependency))
                    else if (@hasDecl(CFunctionDependencyUniversalBackupSourceFiles, @tagName(c_function_dependency)))
                        &@field(CFunctionDependencyUniversalBackupSourceFiles, @tagName(c_function_dependency))
                    else
                        null,
                    else => if (@hasDecl(CFunctionDependencyUniversalBackupSourceFiles, @tagName(c_function_dependency)))
                        &@field(CFunctionDependencyUniversalBackupSourceFiles, @tagName(c_function_dependency))
                    else
                        null,
                },
                if (@hasDecl(CFunctionDependencyDependencies, @tagName(c_function_dependency)))
                    &@field(CFunctionDependencyDependencies, @tagName(c_function_dependency))
                else
                    null,
            );
        }

        for (c_include_dependencies) |dependency_bundle| {
            CDependencyTestStep.addIncludesAsDependencyToStep(builder, target, dependency_step, dependency_bundle);
        }

        dependency_step.c_function_dependency_map = std.EnumMap(CFunctionDependency, DependencyInfo).initFull(DependencyInfo{
            .maybe_target_has_symbol = null,
        });
        dependency_step.c_flags = std.ArrayList([]const u8).init(builder.allocator);
        dependency_step.c_source_files = std.ArrayList([]const u8).init(builder.allocator);
        dependency_step.c_include_directories = std.ArrayList([]const u8).init(builder.allocator);
        dependency_step.c_function_dependencies = c_function_dependencies;
        dependency_step.c_include_dependencies = c_include_dependencies;

        switch (target.getOsTag()) {
            .macos => dependency_step.c_flags.append("-fno-common") catch unreachable,
            .openbsd => dependency_step.c_flags.appendSlice(&[_][]const u8{
                "-DHAVE_ATTRIBUTE__BOUNDED__",
                "-DHAVE_ATTRIBUTE__DEAD__",
            }) catch unreachable,
            .linux => dependency_step.c_flags.appendSlice(&[_][]const u8{
                "-D_DEFAULT_SOURCE",
                "-D_BSD_SOURCE",
                "-D_POSIX_SOURCE",
                "-D_GNU_SOURCE",
            }) catch unreachable,
            .windows => dependency_step.c_flags.appendSlice(&[_][]const u8{
                "-D_POSIX_SOURCE",
                "-D__USE_MINGW_ANSI_STDIO",
                "-D_POSIX",
                "-D_GNU_SOURCE",
            }) catch unreachable,
            else => {},
        }

        dependency_step.c_flags.appendSlice(&[_][]const u8{
            "-O2",
            "-Wall",
        }) catch unreachable;

        return dependency_step;
    }

    pub fn make(step: *std.build.Step) anyerror!void {
        _ = step;
        // no-op, this step is only a common dependency for other steps
    }
};

const ChangeBuildRootStep = struct {
    step: std.build.Step,
    builder: *std.build.Builder,

    is_revert: bool = false,
    maybe_new_build_root: ?[]const u8,
    maybe_revert_step: ?*ChangeBuildRootStep,

    pub fn init(
        builder: *std.build.Builder,
        maybe_new_build_root: ?[]const u8,
        maybe_revert_step: ?*ChangeBuildRootStep,
    ) *ChangeBuildRootStep {
        const change_build_root_step = builder.allocator.create(ChangeBuildRootStep) catch unreachable;

        change_build_root_step.step = std.build.Step.init(
            .custom,
            @typeName(@This()),
            builder.allocator,
            ChangeBuildRootStep.make,
        );
        change_build_root_step.is_revert = false;
        change_build_root_step.maybe_new_build_root = maybe_new_build_root;
        change_build_root_step.maybe_revert_step = maybe_revert_step;
        change_build_root_step.builder = builder;

        return change_build_root_step;
    }

    pub fn make(step: *std.build.Step) anyerror!void {
        const change_build_root_step: *ChangeBuildRootStep = @fieldParentPtr(ChangeBuildRootStep, "step", step);

        if (change_build_root_step.maybe_new_build_root) |new_build_root| {
            if (change_build_root_step.maybe_revert_step) |revert_step| {
                if (change_build_root_step.builder.verbose) {
                    out.debug("({*}) Setting revert step at {*} to '{s}'", .{ change_build_root_step, revert_step, change_build_root_step.builder.build_root });
                }
                revert_step.maybe_new_build_root = try change_build_root_step.builder.allocator.dupe(u8, change_build_root_step.builder.build_root);
                revert_step.is_revert = true;
            }

            if (change_build_root_step.builder.verbose) {
                if (change_build_root_step.is_revert) {
                    out.info("({*}) Reverting build root to '{s}'", .{ change_build_root_step, new_build_root });
                } else {
                    out.info("({*}) Changing build root to '{s}'", .{ change_build_root_step, new_build_root });
                }
            }
            change_build_root_step.builder.build_root = new_build_root;
        } else if (change_build_root_step.builder.verbose)
            out.err("ChangeBuildRootStep without new build root!", .{});
    }
};

/// Exposes ArrayLists for C source files & flags and adds them to the LibExeObjStep at `make`time
const DeferredLibExeObjStep = struct {
    const WorkingDirectoryPayload = struct {
        working_directory: []const u8,
        parent_step: *std.build.Step,
    };

    step: std.build.Step,
    builder: *std.build.Builder,
    lib_exe_obj_step: *std.build.LibExeObjStep,

    include_directories: std.ArrayList([]const u8),
    assembly_files: std.ArrayList([]const u8),
    c_source_files: std.ArrayList([]const u8),
    c_flags: std.ArrayList([]const u8),

    maybe_working_directory_payload: ?WorkingDirectoryPayload,
    maybe_revert_build_root_step: ?*ChangeBuildRootStep,

    c_function_dependency_step: *WideCDependencyStep,

    pub fn debugDependencyMap(deferred_step: *DeferredLibExeObjStep) void {
        var iterator = deferred_step.c_function_dependency_map.iterator();
        while (iterator.next()) |entry| {
            out.info("{s}: {}", .{ @tagName(entry.key), entry.value });
        }
    }

    pub fn init(
        builder: *std.build.Builder,
        lib_exe_obj_step: *std.build.LibExeObjStep,
        c_function_dependency_step: *WideCDependencyStep,
        maybe_working_directory_payload: ?WorkingDirectoryPayload,
    ) *DeferredLibExeObjStep {
        const deferred_step = builder.allocator.create(DeferredLibExeObjStep) catch unreachable;

        deferred_step.step = std.build.Step.init(
            .custom,
            @typeName(@This()),
            builder.allocator,
            DeferredLibExeObjStep.make,
        );
        deferred_step.builder = builder;
        deferred_step.lib_exe_obj_step = lib_exe_obj_step;

        deferred_step.include_directories = std.ArrayList([]const u8).init(builder.allocator);
        deferred_step.assembly_files = std.ArrayList([]const u8).init(builder.allocator);
        deferred_step.c_source_files = std.ArrayList([]const u8).init(builder.allocator);
        deferred_step.c_flags = std.ArrayList([]const u8).init(builder.allocator);
        deferred_step.maybe_working_directory_payload = maybe_working_directory_payload;

        deferred_step.c_function_dependency_step = c_function_dependency_step;

        deferred_step.step.dependOn(&c_function_dependency_step.step);
        if (maybe_working_directory_payload) |working_directory_payload| {
            const revert_build_root_step = ChangeBuildRootStep.init(builder, null, null);
            const set_new_build_root_step = ChangeBuildRootStep.init(builder, working_directory_payload.working_directory, revert_build_root_step);

            deferred_step.lib_exe_obj_step.step.dependOn(&set_new_build_root_step.step);
            revert_build_root_step.step.dependOn(&deferred_step.lib_exe_obj_step.step);
            deferred_step.maybe_revert_build_root_step = revert_build_root_step;
        } else {
            deferred_step.maybe_revert_build_root_step = null;
        }
        deferred_step.lib_exe_obj_step.step.dependOn(&deferred_step.step);

        return deferred_step;
    }

    pub fn make(step: *std.build.Step) anyerror!void {
        const deferred_lib_exe_obj_step: *DeferredLibExeObjStep = @fieldParentPtr(DeferredLibExeObjStep, "step", step);

        if (deferred_lib_exe_obj_step.builder.verbose) {
            out.info("{s} (C Function Dependencies) Adding {} source files, {} flags, and {} includes", .{
                deferred_lib_exe_obj_step.lib_exe_obj_step.name,
                deferred_lib_exe_obj_step.c_function_dependency_step.c_source_files.items.len,
                deferred_lib_exe_obj_step.c_function_dependency_step.c_flags.items.len,
                deferred_lib_exe_obj_step.c_function_dependency_step.c_source_files.items.len,
            });
        }

        deferred_lib_exe_obj_step.c_source_files.appendSlice(deferred_lib_exe_obj_step.c_function_dependency_step.c_source_files.items) catch unreachable;
        deferred_lib_exe_obj_step.c_flags.appendSlice(deferred_lib_exe_obj_step.c_function_dependency_step.c_flags.items) catch unreachable;
        deferred_lib_exe_obj_step.include_directories.appendSlice(deferred_lib_exe_obj_step.c_function_dependency_step.c_include_directories.items) catch unreachable;

        if (deferred_lib_exe_obj_step.builder.verbose) {
            out.debug("{s} C source files:", .{deferred_lib_exe_obj_step.lib_exe_obj_step.name});
            for (deferred_lib_exe_obj_step.c_source_files.items) |c_source_file| {
                out.debug("\t{s}", .{c_source_file});
            }
        }

        if (deferred_lib_exe_obj_step.builder.verbose) {
            out.debug("{s} C flags:", .{deferred_lib_exe_obj_step.lib_exe_obj_step.name});
            for (deferred_lib_exe_obj_step.c_flags.items) |c_flag| {
                out.debug("\t{s}", .{c_flag});
            }
        }

        deferred_lib_exe_obj_step.lib_exe_obj_step.addCSourceFiles(deferred_lib_exe_obj_step.c_source_files.items, deferred_lib_exe_obj_step.c_flags.items);

        if (deferred_lib_exe_obj_step.builder.verbose) {
            out.debug("{s} C Include directories:", .{deferred_lib_exe_obj_step.lib_exe_obj_step.name});
            for (deferred_lib_exe_obj_step.include_directories.items) |directory| {
                out.debug("\t{s}", .{directory});
            }
        }
        for (deferred_lib_exe_obj_step.include_directories.items) |directory| {
            deferred_lib_exe_obj_step.lib_exe_obj_step.addIncludePath(directory);
        }

        for (deferred_lib_exe_obj_step.assembly_files.items) |file| {
            deferred_lib_exe_obj_step.lib_exe_obj_step.addAssemblyFile(file);
        }
    }
};

/// Spawns a child `zig cc` process that checks whether or not the build target
/// has access to a certain c function or include
const CDependencyTestStep = struct {
    // hijacked from CMake source (CheckFunctionExists.c)
    const template_c_source =
        \\char {s}(void);
        \\int main(int ac, char* av[]) {{
        \\  {s}();
        \\  if (ac > 1000) {{
        \\    return *av[0];
        \\  }}
        \\  return 0;
        \\}}
    ;
    const no_function_template_c_source =
        \\int main(void){return 0;}
    ;

    const OnDetermineIfFunctionExistsFn = std.meta.FnPtr(fn (*WideCDependencyStep, bool, *anyopaque) void);

    step: std.build.Step,
    c_function_dependency_step: *WideCDependencyStep,
    rich_step: *DeferredLibExeObjStep,
    builder: *std.build.Builder,
    target: std.zig.CrossTarget,

    maybe_function: ?CFunctionDependency,
    maybe_include_header_files: ?[]const []const u8 = null,

    on_determine_fn: OnDetermineIfFunctionExistsFn,
    on_determine_fn_context: *anyopaque,

    pub fn init(
        builder: *std.build.Builder,
        target: std.zig.CrossTarget,
        maybe_function: ?CFunctionDependency,
        maybe_include_header_files: ?[]const []const u8,
        c_function_dependency_step: *WideCDependencyStep,
        on_determine_fn: OnDetermineIfFunctionExistsFn,
        on_determine_fn_context: *anyopaque,
    ) *CDependencyTestStep {
        std.debug.assert(maybe_function != null or maybe_include_header_files != null);
        var step = builder.allocator.create(CDependencyTestStep) catch unreachable;
        step.maybe_function = maybe_function;
        step.maybe_include_header_files = maybe_include_header_files;

        step.builder = builder;
        step.target = target;
        step.on_determine_fn = on_determine_fn;
        step.on_determine_fn_context = on_determine_fn_context;
        step.c_function_dependency_step = c_function_dependency_step;
        step.step = std.build.Step.init(
            .custom,
            if (maybe_function) |function|
                std.fmt.allocPrint(builder.allocator, "has-{s}", .{@tagName(function)}) catch unreachable
            else if (maybe_include_header_files) |include_header_files| blk: {
                var header_names = std.mem.join(builder.allocator, "-", include_header_files) catch unreachable;
                break :blk std.fmt.allocPrint(builder.allocator, "has-{s}", .{header_names}) catch unreachable;
            } else unreachable,
            builder.allocator,
            CDependencyTestStep.make,
        );
        return step;
    }

    fn checkIfIncludesExist(c_dependency_step: *CDependencyTestStep, include_headers: []const []const u8, c_checks_root_path: []const u8) anyerror!void {
        var source_file = std.ArrayList(u8).init(c_dependency_step.builder.allocator);
        var source_file_writer = source_file.writer();

        for (include_headers) |include_path| {
            try source_file_writer.print("#include <{s}>\n", .{include_path});
        }
        try source_file_writer.writeAll(CDependencyTestStep.no_function_template_c_source);

        var md5_output_buf: [std.crypto.hash.Md5.digest_length]u8 = undefined;
        std.crypto.hash.Md5.hash(source_file.items, &md5_output_buf, .{});

        const c_function_test_path = try std.fs.path.join(c_dependency_step.builder.allocator, &[_][]const u8{
            c_checks_root_path,
            try std.fmt.allocPrint(c_dependency_step.builder.allocator, "{s}.c", .{std.fmt.fmtSliceHexLower(&md5_output_buf)}),
        });

        var maybe_file = std.fs.cwd().createFile(c_function_test_path, .{ .exclusive = true }) catch null;
        if (maybe_file) |file| {
            defer file.close();

            var file_writer = file.writer();
            try file_writer.writeAll(source_file.items);
        }

        var compile_command = std.ArrayList([]const u8).init(c_dependency_step.builder.allocator);
        compile_command.appendSlice(&[_][]const u8{
            c_dependency_step.builder.zig_exe,
            "cc",
            "-target",
            c_dependency_step.target.linuxTriple(c_dependency_step.builder.allocator) catch unreachable,
            c_function_test_path,
        }) catch unreachable;

        const command = std.mem.join(c_dependency_step.builder.allocator, " ", compile_command.items) catch unreachable;

        if (c_dependency_step.builder.verbose) {
            out.info("Running '{s}'", .{command});
        }

        const compile_command_result = try std.ChildProcess.exec(.{
            .allocator = c_dependency_step.builder.allocator,
            .argv = compile_command.items,
        });

        // out.info("{s}", .{compile_command_result.stderr});
        // out.info("{}", .{compile_command_result.term});

        const compiled_successfully = compile_command_result.term == .Exited and compile_command_result.term.Exited == 0;
        c_dependency_step.on_determine_fn(c_dependency_step.c_function_dependency_step, compiled_successfully, c_dependency_step.on_determine_fn_context);
    }

    fn checkIfFunctionExists(c_dependency_step: *CDependencyTestStep, function: CFunctionDependency, c_checks_root_path: []const u8) anyerror!void {
        var source_file = std.ArrayList(u8).init(c_dependency_step.builder.allocator);
        var source_file_writer = source_file.writer();

        if (c_dependency_step.maybe_include_header_files) |header_files| {
            for (header_files) |include_path| {
                try source_file_writer.print("#include <{s}>\n", .{include_path});
            }
        }

        try source_file_writer.print(template_c_source, .{ @tagName(function), @tagName(function) });

        var md5_output_buf: [std.crypto.hash.Md5.digest_length]u8 = undefined;
        std.crypto.hash.Md5.hash(source_file.items, &md5_output_buf, .{});

        const c_function_test_path = try std.fs.path.join(c_dependency_step.builder.allocator, &[_][]const u8{
            c_checks_root_path,
            try std.fmt.allocPrint(c_dependency_step.builder.allocator, "{s}.c", .{std.fmt.fmtSliceHexLower(&md5_output_buf)}),
        });

        var maybe_file = std.fs.cwd().createFile(c_function_test_path, .{ .exclusive = true }) catch null;
        if (maybe_file) |file| {
            defer file.close();

            var file_writer = file.writer();
            try file_writer.writeAll(source_file.items);
        }

        var compile_command = std.ArrayList([]const u8).init(c_dependency_step.builder.allocator);
        compile_command.appendSlice(&[_][]const u8{
            c_dependency_step.builder.zig_exe,
            "cc",
            "-target",
            c_dependency_step.target.linuxTriple(c_dependency_step.builder.allocator) catch unreachable,
            c_function_test_path,
        }) catch unreachable;

        const command = std.mem.join(c_dependency_step.builder.allocator, " ", compile_command.items) catch unreachable;

        if (c_dependency_step.builder.verbose) {
            out.info("Running '{s}'", .{command});
        }

        const compile_command_result = try std.ChildProcess.exec(.{
            .allocator = c_dependency_step.builder.allocator,
            .argv = compile_command.items,
        });

        // out.info("{s}", .{compile_command_result.stderr});
        // out.info("{}", .{compile_command_result.term});

        const compiled_successfully = compile_command_result.term == .Exited and (compile_command_result.term.Exited == 0 or (compile_command_result.term.Exited == 1 and std.mem.indexOf(u8, compile_command_result.stderr, "conflicting types") != null));
        c_dependency_step.on_determine_fn(c_dependency_step.c_function_dependency_step, compiled_successfully, c_dependency_step.on_determine_fn_context);
    }

    pub fn make(step: *std.build.Step) anyerror!void {
        const c_dependency_step: *CDependencyTestStep = @fieldParentPtr(CDependencyTestStep, "step", step);
        const c_checks_root_path = c_dependency_step.builder.global_cache_root;

        if (c_dependency_step.maybe_function) |function| {
            try c_dependency_step.checkIfFunctionExists(function, c_checks_root_path);
        } else if (c_dependency_step.maybe_include_header_files) |include_header_files| {
            try c_dependency_step.checkIfIncludesExist(include_header_files, c_checks_root_path);
        } else unreachable;
    }

    pub fn addFunctionAsDependencyToStep(
        builder: *std.build.Builder,
        target: std.zig.CrossTarget,
        c_function_dependency_step: *WideCDependencyStep,
        comptime function: CFunctionDependency,
        on_determine_fn: OnDetermineIfFunctionExistsFn,
        on_determine_fn_context: *anyopaque,
    ) void {
        const maybe_include_header_files =
            if (@hasDecl(CFunctionDependencyHeaders, @tagName(function)))
            &@field(CFunctionDependencyHeaders, @tagName(function))
        else
            null;

        var c_dependency_test_step = CDependencyTestStep.init(builder, target, function, maybe_include_header_files, c_function_dependency_step, on_determine_fn, on_determine_fn_context);
        c_function_dependency_step.step.dependOn(&c_dependency_test_step.step);
    }

    const FunctionCompatContext = struct {
        maybe_compat_file_source_paths: ?[]const []const u8,
        maybe_dependencies: ?[]const CFunctionDependency,
        c_function_dependency_step: *WideCDependencyStep,
        function: CFunctionDependency,
        builder: *std.build.Builder,
    };

    const IncludeCompatContext = struct {
        include_dependency_bundle: CIncludeDependencyBundle,
        builder: *std.build.Builder,
    };

    pub fn addIncludesAsDependencyToStep(
        builder: *std.build.Builder,
        target: std.zig.CrossTarget,
        source_c_function_dependency_step: *WideCDependencyStep,
        include_dependency_bundle: CIncludeDependencyBundle,
    ) void {
        const compat_context = builder.allocator.create(IncludeCompatContext) catch unreachable;
        compat_context.builder = builder;
        compat_context.include_dependency_bundle = include_dependency_bundle;

        var c_dependency_test_step = CDependencyTestStep.init(builder, target, null, include_dependency_bundle.headers, source_c_function_dependency_step, struct {
            fn onDetermine(c_function_dependency_step: *WideCDependencyStep, has_include: bool, context: *anyopaque) void {
                const inner_compat_context = @ptrCast(*IncludeCompatContext, @alignCast(@alignOf(*FunctionCompatContext), context));
                var pretty_header_names = std.mem.join(inner_compat_context.builder.allocator, ", ", inner_compat_context.include_dependency_bundle.headers) catch unreachable;
                if (has_include) {
                    if (inner_compat_context.builder.verbose) {
                        out.info("Target has {s}", .{pretty_header_names});
                    }
                    c_function_dependency_step.c_flags.append(inner_compat_context.include_dependency_bundle.c_flag) catch unreachable;
                } else {
                    if (inner_compat_context.builder.verbose) {
                        out.info("Target does NOT have {s}", .{pretty_header_names});
                    }
                }
            }
        }.onDetermine, @ptrCast(*anyopaque, compat_context));

        source_c_function_dependency_step.step.dependOn(&c_dependency_test_step.step);
    }

    pub fn addFunctionAsDependencyToStepWithBackupSource(
        builder: *std.build.Builder,
        target: std.zig.CrossTarget,
        source_c_function_dependency_step: *WideCDependencyStep,
        comptime function: CFunctionDependency,
        maybe_compat_source_files_paths: ?[]const []const u8,
        maybe_dependencies: ?[]const CFunctionDependency,
    ) void {
        const compat_context = builder.allocator.create(FunctionCompatContext) catch unreachable;
        compat_context.builder = builder;
        compat_context.function = function;
        compat_context.maybe_compat_file_source_paths = maybe_compat_source_files_paths;
        compat_context.maybe_dependencies = maybe_dependencies;
        compat_context.c_function_dependency_step = source_c_function_dependency_step;

        CDependencyTestStep.addFunctionAsDependencyToStep(builder, target, source_c_function_dependency_step, function, struct {
            fn onDetermine(c_function_dependency_step: *WideCDependencyStep, has_function: bool, context: *anyopaque) void {
                const inner_compat_context = @ptrCast(*FunctionCompatContext, @alignCast(@alignOf(*FunctionCompatContext), context));
                inner_compat_context.c_function_dependency_step.c_function_dependency_map.getPtr(inner_compat_context.function).?.maybe_target_has_symbol = has_function;
                if (!has_function) {
                    var backup_compat_files_log = std.ArrayList(u8).init(inner_compat_context.builder.allocator);
                    const backup_compat_files_log_writer = backup_compat_files_log.writer();

                    if (inner_compat_context.maybe_dependencies) |dependencies| {
                        for (dependencies) |dependency| {
                            const value: WideCDependencyStep.DependencyInfo = inner_compat_context.c_function_dependency_step.c_function_dependency_map.get(dependency) orelse unreachable;
                            if (value.maybe_target_has_symbol) |has_symbol| {
                                if (has_symbol) {
                                    if (inner_compat_context.builder.verbose) {
                                        out.info("Skipping '{s}', dependency '{s}' exists!", .{ @tagName(inner_compat_context.function), @tagName(dependency) });
                                    }
                                    return;
                                }
                            } else @panic("Symbol DAG was misconfigured!");
                        }
                    }

                    if (inner_compat_context.maybe_compat_file_source_paths) |compat_file_source_paths| {
                        for (compat_file_source_paths) |source_file, index| {
                            c_function_dependency_step.c_source_files.append(source_file) catch unreachable;
                            if (index == compat_file_source_paths.len - 1) {
                                backup_compat_files_log_writer.print("'{s}'", .{source_file}) catch unreachable;
                            } else {
                                backup_compat_files_log_writer.print("'{s}', ", .{source_file}) catch unreachable;
                            }
                        }
                        if (inner_compat_context.builder.verbose) {
                            out.info("Target does NOT have '{s}', substituting with {s}", .{ @tagName(inner_compat_context.function), backup_compat_files_log.items });
                        }
                    } else {
                        if (inner_compat_context.builder.verbose) {
                            out.info("Target does NOT have '{s}'", .{@tagName(inner_compat_context.function)});
                        }
                    }
                } else {
                    if (inner_compat_context.builder.verbose) {
                        out.info("Target has '{s}'", .{@tagName(inner_compat_context.function)});
                    }
                    const uppercase_function_name =
                        std.ascii.allocUpperString(inner_compat_context.builder.allocator, @tagName(inner_compat_context.function)) catch unreachable;
                    c_function_dependency_step.c_flags.append(
                        std.fmt.allocPrint(inner_compat_context.builder.allocator, "-DHAVE_{s}", .{uppercase_function_name}) catch unreachable,
                    ) catch unreachable;
                }
            }
        }.onDetermine, @ptrCast(*anyopaque, compat_context));
    }
};

fn prefixStringArray(comptime prefix: []const u8, comptime input: []const []const u8) []const []const u8 {
    comptime var output: [input.len][]const u8 = undefined;
    inline for (input) |item, index| {
        output[index] = prefix ++ item;
    }
    return &output;
}

pub fn addPlatformLibrariesToStep(
    step: *std.build.LibExeObjStep,
    target: std.zig.CrossTarget,
) void {
    _ = step;
    _ = target;
    // step.linkSystemLibraryNeeded("");
}

// TODO(haze): a shit ton of autoconf conditionals
pub fn createLibCryptoStep(
    builder: *std.build.Builder,
    mode: std.builtin.Mode,
    target: std.zig.CrossTarget,
    c_function_dependency_step: *WideCDependencyStep,
    maybe_working_directory: ?DeferredLibExeObjStep.WorkingDirectoryPayload,
) !*DeferredLibExeObjStep {
    const raw_libcrypto_step = builder.addStaticLibrary("crypto", null);
    raw_libcrypto_step.strip = true;
    raw_libcrypto_step.setTarget(target);
    raw_libcrypto_step.setBuildMode(mode);
    raw_libcrypto_step.linkLibC();
    const libcrypto = DeferredLibExeObjStep.init(builder, raw_libcrypto_step, c_function_dependency_step, maybe_working_directory);

    const raw_libcrypto_base_sources = [_][]const u8{
        "cpt_err.c",
        "cryptlib.c",
        "crypto_init.c",
        "cversion.c",
        "ex_data.c",
        "malloc-wrapper.c",
        "mem_clr.c",
        "mem_dbg.c",
        "o_fips.c",
        "o_init.c",
        "o_str.c",
        "o_time.c",
        "aes/aes_cfb.c",
        "aes/aes_ctr.c",
        "aes/aes_ecb.c",
        "aes/aes_ige.c",
        "aes/aes_misc.c",
        "aes/aes_ofb.c",
        "aes/aes_wrap.c",
        "asn1/a_bitstr.c",
        "asn1/a_enum.c",
        "asn1/a_int.c",
        "asn1/a_mbstr.c",
        "asn1/a_object.c",
        "asn1/a_octet.c",
        "asn1/a_pkey.c",
        "asn1/a_print.c",
        "asn1/a_pubkey.c",
        "asn1/a_strex.c",
        "asn1/a_string.c",
        "asn1/a_strnid.c",
        "asn1/a_time.c",
        "asn1/a_time_tm.c",
        "asn1/a_type.c",
        "asn1/a_utf8.c",
        "asn1/ameth_lib.c",
        "asn1/asn1_err.c",
        "asn1/asn1_gen.c",
        "asn1/asn1_item.c",
        "asn1/asn1_lib.c",
        "asn1/asn1_old.c",
        "asn1/asn1_old_lib.c",
        "asn1/asn1_par.c",
        "asn1/asn1_types.c",
        "asn1/asn_mime.c",
        "asn1/asn_moid.c",
        "asn1/bio_asn1.c",
        "asn1/bio_ndef.c",
        "asn1/nsseq.c",
        "asn1/p5_pbe.c",
        "asn1/p5_pbev2.c",
        "asn1/p8_pkey.c",
        "asn1/t_crl.c",
        "asn1/t_pkey.c",
        "asn1/t_req.c",
        "asn1/t_spki.c",
        "asn1/t_x509.c",
        "asn1/t_x509a.c",
        "asn1/tasn_dec.c",
        "asn1/tasn_enc.c",
        "asn1/tasn_fre.c",
        "asn1/tasn_new.c",
        "asn1/tasn_prn.c",
        "asn1/tasn_typ.c",
        "asn1/tasn_utl.c",
        "asn1/x_algor.c",
        "asn1/x_attrib.c",
        "asn1/x_bignum.c",
        "asn1/x_crl.c",
        "asn1/x_exten.c",
        "asn1/x_info.c",
        "asn1/x_long.c",
        "asn1/x_name.c",
        "asn1/x_pkey.c",
        "asn1/x_pubkey.c",
        "asn1/x_req.c",
        "asn1/x_sig.c",
        "asn1/x_spki.c",
        "asn1/x_val.c",
        "asn1/x_x509.c",
        "asn1/x_x509a.c",
        "bf/bf_cfb64.c",
        "bf/bf_ecb.c",
        "bf/bf_enc.c",
        "bf/bf_ofb64.c",
        "bf/bf_skey.c",
        "bio/b_dump.c",
        "bio/b_print.c",
        "bio/b_sock.c",
        "bio/bf_buff.c",
        "bio/bf_nbio.c",
        "bio/bf_null.c",
        "bio/bio_cb.c",
        "bio/bio_err.c",
        "bio/bio_lib.c",
        "bio/bio_meth.c",
        "bio/bss_acpt.c",
        "bio/bss_bio.c",
        "bio/bss_conn.c",
        "bio/bss_dgram.c",
        "bio/bss_fd.c",
        "bio/bss_file.c",
        "bio/bss_mem.c",
        "bio/bss_null.c",
        "bio/bss_sock.c",
        "bn/bn_add.c",
        "bn/bn_asm.c",
        "bn/bn_blind.c",
        "bn/bn_bpsw.c",
        "bn/bn_const.c",
        "bn/bn_ctx.c",
        "bn/bn_depr.c",
        "bn/bn_div.c",
        "bn/bn_err.c",
        "bn/bn_exp.c",
        "bn/bn_exp2.c",
        "bn/bn_gcd.c",
        "bn/bn_gf2m.c",
        "bn/bn_isqrt.c",
        "bn/bn_kron.c",
        "bn/bn_lib.c",
        "bn/bn_mod.c",
        "bn/bn_mont.c",
        "bn/bn_mpi.c",
        "bn/bn_mul.c",
        "bn/bn_nist.c",
        "bn/bn_prime.c",
        "bn/bn_print.c",
        "bn/bn_rand.c",
        "bn/bn_recp.c",
        "bn/bn_shift.c",
        "bn/bn_sqr.c",
        "bn/bn_sqrt.c",
        "bn/bn_word.c",
        "bn/bn_x931p.c",
        "buffer/buf_err.c",
        "buffer/buf_str.c",
        "buffer/buffer.c",
        "bytestring/bs_ber.c",
        "bytestring/bs_cbb.c",
        "bytestring/bs_cbs.c",
        "camellia/cmll_cfb.c",
        "camellia/cmll_ctr.c",
        "camellia/cmll_ecb.c",
        "camellia/cmll_misc.c",
        "camellia/cmll_ofb.c",
        "cast/c_cfb64.c",
        "cast/c_ecb.c",
        "cast/c_enc.c",
        "cast/c_ofb64.c",
        "cast/c_skey.c",
        "chacha/chacha.c",
        "cmac/cm_ameth.c",
        "cmac/cm_pmeth.c",
        "cmac/cmac.c",
        "cms/cms_asn1.c",
        "cms/cms_att.c",
        "cms/cms_cd.c",
        "cms/cms_dd.c",
        "cms/cms_enc.c",
        "cms/cms_env.c",
        "cms/cms_err.c",
        "cms/cms_ess.c",
        "cms/cms_io.c",
        "cms/cms_kari.c",
        "cms/cms_lib.c",
        "cms/cms_pwri.c",
        "cms/cms_sd.c",
        "cms/cms_smime.c",
        "comp/c_rle.c",
        "comp/c_zlib.c",
        "comp/comp_err.c",
        "comp/comp_lib.c",
        "conf/conf_api.c",
        "conf/conf_def.c",
        "conf/conf_err.c",
        "conf/conf_lib.c",
        "conf/conf_mall.c",
        "conf/conf_mod.c",
        "conf/conf_sap.c",
        "ct/ct_b64.c",
        "ct/ct_err.c",
        "ct/ct_log.c",
        "ct/ct_oct.c",
        "ct/ct_policy.c",
        "ct/ct_prn.c",
        "ct/ct_sct.c",
        "ct/ct_sct_ctx.c",
        "ct/ct_vfy.c",
        "ct/ct_x509v3.c",
        "curve25519/curve25519-generic.c",
        "curve25519/curve25519.c",
        "des/cbc_cksm.c",
        "des/cbc_enc.c",
        "des/cfb64ede.c",
        "des/cfb64enc.c",
        "des/cfb_enc.c",
        "des/des_enc.c",
        "des/ecb3_enc.c",
        "des/ecb_enc.c",
        "des/ede_cbcm_enc.c",
        "des/enc_read.c",
        "des/enc_writ.c",
        "des/fcrypt.c",
        "des/fcrypt_b.c",
        "des/ofb64ede.c",
        "des/ofb64enc.c",
        "des/ofb_enc.c",
        "des/pcbc_enc.c",
        "des/qud_cksm.c",
        "des/rand_key.c",
        "des/set_key.c",
        "des/str2key.c",
        "des/xcbc_enc.c",
        "dh/dh_ameth.c",
        "dh/dh_asn1.c",
        "dh/dh_check.c",
        "dh/dh_depr.c",
        "dh/dh_err.c",
        "dh/dh_gen.c",
        "dh/dh_key.c",
        "dh/dh_lib.c",
        "dh/dh_pmeth.c",
        "dh/dh_prn.c",
        "dsa/dsa_ameth.c",
        "dsa/dsa_asn1.c",
        "dsa/dsa_depr.c",
        "dsa/dsa_err.c",
        "dsa/dsa_gen.c",
        "dsa/dsa_key.c",
        "dsa/dsa_lib.c",
        "dsa/dsa_meth.c",
        "dsa/dsa_ossl.c",
        "dsa/dsa_pmeth.c",
        "dsa/dsa_prn.c",
        "dsa/dsa_sign.c",
        "dsa/dsa_vrf.c",
        "dso/dso_dlfcn.c",
        "dso/dso_err.c",
        "dso/dso_lib.c",
        "dso/dso_null.c",
        "dso/dso_openssl.c",
        "ec/ec2_mult.c",
        "ec/ec2_oct.c",
        "ec/ec2_smpl.c",
        "ec/ec_ameth.c",
        "ec/ec_asn1.c",
        "ec/ec_check.c",
        "ec/ec_curve.c",
        "ec/ec_cvt.c",
        "ec/ec_err.c",
        "ec/ec_key.c",
        "ec/ec_kmeth.c",
        "ec/ec_lib.c",
        "ec/ec_mult.c",
        "ec/ec_oct.c",
        "ec/ec_pmeth.c",
        "ec/ec_print.c",
        "ec/eck_prn.c",
        "ec/ecp_mont.c",
        "ec/ecp_nist.c",
        "ec/ecp_oct.c",
        "ec/ecp_smpl.c",
        "ecdh/ecdh_kdf.c",
        "ecdh/ech_err.c",
        "ecdh/ech_key.c",
        "ecdh/ech_lib.c",
        "ecdsa/ecs_asn1.c",
        "ecdsa/ecs_err.c",
        "ecdsa/ecs_lib.c",
        "ecdsa/ecs_ossl.c",
        "ecdsa/ecs_sign.c",
        "ecdsa/ecs_vrf.c",
        "engine/eng_all.c",
        "engine/eng_cnf.c",
        "engine/eng_ctrl.c",
        "engine/eng_dyn.c",
        "engine/eng_err.c",
        "engine/eng_fat.c",
        "engine/eng_init.c",
        "engine/eng_lib.c",
        "engine/eng_list.c",
        "engine/eng_openssl.c",
        "engine/eng_pkey.c",
        "engine/eng_table.c",
        "engine/tb_asnmth.c",
        "engine/tb_cipher.c",
        "engine/tb_dh.c",
        "engine/tb_digest.c",
        "engine/tb_dsa.c",
        "engine/tb_ecdh.c",
        "engine/tb_ecdsa.c",
        "engine/tb_eckey.c",
        "engine/tb_pkmeth.c",
        "engine/tb_rand.c",
        "engine/tb_rsa.c",
        "engine/tb_store.c",
        "err/err.c",
        "err/err_all.c",
        "err/err_prn.c",
        "evp/bio_b64.c",
        "evp/bio_enc.c",
        "evp/bio_md.c",
        "evp/c_all.c",
        "evp/digest.c",
        "evp/e_aes.c",
        "evp/e_aes_cbc_hmac_sha1.c",
        "evp/e_bf.c",
        "evp/e_camellia.c",
        "evp/e_cast.c",
        "evp/e_chacha.c",
        "evp/e_chacha20poly1305.c",
        "evp/e_des.c",
        "evp/e_des3.c",
        "evp/e_gost2814789.c",
        "evp/e_idea.c",
        "evp/e_null.c",
        "evp/e_old.c",
        "evp/e_rc2.c",
        "evp/e_rc4.c",
        "evp/e_rc4_hmac_md5.c",
        "evp/e_sm4.c",
        "evp/e_xcbc_d.c",
        "evp/encode.c",
        "evp/evp_aead.c",
        "evp/evp_enc.c",
        "evp/evp_err.c",
        "evp/evp_key.c",
        "evp/evp_lib.c",
        "evp/evp_pbe.c",
        "evp/evp_pkey.c",
        "evp/m_gost2814789.c",
        "evp/m_gostr341194.c",
        "evp/m_md4.c",
        "evp/m_md5.c",
        "evp/m_md5_sha1.c",
        "evp/m_null.c",
        "evp/m_ripemd.c",
        "evp/m_sha1.c",
        "evp/m_sigver.c",
        "evp/m_streebog.c",
        "evp/m_sm3.c",
        "evp/m_wp.c",
        "evp/names.c",
        "evp/p5_crpt.c",
        "evp/p5_crpt2.c",
        "evp/p_dec.c",
        "evp/p_enc.c",
        "evp/p_lib.c",
        "evp/p_open.c",
        "evp/p_seal.c",
        "evp/p_sign.c",
        "evp/p_verify.c",
        "evp/pmeth_fn.c",
        "evp/pmeth_gn.c",
        "evp/pmeth_lib.c",
        "gost/gost2814789.c",
        "gost/gost89_keywrap.c",
        "gost/gost89_params.c",
        "gost/gost89imit_ameth.c",
        "gost/gost89imit_pmeth.c",
        "gost/gost_asn1.c",
        "gost/gost_err.c",
        "gost/gostr341001.c",
        "gost/gostr341001_ameth.c",
        "gost/gostr341001_key.c",
        "gost/gostr341001_params.c",
        "gost/gostr341001_pmeth.c",
        "gost/gostr341194.c",
        "gost/streebog.c",
        "hkdf/hkdf.c",
        "hmac/hm_ameth.c",
        "hmac/hm_pmeth.c",
        "hmac/hmac.c",
        "idea/i_cbc.c",
        "idea/i_cfb64.c",
        "idea/i_ecb.c",
        "idea/i_ofb64.c",
        "idea/i_skey.c",
        "kdf/hkdf_evp.c",
        "kdf/kdf_err.c",
        "lhash/lh_stats.c",
        "lhash/lhash.c",
        "md4/md4_dgst.c",
        "md4/md4_one.c",
        "md5/md5_dgst.c",
        "md5/md5_one.c",
        "modes/cbc128.c",
        "modes/ccm128.c",
        "modes/cfb128.c",
        "modes/ctr128.c",
        "modes/cts128.c",
        "modes/gcm128.c",
        "modes/ofb128.c",
        "modes/xts128.c",
        "objects/o_names.c",
        "objects/obj_dat.c",
        "objects/obj_err.c",
        "objects/obj_lib.c",
        "objects/obj_xref.c",
        "ocsp/ocsp_asn.c",
        "ocsp/ocsp_cl.c",
        "ocsp/ocsp_err.c",
        "ocsp/ocsp_ext.c",
        "ocsp/ocsp_ht.c",
        "ocsp/ocsp_lib.c",
        "ocsp/ocsp_prn.c",
        "ocsp/ocsp_srv.c",
        "ocsp/ocsp_vfy.c",
        "pem/pem_all.c",
        "pem/pem_err.c",
        "pem/pem_info.c",
        "pem/pem_lib.c",
        "pem/pem_oth.c",
        "pem/pem_pk8.c",
        "pem/pem_pkey.c",
        "pem/pem_sign.c",
        "pem/pem_x509.c",
        "pem/pem_xaux.c",
        "pem/pvkfmt.c",
        "pkcs12/p12_add.c",
        "pkcs12/p12_asn.c",
        "pkcs12/p12_attr.c",
        "pkcs12/p12_crpt.c",
        "pkcs12/p12_crt.c",
        "pkcs12/p12_decr.c",
        "pkcs12/p12_init.c",
        "pkcs12/p12_key.c",
        "pkcs12/p12_kiss.c",
        "pkcs12/p12_mutl.c",
        "pkcs12/p12_npas.c",
        "pkcs12/p12_p8d.c",
        "pkcs12/p12_p8e.c",
        "pkcs12/p12_sbag.c",
        "pkcs12/p12_utl.c",
        "pkcs12/pk12err.c",
        "pkcs7/bio_pk7.c",
        "pkcs7/pk7_asn1.c",
        "pkcs7/pk7_attr.c",
        "pkcs7/pk7_doit.c",
        "pkcs7/pk7_lib.c",
        "pkcs7/pk7_mime.c",
        "pkcs7/pk7_smime.c",
        "pkcs7/pkcs7err.c",
        "poly1305/poly1305.c",
        "rand/rand_err.c",
        "rand/rand_lib.c",
        "rand/randfile.c",
        "rc2/rc2_cbc.c",
        "rc2/rc2_ecb.c",
        "rc2/rc2_skey.c",
        "rc2/rc2cfb64.c",
        "rc2/rc2ofb64.c",
        "ripemd/rmd_dgst.c",
        "ripemd/rmd_one.c",
        "rsa/rsa_ameth.c",
        "rsa/rsa_asn1.c",
        "rsa/rsa_chk.c",
        "rsa/rsa_crpt.c",
        "rsa/rsa_depr.c",
        "rsa/rsa_eay.c",
        "rsa/rsa_err.c",
        "rsa/rsa_gen.c",
        "rsa/rsa_lib.c",
        "rsa/rsa_meth.c",
        "rsa/rsa_none.c",
        "rsa/rsa_oaep.c",
        "rsa/rsa_pk1.c",
        "rsa/rsa_pmeth.c",
        "rsa/rsa_prn.c",
        "rsa/rsa_pss.c",
        "rsa/rsa_saos.c",
        "rsa/rsa_sign.c",
        "rsa/rsa_x931.c",
        "sha/sha1_one.c",
        "sha/sha1dgst.c",
        "sha/sha256.c",
        "sha/sha512.c",
        "sm3/sm3.c",
        "sm4/sm4.c",
        "stack/stack.c",
        "ts/ts_asn1.c",
        "ts/ts_conf.c",
        "ts/ts_err.c",
        "ts/ts_lib.c",
        "ts/ts_req_print.c",
        "ts/ts_req_utils.c",
        "ts/ts_rsp_print.c",
        "ts/ts_rsp_sign.c",
        "ts/ts_rsp_utils.c",
        "ts/ts_rsp_verify.c",
        "ts/ts_verify_ctx.c",
        "txt_db/txt_db.c",
        "ui/ui_err.c",
        "ui/ui_lib.c",
        "ui/ui_util.c",
        "whrlpool/wp_dgst.c",
        "x509/by_dir.c",
        "x509/by_file.c",
        "x509/by_mem.c",
        "x509/pcy_cache.c",
        "x509/pcy_data.c",
        "x509/pcy_lib.c",
        "x509/pcy_map.c",
        "x509/pcy_node.c",
        "x509/pcy_tree.c",
        "x509/x509_addr.c",
        "x509/x509_akey.c",
        "x509/x509_akeya.c",
        "x509/x509_alt.c",
        "x509/x509_asid.c",
        "x509/x509_att.c",
        "x509/x509_bcons.c",
        "x509/x509_bitst.c",
        "x509/x509_cmp.c",
        "x509/x509_conf.c",
        "x509/x509_constraints.c",
        "x509/x509_cpols.c",
        "x509/x509_crld.c",
        "x509/x509_d2.c",
        "x509/x509_def.c",
        "x509/x509_enum.c",
        "x509/x509_err.c",
        "x509/x509_ext.c",
        "x509/x509_extku.c",
        "x509/x509_genn.c",
        "x509/x509_ia5.c",
        "x509/x509_info.c",
        "x509/x509_int.c",
        "x509/x509_issuer_cache.c",
        "x509/x509_lib.c",
        "x509/x509_lu.c",
        "x509/x509_ncons.c",
        "x509/x509_obj.c",
        "x509/x509_ocsp.c",
        "x509/x509_pci.c",
        "x509/x509_pcia.c",
        "x509/x509_pcons.c",
        "x509/x509_pku.c",
        "x509/x509_pmaps.c",
        "x509/x509_prn.c",
        "x509/x509_purp.c",
        "x509/x509_r2x.c",
        "x509/x509_req.c",
        "x509/x509_set.c",
        "x509/x509_skey.c",
        "x509/x509_sxnet.c",
        "x509/x509_trs.c",
        "x509/x509_txt.c",
        "x509/x509_utl.c",
        "x509/x509_v3.c",
        "x509/x509_verify.c",
        "x509/x509_vfy.c",
        "x509/x509_vpm.c",
        "x509/x509cset.c",
        "x509/x509name.c",
        "x509/x509rset.c",
        "x509/x509spki.c",
        "x509/x509type.c",
        "x509/x_all.c",
    };
    const libcrypto_base_sources = comptime prefixStringArray("crypto/", &raw_libcrypto_base_sources);

    const raw_libcrypto_unix_sources = [_][]const u8{
        "crypto_lock.c",
        "bio/b_posix.c",
        "bio/bss_log.c",
        "ui/ui_openssl.c",
    };
    const libcrypto_unix_sources = prefixStringArray("crypto/", &raw_libcrypto_unix_sources);

    const raw_libcrypto_macos_x86_64_asm_sources = [_][]const u8{
        "aes/aes-macosx-x86_64.S",
        "aes/bsaes-macosx-x86_64.S",
        "aes/vpaes-macosx-x86_64.S",
        "aes/aesni-macosx-x86_64.S",
        "aes/aesni-sha1-macosx-x86_64.S",
        "bn/modexp512-macosx-x86_64.S",
        "bn/mont-macosx-x86_64.S",
        "bn/mont5-macosx-x86_64.S",
        "bn/gf2m-macosx-x86_64.S",
        "camellia/cmll-macosx-x86_64.S",
        "md5/md5-macosx-x86_64.S",
        "modes/ghash-macosx-x86_64.S",
        "rc4/rc4-macosx-x86_64.S",
        "rc4/rc4-md5-macosx-x86_64.S",
        "sha/sha1-macosx-x86_64.S",
        "sha/sha256-macosx-x86_64.S",
        "sha/sha512-macosx-x86_64.S",
        "whrlpool/wp-macosx-x86_64.S",
        "cpuid-macosx-x86_64.S",
    };
    const libcrypto_macos_x86_64_asm_sources = prefixStringArray("crypto/", &raw_libcrypto_macos_x86_64_asm_sources);

    try libcrypto.c_flags.appendSlice(&[_][]const u8{ "-DLIBRESSL_CRYPTO_INTERNAL", "-DLIBRESSL_INTERNAL" });

    try libcrypto.c_flags.appendSlice(&[_][]const u8{
        "-DHAVE_NETINET_IP_H",

        "-DLIBRESSL_CRYPTO_INTERNAL",
        "-DOPENSSL_NO_HW_PADLOCK",
        "-DSIZEOF_TIME_T=8",
        "-D_PATH_SSL_CA_FILE=\"/Users/haze/code/libressl/tests/../cert.pem\"",
        "-D__BEGIN_HIDDEN_DECLS=",
        "-D__END_HIDDEN_DECLS=",
    });

    try libcrypto.c_source_files.appendSlice(libcrypto_base_sources);

    const target_is_asm_elf_x86_64 = target.getCpuArch() == .x86_64 and target.getOsTag() == .linux;
    // TODO(haze): Missimg MASM?
    const target_is_asm_macosx_x86_64 = target.getCpuArch() == .x86_64 and target.getOsTag() == .macos;
    const target_is_asm_mingw64_x86_64 = target.getCpuArch() == .x86_64 and target.getOsTag() == .windows;
    const target_is_asm_elf_armv4 = target.getCpuArch().isARM() and target.getOsTag() == .linux;

    if (!target_is_asm_elf_armv4 and !target_is_asm_macosx_x86_64 and !target_is_asm_mingw64_x86_64 and !target_is_asm_elf_x86_64) {
        const raw_crypto_sources = [_][]const u8{
            "aes/aes_core.c",
        };
        const crypto_sources = comptime prefixStringArray("crypto/", &raw_crypto_sources);
        try libcrypto.c_source_files.appendSlice(crypto_sources);
    }

    if (!target_is_asm_macosx_x86_64 and !target_is_asm_mingw64_x86_64 and !target_is_asm_elf_x86_64) {
        const raw_crypto_sources = [_][]const u8{
            "aes/aes_cbc.c",
            "camellia/camellia.c",
            "camellia/cmll_cbc.c",
            "rc4/rc4_enc.c",
            "rc4/rc4_skey.c",
            "whrlpool/wp_block.c",
        };
        const crypto_sources = comptime prefixStringArray("crypto/", &raw_crypto_sources);
        try libcrypto.c_source_files.appendSlice(crypto_sources);
    }

    switch (target.getOsTag()) {
        .macos => {
            try libcrypto.c_source_files.appendSlice(libcrypto_unix_sources);
            if (target.getCpuArch() == .x86_64) {
                try libcrypto.assembly_files.appendSlice(libcrypto_macos_x86_64_asm_sources);
                try libcrypto.c_flags.appendSlice(&[_][]const u8{
                    "-DAES_ASM",
                    "-DBSAES_ASM",
                    "-DVPAES_ASM",
                    "-DOPENSSL_IA32_SSE2",
                    "-DOPENSSL_BN_ASM_MONT",
                    "-DOPENSSL_BN_ASM_MONT5",
                    "-DOPENSSL_BN_ASM_GF2m",
                    "-DMD5_ASM",
                    "-DGHASH_ASM",
                    "-DRSA_ASM",
                    "-DSHA1_ASM",
                    "-DSHA256_ASM",
                    "-DSHA512_ASM",
                    "-DWHIRLPOOL_ASM",
                    "-DOPENSSL_CPUID_OBJ",
                });
            }
        },
        .linux => {
            try libcrypto.c_source_files.appendSlice(libcrypto_unix_sources);
        },
        else => {},
    }

    const raw_include_directories = [_][]const u8{
        "asn1",
        "bio",
        "bn",
        "bytestring",
        "dh",
        "dsa",
        "ec",
        "ecdh",
        "ecdsa",
        "evp",
        "hmac",
        "modes",
        "ocsp",
        "pkcs12",
        "rsa",
        "x509",
        ".",
        "../include/",
        "../include/compat",
    };
    const include_directories = comptime prefixStringArray("crypto/", &raw_include_directories);
    libcrypto.include_directories.appendSlice(include_directories) catch unreachable;

    return libcrypto;
}

pub fn createLibSslStep(
    builder: *std.build.Builder,
    mode: std.builtin.Mode,
    target: std.zig.CrossTarget,
    libcrypto_library: *std.build.LibExeObjStep,
    c_function_dependency_step: *WideCDependencyStep,
    maybe_working_directory: ?DeferredLibExeObjStep.WorkingDirectoryPayload,
) !*DeferredLibExeObjStep {
    const raw_libssl_step = builder.addStaticLibrary("ssl", null);
    raw_libssl_step.strip = true;
    raw_libssl_step.setTarget(target);
    raw_libssl_step.setBuildMode(mode);
    raw_libssl_step.linkLibC();
    const libssl = DeferredLibExeObjStep.init(builder, raw_libssl_step, c_function_dependency_step, maybe_working_directory);

    const raw_lib_ssl_source_files = [_][]const u8{
        "bio_ssl.c",
        "d1_both.c",
        "d1_lib.c",
        "d1_pkt.c",
        "d1_srtp.c",
        "pqueue.c",
        "s3_cbc.c",
        "s3_lib.c",
        "ssl_algs.c",
        "ssl_asn1.c",
        "ssl_both.c",
        "ssl_cert.c",
        "ssl_ciph.c",
        "ssl_ciphers.c",
        "ssl_clnt.c",
        "ssl_err.c",
        "ssl_init.c",
        "ssl_kex.c",
        "ssl_lib.c",
        "ssl_methods.c",
        "ssl_packet.c",
        "ssl_pkt.c",
        "ssl_rsa.c",
        "ssl_seclevel.c",
        "ssl_sess.c",
        "ssl_sigalgs.c",
        "ssl_srvr.c",
        "ssl_stat.c",
        "ssl_tlsext.c",
        "ssl_transcript.c",
        "ssl_txt.c",
        "ssl_versions.c",
        "t1_enc.c",
        "t1_lib.c",
        "tls_buffer.c",
        "tls_content.c",
        "tls_key_share.c",
        "tls_lib.c",
        "tls12_key_schedule.c",
        "tls12_lib.c",
        "tls12_record_layer.c",
        "tls13_client.c",
        "tls13_error.c",
        "tls13_handshake.c",
        "tls13_handshake_msg.c",
        "tls13_key_schedule.c",
        "tls13_legacy.c",
        "tls13_lib.c",
        "tls13_quic.c",
        "tls13_record.c",
        "tls13_record_layer.c",
        "tls13_server.c",
    };
    const lib_ssl_source_files = comptime prefixStringArray("ssl/", &raw_lib_ssl_source_files);

    const raw_include_directories = [_][]const u8{
        ".",
        "../crypto/bio",
        "../include/compat",
        "../include",
    };
    const include_directories = comptime prefixStringArray("ssl/", &raw_include_directories);

    libssl.include_directories.appendSlice(include_directories) catch unreachable;
    libssl.c_source_files.appendSlice(lib_ssl_source_files) catch unreachable;
    libssl.c_flags.appendSlice(&[_][]const u8{
        "-D__BEGIN_HIDDEN_DECLS=",
        "-D__END_HIDDEN_DECLS=",
        "-DLIBRESSL_INTERNAL",
    }) catch unreachable;

    libssl.step.dependOn(&libcrypto_library.step);

    return libssl;
}

pub fn createLibTlsStep(
    builder: *std.build.Builder,
    mode: std.builtin.Mode,
    target: std.zig.CrossTarget,
    libcrypto_library: *std.build.LibExeObjStep,
    libssl_library: *std.build.LibExeObjStep,
    c_function_dependency_step: *WideCDependencyStep,
    maybe_working_directory: ?DeferredLibExeObjStep.WorkingDirectoryPayload,
) !*DeferredLibExeObjStep {
    const raw_libtls_step = builder.addStaticLibrary("tls", null);
    raw_libtls_step.strip = true;
    raw_libtls_step.setTarget(target);
    raw_libtls_step.setBuildMode(mode);
    raw_libtls_step.linkLibC();
    const libtls = DeferredLibExeObjStep.init(builder, raw_libtls_step, c_function_dependency_step, maybe_working_directory);

    const raw_lib_tls_source_files = [_][]const u8{
        "tls.c",
        "tls_bio_cb.c",
        "tls_client.c",
        "tls_config.c",
        "tls_conninfo.c",
        "tls_keypair.c",
        "tls_server.c",
        "tls_signer.c",
        "tls_ocsp.c",
        "tls_peer.c",
        "tls_util.c",
        "tls_verify.c",
    };
    const lib_tls_source_files = comptime prefixStringArray("tls/", &raw_lib_tls_source_files);

    libtls.c_source_files.appendSlice(lib_tls_source_files) catch unreachable;

    const raw_include_directories = [_][]const u8{
        ".",
        "../include/compat",
        "../include",
    };
    const include_directories = comptime prefixStringArray("tls/", &raw_include_directories);

    libtls.include_directories.appendSlice(include_directories) catch unreachable;

    if (target.getOsTag() == .windows) {
        const raw_windows_compat_source_files = [_][]const u8{
            "compat/ftruncate.c",
            "compat/pread.c",
            "compat/pwrite.c",
        };
        const windows_compat_source_files = comptime prefixStringArray("tls/", &raw_windows_compat_source_files);
        libtls.c_source_files.appendSlice(windows_compat_source_files) catch unreachable;
    }

    libtls.c_flags.appendSlice(&[_][]const u8{
        "-D__BEGIN_HIDDEN_DECLS=",
        "-D__END_HIDDEN_DECLS=",
        "-DLIBRESSL_INTERNAL",
    }) catch unreachable;

    libtls.step.dependOn(&libssl_library.step);
    libtls.lib_exe_obj_step.linkLibrary(libcrypto_library);
    libtls.lib_exe_obj_step.linkLibrary(libssl_library);

    return libtls;
}

pub fn linkStepWithLibreSsl(
    builder: *std.build.Builder,
    target: std.zig.CrossTarget,
    mode: std.builtin.Mode,
    libressl_source_root: []const u8,
    input_step: *std.build.LibExeObjStep,
) !void {
    const required_c_functions = comptime std.enums.values(CFunctionDependency);
    const required_c_function_step = WideCDependencyStep.init(builder, required_c_functions, &CIncludeDependencies, target);

    const working_directory_payload = DeferredLibExeObjStep.WorkingDirectoryPayload{
        .working_directory = libressl_source_root,
        .parent_step = &input_step.step,
    };

    const libcrypto = try createLibCryptoStep(builder, mode, target, required_c_function_step, working_directory_payload);
    const libssl = try createLibSslStep(builder, mode, target, libcrypto.lib_exe_obj_step, required_c_function_step, working_directory_payload);
    const libtls = try createLibTlsStep(builder, mode, target, libcrypto.lib_exe_obj_step, libssl.lib_exe_obj_step, required_c_function_step, working_directory_payload);

    // the autogen step will run with the build_root changed, but if we check beforehand, use the source root
    const autogen_step = builder.addSystemCommand(&[_][]const u8{ "sh", "autogen.sh" });

    const openbsd_path = try std.fs.path.join(builder.allocator, &[_][]const u8{ libressl_source_root, "openbsd" });
    const openbsd_dir_result = std.fs.cwd().openDir(openbsd_path, .{});
    const needs_to_run_autogen = if (openbsd_dir_result) |_| false else |_| true;
    if (needs_to_run_autogen) {
        libcrypto.step.dependOn(&autogen_step.step);
        libssl.step.dependOn(&autogen_step.step);
        libtls.step.dependOn(&autogen_step.step);
    }

    input_step.step.dependOn(&libcrypto.maybe_revert_build_root_step.?.step);
    input_step.step.dependOn(&libssl.maybe_revert_build_root_step.?.step);
    input_step.step.dependOn(&libtls.maybe_revert_build_root_step.?.step);

    input_step.linkLibrary(libcrypto.lib_exe_obj_step);
    input_step.linkLibrary(libssl.lib_exe_obj_step);
    input_step.linkLibrary(libtls.lib_exe_obj_step);

    const libressl_include_path = try std.fs.path.join(builder.allocator, &[_][]const u8{ libressl_source_root, "include" });
    input_step.addIncludePath(libressl_include_path);
}

pub fn build(b: *std.build.Builder) !void {
    const mode = b.standardReleaseOptions();
    const target = b.standardTargetOptions(.{});

    const required_c_functions = comptime std.enums.values(CFunctionDependency);
    const required_c_function_step = WideCDependencyStep.init(b, required_c_functions, &CIncludeDependencies, target);

    const autogen_step = b.addSystemCommand(&[_][]const u8{ "sh", "autogen.sh" });

    const libcrypto = try createLibCryptoStep(b, mode, target, required_c_function_step, null);
    libcrypto.lib_exe_obj_step.install();

    const libssl = try createLibSslStep(b, mode, target, libcrypto.lib_exe_obj_step, required_c_function_step, null);
    libssl.lib_exe_obj_step.install();

    const libtls = try createLibTlsStep(b, mode, target, libcrypto.lib_exe_obj_step, libssl.lib_exe_obj_step, required_c_function_step, null);
    libtls.lib_exe_obj_step.install();

    const openbsd_dir_result = std.fs.cwd().openDir("openbsd", .{});
    const needs_to_run_autogen = if (openbsd_dir_result) |_| false else |_| true;
    if (needs_to_run_autogen) {
        libcrypto.step.dependOn(&autogen_step.step);
        libssl.step.dependOn(&autogen_step.step);
        libtls.step.dependOn(&autogen_step.step);
    }
}
