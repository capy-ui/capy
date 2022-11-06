const std = @import("std");
const builtin = @import("builtin");

const root = @import("main.zig");
const req = @import("request.zig");
const Request = req.Request;
const Response = req.Response;

const libressl = root.libressl;
const zuri = root.zuri;
const hzzp = root.hzzp;

fn initWindows() void {
    if (@import("builtin").os.tag == .windows) {
        _ = std.os.windows.WSAStartup(2, 2) catch {
            @panic("Failed to initialize on windows");
        };
    }
}

var windowsInit = std.once(initWindows);

const CurlConnectionPoolMaxAgeSecs = 118;
const CurlConnectionPoolMaxClients = 5;

// things to check when matching connections
// host & port match
// protocols match
// TODO(haze/for the future): stuff that i saw curl doing (ConnectionExists in lib/url.c)
// ssl upgraded connections?
// authentication?

// Doubly linked list, protected by a parent rwlock to ensure thread safety
const StoredConnection = struct {
    const Self = @This();
    const Criteria = struct {
        allocator: std.mem.Allocator,
        host: union(enum) {
            provided: []const u8,
            allocated: []u8,
        },
        port: u16,
        is_tls: bool,

        fn getHost(self: Criteria) []const u8 {
            return switch (self.host) {
                .allocated => |data| data,
                .provided => |data| data,
            };
        }

        pub fn eql(self: Criteria, other: Criteria) bool {
            const are_both_tls = self.is_tls == other.is_tls;
            const do_ports_match = self.port == other.port;
            const do_hosts_match =
                std.mem.eql(u8, self.getHost(), other.getHost());
            return are_both_tls and do_ports_match and do_hosts_match;
        }

        pub fn deinit(self: *Criteria) void {
            switch (self.host) {
                .provided => {},
                .allocated => |buf| self.allocator.free(buf),
            }
            self.* = undefined;
        }
    };

    allocator: std.mem.Allocator,
    clientState: union(enum) {
        Ssl: libressl.SslStream,
        Normal: std.net.Stream,
    },

    criteria: Criteria,

    pub fn deinit(self: *Self) void {
        self.criteria.deinit();
        self.allocator.destroy(self);
    }
};

const ConnectionCache = struct {
    const Self = @This();

    const Queue = std.TailQueue(*StoredConnection);
    const Node = Queue.Node;

    items: Queue = Queue{},

    fn findSuitableConnection(self: *Self, criteria: StoredConnection.Criteria) ?*Node {
        var ptr: ?*Node = self.items.last;
        while (ptr) |node| {
            root.logger.debug("Checking Connection {*} {}", .{ node, node.data });
            if (node.data.criteria.eql(criteria)) return node;
            ptr = node.prev;
        }
        return null;
    }

    fn removeFromCache(self: *Self, stored_connection_node: *Node) void {
        self.items.remove(stored_connection_node);
    }

    pub fn deinit(self: *Self) void {
        while (self.items.pop()) |node| {
            var allocator = node.data.allocator;
            node.data.deinit();
            allocator.destroy(node);
        }
    }

    fn addNewConnection(self: *Self, stored_connection_node: *Node) void {
        self.items.append(stored_connection_node);
    }
};

pub var global_connection_cache = ConnectionCache{};

pub const Client = struct {
    const Self = @This();

    const HzzpSslResponseParser = hzzp.parser.response.ResponseParser(libressl.SslStream.Reader);
    const HzzpResponseParser = hzzp.parser.response.ResponseParser(std.net.Stream.Reader);

    pub const HzzpSslClient = hzzp.base.client.BaseClient(libressl.SslStream.Reader, libressl.SslStream.Writer);
    pub const HzzpClient = hzzp.base.client.BaseClient(std.net.Stream.Reader, std.net.Stream.Writer);

    pub const State = union(enum) {
        Created,
        ConnectedSsl: struct {
            tunnel: libressl.SslStream,
            client: HzzpSslClient,
        },
        Connected: struct {
            tcp_connection: std.net.Stream,
            client: HzzpClient,
        },
        Shutdown,

        const NextError = HzzpSslResponseParser.NextError || HzzpResponseParser.NextError;

        const PayloadReader = union(enum) {
            SslReader: HzzpSslClient.PayloadReader,
            Reader: HzzpClient.PayloadReader,
        };

        pub fn payloadReader(self: *State) PayloadReader {
            return switch (self.*) {
                .ConnectedSsl => |*state| .{ .SslReader = state.client.reader() },
                .Connected => |*state| .{ .Reader = state.client.reader() },
                else => unreachable,
            };
        }

        pub fn next(self: *State) NextError!?hzzp.parser.response.Event {
            return switch (self.*) {
                .ConnectedSsl => |*state| state.client.next(),
                .Connected => |*state| state.client.next(),
                else => unreachable,
            };
        }

        pub fn writePayload(self: *State, maybe_data: ?[]const u8) !void {
            if (maybe_data) |data|
                root.logger.debug("Attempting to write {} byte payload", .{data.len})
            else
                root.logger.debug("Attempting to write null payload", .{});
            return switch (self.*) {
                .ConnectedSsl => |*state| state.client.writePayload(maybe_data),
                .Connected => |*state| state.client.writePayload(maybe_data),
                else => unreachable,
            };
        }

        pub fn finishHeaders(self: *State) !void {
            root.logger.debug("Attempting to finish headers", .{});
            return switch (self.*) {
                .ConnectedSsl => |*state| state.client.finishHeaders(),
                .Connected => |*state| state.client.finishHeaders(),
                else => unreachable,
            };
        }

        pub fn writeHeaderValue(self: *State, name: []const u8, value: []const u8) !void {
            root.logger.debug("Attempting to set header: \"{s}\" = \"{s}\"", .{ name, value });
            return switch (self.*) {
                .ConnectedSsl => |*state| state.client.writeHeaderValue(name, value),
                .Connected => |*state| state.client.writeHeaderValue(name, value),
                else => unreachable,
            };
        }

        pub fn writeStatusLine(self: *State, method: []const u8, path: []const u8) !void {
            root.logger.debug("Attempting to write status line (method={s}, path={s})", .{ method, path });
            return switch (self.*) {
                .ConnectedSsl => |*state| state.client.writeStatusLine(method, path),
                .Connected => |*state| state.client.writeStatusLine(method, path),
                else => unreachable,
            };
        }
    };

    allocator: std.mem.Allocator,
    state: State,
    client_read_buffer: []u8,
    user_agent: ?[]u8,

    pub fn deinit(self: *Self) void {
        if (self.user_agent) |user_agent|
            self.allocator.free(user_agent);
        self.allocator.free(self.client_read_buffer);
        self.allocator.destroy(self);
    }

    /// if a user agent is provided, it will be copied into the client and free'd once deinit is called
    pub fn init(
        allocator: std.mem.Allocator,
        options: struct {
            user_agent: ?[]const u8 = null,
        },
    ) !*Self {
        var client: *Self = try allocator.create(Self);
        errdefer allocator.destroy(client);

        client.allocator = allocator;
        client.state = .Created;

        client.client_read_buffer = try allocator.alloc(u8, 1 << 13);
        errdefer allocator.free(client.client_read_buffer);

        if (options.user_agent) |user_agent| {
            client.user_agent = try allocator.alloc(u8, user_agent.len);
            std.mem.copy(u8, client.user_agent.?, user_agent);
        } else {
            client.user_agent = null;
        }

        windowsInit.call();

        return client;
    }

    pub fn perform(self: *Self, request: Request) !Response {
        var uri = try zuri.Uri.parse(request.url, false);

        if (!std.ascii.eqlIgnoreCase(uri.scheme, "http") and !std.ascii.eqlIgnoreCase(uri.scheme, "https"))
            return error.InvalidHttpScheme;

        const port: u16 = if (uri.port == null) if (std.mem.startsWith(u8, uri.scheme, "https")) @as(u16, 443) else @as(u16, 80) else uri.port.?;
        var tunnel_host_buf: [1 << 8]u8 = undefined;
        var tunnel_host: []const u8 = undefined;
        var is_ssl = port == 443;
        var reused_connection: ?*ConnectionCache.Node = null;

        switch (uri.host) {
            .name => |host| {
                if (host.len == 0) return error.MissingHost;
                std.mem.copy(u8, &tunnel_host_buf, host);
                tunnel_host = tunnel_host_buf[0..host.len];
            },
            .ip => |addr| {
                // if we have an ip, print it as the host for the iguanaTLS client
                tunnel_host = try std.fmt.bufPrint(&tunnel_host_buf, "{}", .{addr});
            },
        }

        // we need to set this null byte for tls connections (because before tunnelHost would be a
        // slice pointing to the url, and that would include the path)
        tunnel_host_buf[tunnel_host.len] = '\x00';

        if (request.use_global_connection_pool) {
            root.logger.debug("Searching connection cache...", .{});
            if (global_connection_cache.findSuitableConnection(StoredConnection.Criteria{
                .allocator = self.allocator,
                .host = .{ .provided = tunnel_host },
                .port = port,
                .is_tls = is_ssl,
            })) |stored_connection_node| {
                reused_connection = stored_connection_node;
                self.state = switch (stored_connection_node.data.clientState) {
                    .Ssl => |*ssl_tunnel| .{
                        .ConnectedSsl = .{
                            .tunnel = ssl_tunnel.*,
                            .client = hzzp.base.client.create(self.client_read_buffer, ssl_tunnel.reader(), ssl_tunnel.writer()),
                        },
                    },
                    .Normal => |tcp_connection| .{ .Connected = .{
                        .tcp_connection = tcp_connection,
                        .client = hzzp.base.client.create(self.client_read_buffer, tcp_connection.reader(), tcp_connection.writer()),
                    } },
                };
                global_connection_cache.removeFromCache(stored_connection_node);
                root.logger.debug("Found a connection to reuse! {}", .{stored_connection_node.data.criteria});
            } else {
                root.logger.debug("No reusable connection found", .{});
            }
        }

        var created_new_connection = false;

        root.logger.debug("req={}", .{request});
        if (reused_connection == null) {
            var tcp_connection = switch (uri.host) {
                .name => |host| blk: {
                    root.logger.debug("Opening tcp connection to {s}:{}...", .{ host, port });
                    var address_list = try getAddressList(self.allocator, host, port);
                    defer self.allocator.free(address_list);
                    if (address_list.len == 0) return error.UnknownHostName;
                    break :blk try std.net.tcpConnectToAddress(address_list[0]);
                },
                .ip => |addr| blk: {
                    root.logger.debug("Opening tcp connection to {s}:{}...", .{ tunnel_host, port });
                    break :blk try std.net.tcpConnectToAddress(addr);
                },
            };

            if (is_ssl) {
                var tls_configuration = request.tls_configuration orelse try (libressl.TlsConfigurationParams{}).build();
                root.logger.debug("Opening TLS tunnel... (host='{s}') {}", .{ tunnel_host, tls_configuration.params });
                var tunnel = try libressl.SslStream.wrapClientStream(tls_configuration, tcp_connection, tunnel_host);
                root.logger.debug("Tunnel open, creating client now", .{});
                var client = hzzp.base.client.create(self.client_read_buffer, tunnel.reader(), tunnel.writer());
                created_new_connection = true;
                self.state = .{
                    .ConnectedSsl = .{
                        .tunnel = tunnel,
                        .client = client,
                    },
                };
            } else {
                var client = hzzp.base.client.create(self.client_read_buffer, tcp_connection.reader(), tcp_connection.writer());
                created_new_connection = true;
                self.state = .{
                    .Connected = .{
                        .client = client,
                        .tcp_connection = tcp_connection,
                    },
                };
            }
            root.logger.debug("Client created...", .{});
        }

        var added_connection_to_global_cache = false;

        root.logger.debug("path={s} query={s} fragment={s}", .{ uri.path, uri.query, uri.fragment });

        var path = if (std.mem.trim(u8, uri.path, " ").len == 0) "/" else uri.path;
        if (std.mem.trim(u8, uri.query, " ").len == 0) {
            try self.state.writeStatusLine(@tagName(request.method), path);
        } else {
            var status = try std.fmt.allocPrint(self.allocator, "{s}?{s}", .{ path, uri.query });
            try self.state.writeStatusLine(@tagName(request.method), status);
            self.allocator.free(status);
        }

        try self.state.writeHeaderValue("Host", tunnel_host);
        try self.state.writeHeaderValue("Connection", "Keep-Alive");
        if (self.user_agent) |user_agent|
            try self.state.writeHeaderValue("User-Agent", user_agent)
        else
            try self.state.writeHeaderValue("User-Agent", root.zelda_default_user_agent);

        // write headers now that we are connected
        if (request.headers) |headerMap| {
            var headerMapIter = headerMap.iterator();
            while (headerMapIter.next()) |kv| {
                var value = try kv.value_ptr.value(self.allocator);
                defer self.allocator.free(value);

                try self.state.writeHeaderValue(kv.key_ptr.*, value);
            }
        }

        // write body
        if (request.body) |body| {
            switch (body.kind) {
                .JSON => try self.state.writeHeaderValue("Content-Type", "application/json"),
                .URLEncodedForm => try self.state.writeHeaderValue("Content-Type", "application/x-www-form-urlencoded"),
                else => {},
            }
            var contentLengthBuffer: [64]u8 = undefined;
            const contentLength = try std.fmt.bufPrint(&contentLengthBuffer, "{}", .{body.bytes.len});
            try self.state.writeHeaderValue("Content-Length", contentLength);
            try self.state.finishHeaders();
            try self.state.writePayload(body.bytes);
        } else {
            try self.state.finishHeaders();
            try self.state.writePayload(null);
        }
        root.logger.debug("Finished sending request...", .{});

        var event = try self.state.next();
        if (event == null) {
            return error.MissingStatus;
        } else while (event.? == .skip) : (event = try self.state.next()) {}
        if (event == null or event.? != .status) {
            return error.MissingStatus;
        }
        const rawCode = std.math.cast(u10, event.?.status.code) orelse return error.StatusCodeTooLarge;
        const responseCode = @intToEnum(hzzp.StatusCode, rawCode);

        // read response headers
        var response = Response.init(self.allocator, responseCode);

        event = try self.state.next();

        while (event != null and event.? != .head_done) {
            switch (event.?) {
                .header => |header| {
                    const value = try self.allocator.alloc(u8, header.value.len);
                    std.mem.copy(u8, value, header.value);

                    if (response.headers.getEntry(header.name)) |entry| {
                        try entry.value_ptr.parts.append(value);
                    } else {
                        var list = req.HeaderValue.init(self.allocator);
                        try list.parts.append(value);

                        const name = try self.allocator.alloc(u8, header.name.len);
                        std.mem.copy(u8, name, header.name);

                        try response.headers.put(name, list);
                    }
                },
                else => return error.ExpectedHeaders,
            }
            event = try self.state.next();
        }

        // read response body (if any)
        var bodyReader = self.state.payloadReader();
        switch (bodyReader) {
            .SslReader => |reader| response.body = try reader.readAllAlloc(self.allocator, std.math.maxInt(u64)),
            .Reader => |reader| response.body = try reader.readAllAlloc(self.allocator, std.math.maxInt(u64)),
        }

        // This results in LLVM ir errors
        // response.body = switch (bodyReader) {
        //     .SslReader => |reader| try reader.readAllAlloc(self.allocator, std.math.maxInt(u64)),
        //     .Reader => |reader| try reader.readAllAlloc(self.allocator, std.math.maxInt(u64)),
        // };

        if (created_new_connection and request.use_global_connection_pool) {
            var stored_connection = try self.allocator.create(StoredConnection);
            stored_connection.allocator = self.allocator;
            stored_connection.clientState = switch (self.state) {
                .ConnectedSsl => |sslState| .{ .Ssl = sslState.tunnel },
                .Connected => |normalState| .{ .Normal = normalState.tcp_connection },
                else => unreachable,
            };
            stored_connection.criteria = StoredConnection.Criteria{
                .allocator = self.allocator,
                .host = .{ .allocated = try self.allocator.dupe(u8, tunnel_host) },
                .port = port,
                .is_tls = is_ssl,
            };
            var node = try self.allocator.create(@TypeOf(global_connection_cache).Node);
            node.next = null;
            node.prev = null;
            node.data = stored_connection;
            global_connection_cache.addNewConnection(node);
            added_connection_to_global_cache = true;
        } else if (reused_connection) |stored_connection| {
            // we're done with the one we used, we can put it back
            global_connection_cache.addNewConnection(stored_connection);
        }

        return response;
    }
};

/// Call `AddressList.deinit` on the result.
pub fn getAddressList(allocator: std.mem.Allocator, name: []const u8, port: u16) ![]std.net.Address {
    const os = std.os;
    var addrs: []std.net.Address = undefined;
    if (builtin.target.os.tag == .windows or builtin.link_libc) {
        const name_c = try std.cstr.addNullByte(allocator, name);
        defer allocator.free(name_c);

        const port_c = try std.fmt.allocPrintZ(allocator, "{}", .{port});
        defer allocator.free(port_c);

        const sys = if (builtin.target.os.tag == .windows) os.windows.ws2_32 else os.system;
        const hints = os.addrinfo{
            .flags = sys.AI.NUMERICSERV,
            .family = os.AF.UNSPEC,
            .socktype = os.SOCK.STREAM,
            .protocol = os.IPPROTO.TCP,
            .canonname = null,
            .addr = null,
            .addrlen = 0,
            .next = null,
        };
        var res: *os.addrinfo = undefined;
        const rc = sys.getaddrinfo(name_c.ptr, port_c.ptr, &hints, &res);
        if (builtin.target.os.tag == .windows) switch (@intToEnum(os.windows.ws2_32.WinsockError, @intCast(u16, rc))) {
            @intToEnum(os.windows.ws2_32.WinsockError, 0) => {},
            .WSATRY_AGAIN => return error.TemporaryNameServerFailure,
            .WSANO_RECOVERY => return error.NameServerFailure,
            .WSAEAFNOSUPPORT => return error.AddressFamilyNotSupported,
            .WSA_NOT_ENOUGH_MEMORY => return error.OutOfMemory,
            .WSAHOST_NOT_FOUND => return error.UnknownHostName,
            .WSATYPE_NOT_FOUND => return error.ServiceUnavailable,
            .WSAEINVAL => unreachable,
            .WSAESOCKTNOSUPPORT => unreachable,
            else => |err| return os.windows.unexpectedWSAError(err),
        } else switch (rc) {
            @intToEnum(sys.EAI, 0) => {},
            .ADDRFAMILY => return error.HostLacksNetworkAddresses,
            .AGAIN => return error.TemporaryNameServerFailure,
            .BADFLAGS => unreachable, // Invalid hints
            .FAIL => return error.NameServerFailure,
            .FAMILY => return error.AddressFamilyNotSupported,
            .MEMORY => return error.OutOfMemory,
            .NODATA => return error.HostLacksNetworkAddresses,
            .NONAME => return error.UnknownHostName,
            .SERVICE => return error.ServiceUnavailable,
            .SOCKTYPE => unreachable, // Invalid socket type requested in hints
            .SYSTEM => switch (os.errno(-1)) {
                else => |e| return os.unexpectedErrno(e),
            },
            else => unreachable,
        }
        defer sys.freeaddrinfo(res);

        const addr_count = blk: {
            var count: usize = 0;
            var it: ?*os.addrinfo = res;
            while (it) |info| : (it = info.next) {
                if (info.addr != null) {
                    count += 1;
                }
            }
            break :blk count;
        };
        addrs = try allocator.alloc(std.net.Address, addr_count);

        var it: ?*os.addrinfo = res;
        var i: usize = 0;
        while (it) |info| : (it = info.next) {
            const addr = info.addr orelse continue;
            addrs[i] = std.net.Address.initPosix(@alignCast(4, addr));

            // if (info.canonname) |n| {
            //     if (result.canon_name == null) {
            //         result.canon_name = try arena.dupe(u8, mem.sliceTo(n, 0));
            //     }
            // }
            i += 1;
        }

        return addrs;
    }

    if (builtin.target.os.tag == .linux) {
        const flags = std.c.AI.NUMERICSERV;
        const family = os.AF.UNSPEC;
        var lookup_addrs = std.ArrayList(std.net.LookupAddr).init(allocator);
        defer lookup_addrs.deinit();

        var canon = std.ArrayList(u8).init(allocator);
        defer canon.deinit();

        try std.net.linuxLookupName(&lookup_addrs, &canon, name, family, flags, port);

        addrs = try allocator.alloc(std.net.Address, lookup_addrs.items.len);
        // if (canon.items.len != 0) {
        //     result.canon_name = canon.toOwnedSlice();
        // }

        for (lookup_addrs.items) |lookup_addr, i| {
            addrs[i] = lookup_addr.addr;
            std.debug.assert(addrs[i].getPort() == port);
        }

        return addrs;
    }
    @compileError("std.net.getAddressList unimplemented for this OS");
}
