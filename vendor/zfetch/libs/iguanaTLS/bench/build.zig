const Builder = @import("std").build.Builder;

pub fn build(b: *Builder) void {
    const record_build = b.addExecutable("record_handshake", "record_handshake.zig");
    record_build.addPackagePath("tls", "../src/main.zig");
    record_build.setBuildMode(.Debug);
    record_build.install();

    const use_gpa = b.option(
        bool,
        "use-gpa",
        "Use the general purpose allocator instead of an arena allocator",
    ) orelse false;
    const build_options = b.addOptions();
    build_options.addOption(bool, "use_gpa", use_gpa);

    const bench_build = b.addExecutable("bench", "bench.zig");
    bench_build.addPackagePath("tls", "../src/main.zig");
    bench_build.setBuildMode(.ReleaseFast);
    bench_build.addOptions("build_options", build_options);
    bench_build.install();

    const record_run_cmd = record_build.run();
    const bench_run_cmd = bench_build.run();
    record_run_cmd.step.dependOn(b.getInstallStep());
    bench_run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        record_run_cmd.addArgs(args);
        bench_run_cmd.addArgs(args);
    }

    const record_run_step = b.step("record-handshake", "Record a TLS handshake");
    const bench_run_step = b.step("bench", "Run the benchmark");
    record_run_step.dependOn(&record_run_cmd.step);
    bench_run_step.dependOn(&bench_run_cmd.step);
}
