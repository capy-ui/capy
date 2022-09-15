const std = @import("std");
const tls = @import("tls");

const RecordingRandom = struct {
    base: std.rand.Random,
    recorded: std.ArrayList(u8),

    pub fn random(self: *RecordingRandom) std.rand.Random {
        return std.rand.Random.init(self, fill);
    }

    fn fill(self: *RecordingRandom, buf: []u8) void {
        self.base.bytes(buf);
        self.recorded.writer().writeAll(buf) catch unreachable;
    }
};

fn RecordingReaderState(comptime Base: type) type {
    return struct {
        base: Base,
        recorded: std.ArrayList(u8),

        fn read(self: *@This(), buffer: []u8) !usize {
            var read_bytes = try self.base.read(buffer);
            if (read_bytes != 0) {
                try self.recorded.writer().writeAll(buffer[0..read_bytes]);
            }
            return read_bytes;
        }
    };
}

fn RecordingReader(comptime Base: type) type {
    return std.io.Reader(
        *RecordingReaderState(Base),
        Base.Error || error{OutOfMemory},
        RecordingReaderState(Base).read,
    );
}

fn record_handshake(
    comptime ciphersuites: anytype,
    comptime curves: anytype,
    allocator: std.mem.Allocator,
    out_name: []const u8,
    hostname: []const u8,
    port: u16,
    pem_file_path: []const u8,
) !void {
    // Read PEM file
    const pem_file = try std.fs.cwd().openFile(pem_file_path, .{});
    defer pem_file.close();

    const trust_anchors = try tls.x509.CertificateChain.from_pem(allocator, pem_file.reader());
    defer trust_anchors.deinit();
    std.log.info("Read {} certificates.", .{trust_anchors.data.items.len});

    const sock = try std.net.tcpConnectToHost(allocator, hostname, port);
    defer sock.close();

    var recording_reader_state = RecordingReaderState(@TypeOf(sock).Reader){
        .base = sock.reader(),
        .recorded = std.ArrayList(u8).init(allocator),
    };
    defer recording_reader_state.recorded.deinit();

    var recording_random = RecordingRandom{
        .base = std.crypto.random.*,
        .recorded = std.ArrayList(u8).init(allocator),
    };
    defer recording_random.recorded.deinit();

    const reader = RecordingReader(@TypeOf(sock).Reader){
        .context = &recording_reader_state,
    };
    std.log.info("Recording session `{s}`...", .{out_name});
    var client = try tls.client_connect(.{
        .rand = recording_random.random(),
        .reader = reader,
        .writer = sock.writer(),
        .ciphersuites = ciphersuites,
        .curves = curves,
        .cert_verifier = .default,
        .temp_allocator = allocator,
        .trusted_certificates = trust_anchors.data.items,
    }, hostname);
    defer client.close_notify() catch {};

    const out_file = try std.fs.cwd().createFile(out_name, .{});
    defer out_file.close();

    if (ciphersuites.len > 1) {
        try out_file.writeAll(&[_]u8{ 0x3, 'a', 'l', 'l' });
    } else {
        try out_file.writer().writeIntLittle(u8, ciphersuites[0].name.len);
        try out_file.writeAll(ciphersuites[0].name);
    }
    if (curves.len > 1) {
        try out_file.writeAll(&[_]u8{ 0x3, 'a', 'l', 'l' });
    } else {
        try out_file.writer().writeIntLittle(u8, curves[0].name.len);
        try out_file.writeAll(curves[0].name);
    }
    try out_file.writer().writeIntLittle(usize, hostname.len);
    try out_file.writeAll(hostname);
    try out_file.writer().writeIntLittle(u16, port);
    try out_file.writer().writeIntLittle(usize, pem_file_path.len);
    try out_file.writeAll(pem_file_path);
    try out_file.writer().writeIntLittle(usize, recording_reader_state.recorded.items.len);
    try out_file.writeAll(recording_reader_state.recorded.items);
    try out_file.writer().writeIntLittle(usize, recording_random.recorded.items.len);
    try out_file.writeAll(recording_random.recorded.items);
    std.log.info("Session recorded.\n", .{});
}

fn record_with_ciphersuite(
    comptime ciphersuites: anytype,
    allocator: std.mem.Allocator,
    out_name: []const u8,
    curve_str: []const u8,
    hostname: []const u8,
    port: u16,
    pem_file_path: []const u8,
) !void {
    if (std.mem.eql(u8, curve_str, "all")) {
        return try record_handshake(
            ciphersuites,
            tls.curves.all,
            allocator,
            out_name,
            hostname,
            port,
            pem_file_path,
        );
    }
    inline for (tls.curves.all) |curve| {
        if (std.mem.eql(u8, curve_str, curve.name)) {
            return try record_handshake(
                ciphersuites,
                .{curve},
                allocator,
                out_name,
                hostname,
                port,
                pem_file_path,
            );
        }
    }
    std.log.err("Invalid curve `{s}`", .{curve_str});
    std.debug.print("Available options:\n- all\n", .{});
    inline for (tls.curves.all) |curve| {
        std.debug.print("- {s}\n", .{curve.name});
    }
    return error.InvalidArg;
}

var gpa = std.heap.GeneralPurposeAllocator(.{}){};
pub fn main() !void {
    const allocator = gpa.allocator();

    var args = std.process.args();
    std.debug.assert(args.skip());

    const pem_file_path = (try args.next(allocator)) orelse {
        std.log.err("Need PEM file path as first argument", .{});
        return error.NotEnoughArgs;
    };
    defer allocator.free(pem_file_path);

    const ciphersuite_str = (try args.next(allocator)) orelse {
        std.log.err("Need ciphersuite as second argument", .{});
        return error.NotEnoughArgs;
    };
    defer allocator.free(ciphersuite_str);

    const curve_str = (try args.next(allocator)) orelse {
        std.log.err("Need curve as third argument", .{});
        return error.NotEnoughArgs;
    };
    defer allocator.free(curve_str);

    const hostname_port = (try args.next(allocator)) orelse {
        std.log.err("Need hostname:port as fourth argument", .{});
        return error.NotEnoughArgs;
    };
    defer allocator.free(hostname_port);

    if (args.skip()) {
        std.log.err("Need exactly four arguments", .{});
        return error.TooManyArgs;
    }

    var hostname_parts = std.mem.split(u8, hostname_port, ":");
    const hostname = hostname_parts.next().?;
    const port = std.fmt.parseUnsigned(
        u16,
        hostname_parts.next() orelse {
            std.log.err("Hostname and port should be in `hostname:port` format", .{});
            return error.InvalidArg;
        },
        10,
    ) catch {
        std.log.err("Port is not a base 10 unsigned integer...", .{});
        return error.InvalidArg;
    };
    if (hostname_parts.next() != null) {
        std.log.err("Hostname and port should be in `hostname:port` format", .{});
        return error.InvalidArg;
    }

    const out_name = try std.fmt.allocPrint(allocator, "{s}-{s}-{s}-{}.handshake", .{
        hostname,
        ciphersuite_str,
        curve_str,
        std.time.timestamp(),
    });
    defer allocator.free(out_name);

    if (std.mem.eql(u8, ciphersuite_str, "all")) {
        return try record_with_ciphersuite(
            tls.ciphersuites.all,
            allocator,
            out_name,
            curve_str,
            hostname,
            port,
            pem_file_path,
        );
    }
    inline for (tls.ciphersuites.all) |ciphersuite| {
        if (std.mem.eql(u8, ciphersuite_str, ciphersuite.name)) {
            return try record_with_ciphersuite(
                .{ciphersuite},
                allocator,
                out_name,
                curve_str,
                hostname,
                port,
                pem_file_path,
            );
        }
    }
    std.log.err("Invalid ciphersuite `{s}`", .{ciphersuite_str});
    std.debug.print("Available options:\n- all\n", .{});
    inline for (tls.ciphersuites.all) |ciphersuite| {
        std.debug.print("- {s}\n", .{ciphersuite.name});
    }
    return error.InvalidArg;
}
