const std = @import("std");
const tls = @import("tls");
const use_gpa = @import("build_options").use_gpa;

pub const log_level = .debug;

const RecordingAllocator = struct {
    const Stats = struct {
        peak_allocated: usize = 0,
        total_allocated: usize = 0,
        total_deallocated: usize = 0,
        total_allocations: usize = 0,
    };

    base_allocator: std.mem.Allocator,
    stats: Stats = .{},

    pub fn allocator(self: *RecordingAllocator) std.mem.Allocator {
        return std.mem.Allocator.init(self, alloc, resize, free);
    }

    fn alloc(
        a: *RecordingAllocator,
        len: usize,
        ptr_align: u29,
        len_align: u29,
        ret_addr: usize,
    ) ![]u8 {
        const self = @ptrCast(*RecordingAllocator, a);
        const mem = try self.base_allocator.rawAlloc(
            len,
            ptr_align,
            len_align,
            ret_addr,
        );

        self.stats.total_allocations += 1;
        self.stats.total_allocated += mem.len;
        self.stats.peak_allocated = std.math.max(
            self.stats.peak_allocated,
            self.stats.total_allocated - self.stats.total_deallocated,
        );
        return mem;
    }

    fn resize(a: *RecordingAllocator, buf: []u8, buf_align: u29, new_len: usize, len_align: u29, ret_addr: usize) ?usize {
        const self = @ptrCast(*RecordingAllocator, a);
        const actual_len = self.base_allocator.rawResize(
            buf,
            buf_align,
            new_len,
            len_align,
            ret_addr,
        ) orelse return null;

        std.debug.assert(actual_len != 0);
        if (actual_len > buf.len) {
            self.stats.total_allocated += actual_len - buf.len;
            self.stats.peak_allocated = std.math.max(
                self.stats.peak_allocated,
                self.stats.total_allocated - self.stats.total_deallocated,
            );
        } else {
            self.stats.total_deallocated += buf.len - actual_len;
        }
        return actual_len;
    }

    fn free(a: *RecordingAllocator, buf: []u8, buf_align: u29, return_address: usize) void {
         _ = buf_align;
         _ = return_address;
        const self = @ptrCast(*RecordingAllocator, a);
        self.stats.total_deallocated += buf.len;
    }
};

const SinkWriter = blk: {
    const S = struct {};
    break :blk std.io.Writer(S, error{}, struct {
        fn f(_: S, buffer: []const u8) !usize {
            return buffer.len;
        }
    }.f);
};

const ReplayingReaderState = struct {
    data: []const u8,
};
const ReplayingReader = std.io.Reader(*ReplayingReaderState, error{}, struct {
    fn f(self: *ReplayingReaderState, buffer: []u8) !usize {
        if (self.data.len < buffer.len)
            @panic("Not enoguh reader data!");
        std.mem.copy(u8, buffer, self.data[0..buffer.len]);
        self.data = self.data[buffer.len..];
        return buffer.len;
    }
}.f);

const ReplayingRandom = struct {
    data: []const u8,

    pub fn random(self: *ReplayingRandom) std.rand.Random {
        return std.rand.Random.init(self, fillFn);
    }

    fn fillFn(self: *ReplayingRandom, buf: []u8) void {
        if (self.data.len < buf.len)
            @panic("Not enough random data!");
        std.mem.copy(u8, buf, self.data[0..buf.len]);
        self.data = self.data[buf.len..];
    }
};

fn benchmark_run(
    comptime ciphersuites: anytype,
    comptime curves: anytype,
    gpa: std.mem.Allocator,
    allocator: std.mem.Allocator,
    running_time: f32,
    hostname: []const u8,
    trust_anchors: tls.x509.CertificateChain,
    reader_recording: []const u8,
    random_recording: []const u8,
) !void {
    {
        const warmup_time_secs = std.math.max(0.5, running_time / 20);
        std.debug.print("Warming up for {d:.2} seconds...\n", .{warmup_time_secs});
        const warmup_time_ns = @floatToInt(i128, warmup_time_secs * std.time.ns_per_s);

        var warmup_time_passed: i128 = 0;
        var timer = try std.time.Timer.start();
        while (warmup_time_passed < warmup_time_ns) {
            var rand_impl = ReplayingRandom{
                .data = random_recording,
            };
            var reader_state = ReplayingReaderState{
                .data = reader_recording,
            };
            const reader = ReplayingReader{ .context = &reader_state };
            const writer = SinkWriter{ .context = .{} };

            timer.reset();
            _ = try tls.client_connect(.{
                .rand = rand_impl.random(),
                .reader = reader,
                .writer = writer,
                .ciphersuites = ciphersuites,
                .curves = curves,
                .cert_verifier = .default,
                .temp_allocator = allocator,
                .trusted_certificates = trust_anchors.data.items,
            }, hostname);
            warmup_time_passed += timer.read();
        }
    }
    {
        std.debug.print("Benchmarking for {d:.2} seconds...\n", .{running_time});

        const RunRecording = struct {
            time: i128,
            mem_stats: RecordingAllocator.Stats,
        };
        var run_recordings = std.ArrayList(RunRecording).init(gpa);

        defer run_recordings.deinit();
        const bench_time_ns = @floatToInt(i128, running_time * std.time.ns_per_s);

        var total_time_passed: i128 = 0;
        var iterations: usize = 0;
        var timer = try std.time.Timer.start();
        while (total_time_passed < bench_time_ns) : (iterations += 1) {
            var rand_impl = ReplayingRandom{
                .data = random_recording,
            };
            var reader_state = ReplayingReaderState{
                .data = reader_recording,
            };
            const reader = ReplayingReader{ .context = &reader_state };
            const writer = SinkWriter{ .context = .{} };
            var recording_allocator = RecordingAllocator{ .base_allocator = allocator };

            timer.reset();
            _ = try tls.client_connect(.{
                .rand = rand_impl.random(),
                .reader = reader,
                .writer = writer,
                .ciphersuites = ciphersuites,
                .curves = curves,
                .cert_verifier = .default,
                .temp_allocator = recording_allocator.allocator(),
                .trusted_certificates = trust_anchors.data.items,
            }, hostname);
            const runtime = timer.read();
            total_time_passed += runtime;

            (try run_recordings.addOne()).* = .{
                .mem_stats = recording_allocator.stats,
                .time = runtime,
            };
        }

        const total_time_secs = @intToFloat(f64, total_time_passed) / std.time.ns_per_s;
        const mean_time_ns = @divTrunc(total_time_passed, iterations);
        const mean_time_ms = @intToFloat(f64, mean_time_ns) * std.time.ms_per_s / std.time.ns_per_s;

        const std_dev_ns = blk: {
            var acc: i128 = 0;
            for (run_recordings.items) |rec| {
                const dt = rec.time - mean_time_ns;
                acc += dt * dt;
            }
            const acc_unsigned: u128 = @intCast(u128, if (acc < 0) -acc else acc);
            break :blk std.math.sqrt(@divTrunc(acc_unsigned, iterations));
        };
        const std_dev_ms = @intToFloat(f64, std_dev_ns) * std.time.ms_per_s / std.time.ns_per_s;

        std.debug.print(
            \\Finished benchmarking.
            \\Total runtime: {d:.2} sec
            \\Iterations: {} ({d:.2} iterations/sec)
            \\Mean iteration time: {d:.2} ms
            \\Standard deviation: {d:.2} ms
            \\
        , .{
            total_time_secs,
            iterations,
            @intToFloat(f64, iterations) / total_time_secs,
            mean_time_ms,
            std_dev_ms,
        });

        // (percentile/100) * (total number n + 1)
        std.sort.sort(RunRecording, run_recordings.items, {}, struct {
            fn f(_: void, lhs: RunRecording, rhs: RunRecording) bool {
                return lhs.time < rhs.time;
            }
        }.f);
        const percentiles = .{ 99.0, 90.0, 75.0, 50.0 };
        inline for (percentiles) |percentile| {
            if (percentile < iterations) {
                const idx = @floatToInt(usize, @intToFloat(f64, iterations + 1) * percentile / 100.0);
                std.debug.print(
                    "{d:.0}th percentile value: {d:.2} ms\n",
                    .{
                        percentile,
                        @intToFloat(f64, run_recordings.items[idx].time) * std.time.ms_per_s / std.time.ns_per_s,
                    },
                );
            }
        }

        const first_mem_stats = run_recordings.items[0].mem_stats;
        for (run_recordings.items[1..]) |rec| {
            std.debug.assert(std.meta.eql(first_mem_stats, rec.mem_stats));
        }

        std.debug.print(
            \\Peak allocated memory: {:.2},
            \\Total allocated memory: {:.2},
            \\Number of allocations: {d},
            \\
        , .{
            std.fmt.fmtIntSizeBin(first_mem_stats.peak_allocated),
            std.fmt.fmtIntSizeBin(first_mem_stats.total_allocated),
            first_mem_stats.total_allocations,
        });
    }
}

fn benchmark_run_with_ciphersuite(
    comptime ciphersuites: anytype,
    curve_str: []const u8,
    gpa: std.mem.Allocator,
    allocator: std.mem.Allocator,
    running_time: f32,
    hostname: []const u8,
    trust_anchors: tls.x509.CertificateChain,
    reader_recording: []const u8,
    random_recording: []const u8,
) !void {
    if (std.mem.eql(u8, curve_str, "all")) {
        return try benchmark_run(
            ciphersuites,
            tls.curves.all,
            gpa,
            allocator,
            running_time,
            hostname,
            trust_anchors,
            reader_recording,
            random_recording,
        );
    }
    inline for (tls.curves.all) |curve| {
        if (std.mem.eql(u8, curve_str, curve.name)) {
            return try benchmark_run(
                ciphersuites,
                .{curve},
                gpa,
                allocator,
                running_time,
                hostname,
                trust_anchors,
                reader_recording,
                random_recording,
            );
        }
    }
    return error.InvalidCurve;
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();

    var args = std.process.args();
    std.debug.assert(args.skip());

    const running_time = blk: {
        const arg = (try args.next(allocator)) orelse return error.NoArguments;
        break :blk std.fmt.parseFloat(f32, arg) catch {
            std.log.err("Running time is not a floating point number...", .{});
            return error.InvalidArg;
        };
    };

    // Loop over all files, swap gpa with a fixed buffer allocator for the handhsake
    arg_loop: while (try args.next(allocator)) |recorded_file_path| {
        defer allocator.free(recorded_file_path);

        std.debug.print(
            \\============================================================
            \\{s}
            \\============================================================
            \\
        , .{std.fs.path.basename(recorded_file_path)});

        const recorded_file = try std.fs.cwd().openFile(recorded_file_path, .{});
        defer recorded_file.close();

        const ciphersuite_str_len = try recorded_file.reader().readByte();
        const ciphersuite_str = try allocator.alloc(u8, ciphersuite_str_len);
        defer allocator.free(ciphersuite_str);
        try recorded_file.reader().readNoEof(ciphersuite_str);

        const curve_str_len = try recorded_file.reader().readByte();
        const curve_str = try allocator.alloc(u8, curve_str_len);
        defer allocator.free(curve_str);
        try recorded_file.reader().readNoEof(curve_str);

        const hostname_len = try recorded_file.reader().readIntLittle(usize);
        const hostname = try allocator.alloc(u8, hostname_len);
        defer allocator.free(hostname);
        try recorded_file.reader().readNoEof(hostname);

        // This variable was passed around and unused, not sure why
        //const port = try recorded_file.reader().readIntLittle(u16);

        const trust_anchors = blk: {
            const pem_file_path_len = try recorded_file.reader().readIntLittle(usize);
            const pem_file_path = try allocator.alloc(u8, pem_file_path_len);
            defer allocator.free(pem_file_path);
            try recorded_file.reader().readNoEof(pem_file_path);

            const pem_file = try std.fs.cwd().openFile(pem_file_path, .{});
            defer pem_file.close();

            const tas = try tls.x509.CertificateChain.from_pem(allocator, pem_file.reader());
            std.debug.print("Read {} certificates.\n", .{tas.data.items.len});
            break :blk tas;
        };
        defer trust_anchors.deinit();

        const reader_recording_len = try recorded_file.reader().readIntLittle(usize);
        const reader_recording = try allocator.alloc(u8, reader_recording_len);
        defer allocator.free(reader_recording);
        try recorded_file.reader().readNoEof(reader_recording);

        const random_recording_len = try recorded_file.reader().readIntLittle(usize);
        const random_recording = try allocator.alloc(u8, random_recording_len);
        defer allocator.free(random_recording);
        try recorded_file.reader().readNoEof(random_recording);

        var arena_allocator_impl: std.heap.ArenaAllocator = undefined;
        const handshake_allocator = blk: {
            if (use_gpa) break :blk gpa.allocator();
            arena_allocator_impl = std.heap.ArenaAllocator.init(std.heap.page_allocator);
            break :blk arena_allocator_impl.allocator();
        };

        defer if (!use_gpa)
            arena_allocator_impl.deinit();
            //@fieldParentPtr(std.heap.ArenaAllocator, "allocator", handshake_allocator).deinit();

        if (std.mem.eql(u8, ciphersuite_str, "all")) {
            try benchmark_run_with_ciphersuite(
                tls.ciphersuites.all,
                curve_str,
                allocator,
                handshake_allocator,
                running_time,
                hostname,
                trust_anchors,
                reader_recording,
                random_recording,
            );
            continue :arg_loop;
        }
        inline for (tls.ciphersuites.all) |ciphersuite| {
            if (std.mem.eql(u8, ciphersuite_str, ciphersuite.name)) {
                try benchmark_run_with_ciphersuite(
                    .{ciphersuite},
                    curve_str,
                    allocator,
                    handshake_allocator,
                    running_time,
                    hostname,
                    trust_anchors,
                    reader_recording,
                    random_recording,
                );
                continue :arg_loop;
            }
        }
        return error.InvalidCiphersuite;
    }
}
