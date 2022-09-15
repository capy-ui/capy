const std = @import("std");

const tls = @import("iguanaTLS");

const assert = std.debug.assert;

const Socket = std.net.Stream;

const TlsClient = tls.Client(Socket.Reader, Socket.Writer, tls.ciphersuites.all, true);

/// The protocol which a connection should use. This dictates the default port and whether or not a TLS connection
/// should be established.
pub const Protocol = enum {
    http,
    https,
    unix,

    pub fn defaultPort(self: Protocol) u16 {
        return switch (self) {
            .http => 80,
            .https => 443,
            .unix => unreachable,
        };
    }
};

pub fn init() error{InitializationError}!void {
    if (@import("builtin").os.tag == .windows) {
        _ = std.os.windows.WSAStartup(2, 2) catch return error.InitializationError;
    }
}

pub fn deinit() void {
    if (@import("builtin").os.tag == .windows) {
        std.os.windows.WSACleanup() catch return;
    }
}

/// A wrapper around streams that may be wrapped in tls that provides a connection agnostic interface.
pub const Connection = struct {
    pub const ConnectOptions = struct {
        protocol: Protocol = .http,

        /// Hostname for TCP connections, Path for unix domain sockets.
        hostname: []const u8,

        /// For TCP connections, null indicates default port for the specified protocol. Must be null for unix domain sockets.
        port: ?u16 = null,

        /// Whether the connection should be wrapped in a TLS stream
        want_tls: bool = false,

        /// Must be null if want_tls is false.
        trust_chain: ?tls.x509.CertificateChain = null,
    };

    allocator: std.mem.Allocator,

    /// The options that this connection was initiated with.
    options: ConnectOptions,

    /// The underlying network socket.
    socket: Socket,

    /// The TLS context if the connection is using TLS.
    secure_context: ?TlsClient = null,

    /// Workaround for std.crypto.rand not working in evented mode
    prng: std.rand.Isaac64 = undefined,

    fn rawConnect(allocator: std.mem.Allocator, options: ConnectOptions) !Socket {
        switch (options.protocol) {
            .http, .https => {
                const real_port = options.port orelse options.protocol.defaultPort();

                return try std.net.tcpConnectToHost(allocator, options.hostname, real_port);
            },
            .unix => {
                assert(options.port == null);

                // windows doesn't support unix sockets before build 17063.
                if (!std.net.has_unix_sockets) return error.UnixSocketsUnsupported;

                return try std.net.connectUnixSocket(options.hostname);
            },
        }
    }

    /// Form a connection to the requested hostname and port.
    /// In the case of a unix domain socket, the hostname is used as the socket path.
    pub fn connect(allocator: std.mem.Allocator, options: ConnectOptions) !Connection {
        const host_dupe = try allocator.dupe(u8, options.hostname);
        errdefer allocator.free(host_dupe);

        var conn = Connection{
            .allocator = allocator,
            .options = options,
            .socket = undefined,
        };

        conn.options.hostname = host_dupe;

        conn.socket = try rawConnect(allocator, conn.options);
        errdefer conn.socket.close();

        if (options.want_tls) {
            try conn.setupTlsContext();
        }

        return conn;
    }

    pub fn fromSocket(allocator: std.mem.Allocator, socket: Socket, options: ConnectOptions) !Connection {
        const host_dupe = try allocator.dupe(u8, options.hostname);
        errdefer allocator.free(host_dupe);

        var conn = Connection{
            .allocator = allocator,
            .options = options,
            .socket = socket,
        };

        conn.options.hostname = host_dupe;

        if (options.want_tls) {
            try conn.setupTlsContext();
        }

        return conn;
    }

    pub fn reconnect(self: *Connection) !void {
        if (self.secure_context) |*ctx| {
            ctx.close_notify() catch {};
        }

        self.socket.close();

        self.socket = rawConnect(self.allocator, self.options);
        errdefer self.close();

        if (self.secure_context) |_| {
            try self.setupTlsContext(self.options.trust_chain);
        }
    }

    fn setupTlsContext(self: *Connection) !void {
        // Workaround for std.crypto.rand not working in evented mode and std.rand.DefaultCsprng miscompiling the vectorized permute
        var seed: [8]u8 = undefined;
        try std.os.getrandom(&seed);
        self.prng = std.rand.Isaac64.init(std.mem.bytesAsValue(u64, &seed).*);

        if (self.options.trust_chain) |trust_chain| {
            self.secure_context = try tls.client_connect(.{
                .reader = self.socket.reader(),
                .writer = self.socket.writer(),
                .cert_verifier = .default,
                .trusted_certificates = trust_chain.data.items,
                .temp_allocator = self.allocator,
                .ciphersuites = tls.ciphersuites.all,
                .protocols = &[_][]const u8{"http/1.1"},

                // Workaround for std.crypto.rand not working in evented mode
                .rand = self.prng.random(),
            }, self.options.hostname);
        } else {
            self.secure_context = try tls.client_connect(.{
                .reader = self.socket.reader(),
                .writer = self.socket.writer(),
                .cert_verifier = .none,
                .temp_allocator = self.allocator,
                .ciphersuites = tls.ciphersuites.all,
                .protocols = &[_][]const u8{"http/1.1"},

                // Workaround for std.crypto.rand not working in evented mode
                .rand = self.prng.random(),
            }, self.options.hostname);
        }
    }

    /// Close this connection.
    pub fn close(self: *Connection) void {
        if (self.secure_context) |*ctx| {
            ctx.close_notify() catch {};
        }

        self.socket.close();
        self.allocator.free(self.options.hostname);
    }

    pub const ReadError = TlsClient.Reader.Error;
    pub const Reader = std.io.Reader(*Connection, ReadError, read);
    pub fn read(self: *Connection, buffer: []u8) ReadError!usize {
        if (self.secure_context) |*ctx| {
            return ctx.read(buffer);
        } else {
            return self.socket.read(buffer);
        }
    }

    pub fn reader(self: *Connection) Reader {
        return .{ .context = self };
    }

    pub const WriteError = TlsClient.Writer.Error;
    pub const Writer = std.io.Writer(*Connection, WriteError, write);
    pub fn write(self: *Connection, buffer: []const u8) WriteError!usize {
        if (self.secure_context) |*ctx| {
            return ctx.write(buffer);
        } else {
            return self.socket.write(buffer);
        }
    }

    pub fn writer(self: *Connection) Writer {
        return .{ .context = self };
    }
};

test "can http?" {
    try @This().init();
    var conn = try Connection.connect(std.testing.allocator, .{ .hostname = "en.wikipedia.org" });
    defer conn.close();

    try conn.writer().writeAll("GET / HTTP/1.1\r\nHost: en.wikipedia.org\r\nAccept: */*\r\n\r\n");

    var buf = try conn.reader().readUntilDelimiterAlloc(std.testing.allocator, '\r', std.math.maxInt(usize));
    defer std.testing.allocator.free(buf);

    try std.testing.expectEqualStrings("HTTP/1.1 301 TLS Redirect", buf);
}

test "can https?" {
    try @This().init();
    var conn = try Connection.connect(std.testing.allocator, .{ .hostname = "en.wikipedia.org", .protocol = .https, .want_tls = true });
    defer conn.close();

    try conn.writer().writeAll("GET / HTTP/1.1\r\nHost: en.wikipedia.org\r\nAccept: */*\r\n\r\n");

    var buf = try conn.reader().readUntilDelimiterAlloc(std.testing.allocator, '\r', std.math.maxInt(usize));
    defer std.testing.allocator.free(buf);

    try std.testing.expectEqualStrings("HTTP/1.1 301 Moved Permanently", buf);
}

comptime {
    std.testing.refAllDecls(@This());
}
