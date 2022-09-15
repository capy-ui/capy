const std = @import("std");

const mem = std.mem;

const hzzp = @import("hzzp");
const zuri = @import("uri");
const tls = @import("iguanaTLS");

const connection = @import("connection.zig");

const Protocol = connection.Protocol;
const Connection = connection.Connection;

/// All RFC 7231 and RFC 5789 HTTP methods.
pub const Method = enum {
    GET,
    HEAD,
    POST,
    PUT,
    DELETE,
    CONNECT,
    OPTIONS,
    TRACE,
    PATCH,

    pub fn name(self: Method) []const u8 {
        return @tagName(self);
    }

    pub const HasPayload = enum { yes, no, maybe };
    pub fn hasPayload(self: Method) HasPayload {
        switch (self) {
            .GET, .HEAD, .CONNECT, .OPTIONS, .TRACE => return .no,
            .POST, .PUT, .PATCH => return .yes,
            .DELETE => return .maybe,
        }
    }
};

const root = @import("root");
const read_buffer_size = if (@hasDecl(root, "zfetch_read_buffer_size"))
    root.zfetch_read_buffer_size
else if (@hasDecl(root, "zfetch_buffer_size"))
    root.zfetch_buffer_size
else if (@hasDecl(root, "zfetch_large_buffer"))
    if (root.zfetch_large_buffer) 32768 else 4096
else
    4096;

const write_buffer_size = if (@hasDecl(root, "zfetch_write_buffer_size"))
    root.zfetch_write_buffer_size
else if (@hasDecl(root, "zfetch_buffer_size"))
    root.zfetch_buffer_size
else if (@hasDecl(root, "zfetch_large_buffer"))
    if (root.zfetch_large_buffer) 32768 else 4096
else
    4096;

const BufferedReader = std.io.BufferedReader(read_buffer_size, Connection.Reader);
const BufferedWriter = std.io.BufferedWriter(write_buffer_size, Connection.Writer);

const HttpClient = hzzp.base.client.BaseClient(BufferedReader.Reader, BufferedWriter.Writer);

pub const Request = struct {
    pub const Status = struct {
        /// The response code
        code: u16,

        /// The reason for this response code, may be non-standard.
        reason: []const u8,
    };

    allocator: mem.Allocator,

    /// The connection that this request is using.
    socket: Connection,

    /// A duplicate of the url provided when initialized.
    url: []const u8,

    /// The components of the url provided when initialized.
    uri: zuri.UriComponents,

    buffer: []u8 = undefined,
    client: HttpClient,

    /// The response status.
    status: Status,

    /// The response headers.
    headers: hzzp.Headers,

    buffered_reader: *BufferedReader,
    buffered_writer: *BufferedWriter,

    // assumes scheme://hostname[:port]/ url
    /// Start a new request to the specified url. This will open a connection to the server.
    /// `url` must remain alive until the request is sent (see commit).
    pub fn init(allocator: mem.Allocator, url: []const u8, trust: ?tls.x509.CertificateChain) !*Request {
        const uri = try zuri.parse(url);

        const protocol: Protocol = proto: {
            if (uri.scheme) |scheme| {
                if (mem.eql(u8, scheme, "http")) {
                    break :proto .http;
                } else if (mem.eql(u8, scheme, "https")) {
                    break :proto .https;
                } else if (mem.eql(u8, scheme, "unix")) {
                    break :proto .unix;
                } else {
                    return error.InvalidScheme;
                }
            } else {
                return error.MissingScheme;
            }
        };

        var req = try allocator.create(Request);
        errdefer allocator.destroy(req);

        var options = Connection.ConnectOptions{
            .protocol = protocol,
            .hostname = undefined,
        };

        switch (protocol) {
            .unix => {
                if (uri.host != null) return error.InvalidUri;

                options.hostname = uri.path;
            },
            .http, .https => {
                if (uri.host == null) return error.MissingHost;

                options.hostname = uri.host.?;
                options.port = uri.port;
            },
        }

        if (protocol == .https or trust != null) {
            options.want_tls = true;
            options.trust_chain = trust;
        }

        req.allocator = allocator;
        req.socket = try Connection.connect(allocator, options);
        errdefer req.socket.close();

        req.buffer = try allocator.alloc(u8, mem.page_size);
        errdefer allocator.free(req.buffer);

        req.url = url;
        req.uri = uri;

        req.buffered_reader = try allocator.create(BufferedReader);
        errdefer allocator.destroy(req.buffered_reader);
        req.buffered_reader.* = .{ .unbuffered_reader = req.socket.reader() };

        req.buffered_writer = try allocator.create(BufferedWriter);
        errdefer allocator.destroy(req.buffered_writer);
        req.buffered_writer.* = .{ .unbuffered_writer = req.socket.writer() };

        req.client = HttpClient.init(req.buffer, req.buffered_reader.reader(), req.buffered_writer.writer());

        req.headers = hzzp.Headers.init(allocator);
        req.status = Status{
            .code = 0,
            .reason = "",
        };

        return req;
    }

    pub fn fromConnection(allocator: std.mem.Allocator, conn: Connection, url: []const u8) !*Request {
        const uri = try zuri.parse(url);

        var req = try allocator.create(Request);
        errdefer allocator.destroy(req);

        req.allocator = allocator;
        req.socket = conn;

        req.buffer = try allocator.alloc(u8, mem.page_size);
        errdefer allocator.free(req.buffer);

        req.url = url;
        req.uri = uri;

        req.buffered_reader = try allocator.create(BufferedReader);
        errdefer allocator.destroy(req.buffered_reader);
        req.buffered_reader.* = .{ .unbuffered_reader = req.socket.reader() };

        req.buffered_writer = try allocator.create(BufferedWriter);
        errdefer allocator.destroy(req.buffered_writer);
        req.buffered_writer.* = .{ .unbuffered_writer = req.socket.writer() };

        req.client = HttpClient.init(req.buffer, req.buffered_reader.reader(), req.buffered_writer.writer());

        req.headers = hzzp.Headers.init(allocator);
        req.status = Status{
            .code = 0,
            .reason = "",
        };

        return req;
    }

    /// This function does NOT reform the underlying connection. The url MUST reside on the same host and port.
    pub fn reset(self: *Request, url: []const u8) !void {
        const uri = try zuri.parse(url);

        self.url = url;
        self.uri = uri;

        self.client.reset();

        self.headers.deinit();
        self.headers = hzzp.Headers.init(self.allocator);

        self.allocator.free(self.status.reason);
        self.status = Status{
            .code = 0,
            .reason = "",
        };
    }

    /// End this request. Closes the connection and frees all data.
    pub fn deinit(self: *Request) void {
        self.socket.close();
        self.headers.deinit();

        self.uri = undefined;

        self.allocator.free(self.buffer);
        self.allocator.free(self.status.reason);

        self.allocator.destroy(self.buffered_reader);
        self.allocator.destroy(self.buffered_writer);

        self.allocator.destroy(self);
    }

    /// See `commit` and `fulfill`
    pub fn do(self: *Request, method: Method, headers: ?hzzp.Headers, payload: ?[]const u8) !void {
        try self.commit(method, headers, payload);
        try self.fulfill();
    }

    /// Performs the initial request. This verifies whether the method you are using requires or disallows a payload.
    /// Default headers such as Host, Authorization (when using basic authentication), Connection, User-Agent, and
    /// Content-Length are provided automatically, therefore headers is nullable. This only writes information to allow
    /// for greater compatibility for change in the future.
    pub fn commit(self: *Request, method: Method, headers: ?hzzp.Headers, payload: ?[]const u8) !void {
        if (method.hasPayload() == .yes and payload == null) return error.MissingPayload;
        if (method.hasPayload() == .no and payload != null) return error.MustOmitPayload;

        try self.client.writeStatusLineParts(method.name(), self.uri.path, self.uri.query, self.uri.fragment);

        if (headers == null or !headers.?.contains("Host")) {
            if (self.uri.host) |host| {
                if (self.uri.port) |port| {
                    var auth = try std.fmt.allocPrint(self.allocator, "{s}:{d}", .{ host, port });
                    defer self.allocator.free(auth);

                    try self.client.writeHeaderValue("Host", auth);
                } else {
                    try self.client.writeHeaderValue("Host", host);
                }
            } else {
                try self.client.writeHeaderValue("Host", "");
            }
        }

        if (self.uri.user != null or self.uri.password != null) {
            if (self.uri.user == null) return error.MissingUsername;
            if (self.uri.password == null) return error.MissingPassword;

            if (headers != null and headers.?.contains("Authorization")) return error.AuthorizationMismatch;

            var unencoded = try std.fmt.allocPrint(self.allocator, "{s}:{s}", .{ self.uri.user.?, self.uri.password.? });
            defer self.allocator.free(unencoded);

            var auth = try self.allocator.alloc(u8, std.base64.standard.Encoder.calcSize(unencoded.len));
            defer self.allocator.free(auth);

            _ = std.base64.standard.Encoder.encode(auth, unencoded);

            try self.client.writeHeaderFormat("Authorization", "Basic {s}", .{auth});
        }

        if (headers == null or !headers.?.contains("Connection")) {
            try self.client.writeHeaderValue("Connection", "close");
        }

        if (headers == null or !headers.?.contains("User-Agent")) {
            try self.client.writeHeaderValue("User-Agent", "zfetch");
        }

        if (payload != null and (headers == null or !headers.?.contains("Content-Length") and !headers.?.contains("Transfer-Encoding"))) {
            try self.client.writeHeaderFormat("Content-Length", "{d}", .{payload.?.len});
        }

        if (headers) |hdrs| {
            try self.client.writeHeaders(hdrs.list.items);
        }

        try self.client.finishHeaders();
        try self.client.writePayload(payload);

        try self.buffered_writer.flush();
    }

    /// Waits for the head of the response to be returned. This is not safe for malicious servers, which may stall
    /// forever.
    pub fn fulfill(self: *Request) !void {
        while (try self.client.next()) |event| {
            switch (event) {
                .status => |stat| {
                    self.status.code = stat.code;
                    self.status.reason = try self.allocator.dupe(u8, stat.reason);
                },
                .header => |header| {
                    try self.headers.append(header);
                },
                .head_done => {
                    return;
                },
                .skip => {},
                .payload, .end => unreachable,
            }
        }
    }

    pub const Reader = HttpClient.PayloadReader;

    /// A reader for the response payload. This should only be called after the request is fulfilled.
    pub fn reader(self: *Request) Reader {
        return self.client.reader();
    }
};

test "makes request" {
    try connection.init();
    defer connection.deinit();

    var req = try Request.init(std.testing.allocator, "https://httpbin.org/get", null);
    defer req.deinit();

    try req.do(.GET, null, null);

    try std.testing.expect(req.status.code == 200);
    try std.testing.expectEqualStrings("OK", req.status.reason);
    try std.testing.expectEqualStrings("application/json", req.headers.get("content-type").?);

    var body = try req.reader().readAllAlloc(std.testing.allocator, 4 * 1024);
    defer std.testing.allocator.free(body);

    var json = std.json.Parser.init(std.testing.allocator, false);
    defer json.deinit();

    var tree = try json.parse(body);
    defer tree.deinit();

    try std.testing.expectEqualStrings("https://httpbin.org/get", tree.root.Object.get("url").?.String);
    try std.testing.expectEqualStrings("zfetch", tree.root.Object.get("headers").?.Object.get("User-Agent").?.String);
}

test "does basic auth" {
    try connection.init();
    defer connection.deinit();

    var req = try Request.init(std.testing.allocator, "https://username:password@httpbin.org/basic-auth/username/password", null);
    defer req.deinit();

    try req.do(.GET, null, null);

    try std.testing.expect(req.status.code == 200);
    try std.testing.expectEqualStrings("OK", req.status.reason);
    try std.testing.expectEqualStrings("application/json", req.headers.get("content-type").?);

    var body = try req.reader().readAllAlloc(std.testing.allocator, 4 * 1024);
    defer std.testing.allocator.free(body);

    var json = std.json.Parser.init(std.testing.allocator, false);
    defer json.deinit();

    var tree = try json.parse(body);
    defer tree.deinit();

    try std.testing.expect(tree.root.Object.get("authenticated").?.Bool == true);
    try std.testing.expectEqualStrings("username", tree.root.Object.get("user").?.String);
}

test "can reset and resend" {
    try connection.init();
    defer connection.deinit();

    var headers = hzzp.Headers.init(std.testing.allocator);
    defer headers.deinit();

    try headers.appendValue("Connection", "keep-alive");

    var req = try Request.init(std.testing.allocator, "https://httpbin.org/user-agent", null);
    defer req.deinit();

    try req.do(.GET, headers, null);

    try std.testing.expect(req.status.code == 200);
    try std.testing.expectEqualStrings("OK", req.status.reason);
    try std.testing.expectEqualStrings("application/json", req.headers.get("content-type").?);

    var body = try req.reader().readAllAlloc(std.testing.allocator, 4 * 1024);
    defer std.testing.allocator.free(body);

    var json = std.json.Parser.init(std.testing.allocator, false);
    defer json.deinit();

    var tree = try json.parse(body);
    defer tree.deinit();

    try std.testing.expectEqualStrings("zfetch", tree.root.Object.get("user-agent").?.String);

    try req.reset("https://httpbin.org/get");

    try req.do(.GET, null, null);

    try std.testing.expect(req.status.code == 200);
    try std.testing.expectEqualStrings("OK", req.status.reason);
    try std.testing.expectEqualStrings("application/json", req.headers.get("content-type").?);

    var body1 = try req.reader().readAllAlloc(std.testing.allocator, 4 * 1024);
    defer std.testing.allocator.free(body1);

    var json1 = std.json.Parser.init(std.testing.allocator, false);
    defer json1.deinit();

    var tree1 = try json1.parse(body1);
    defer tree1.deinit();

    try std.testing.expectEqualStrings("https://httpbin.org/get", tree1.root.Object.get("url").?.String);
    try std.testing.expectEqualStrings("zfetch", tree1.root.Object.get("headers").?.Object.get("User-Agent").?.String);
}

comptime {
    std.testing.refAllDecls(@This());
}
