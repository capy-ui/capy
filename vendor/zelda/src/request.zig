const std = @import("std");
const root = @import("main.zig");

const hzzp = root.hzzp;
const libressl = root.libressl;

pub const Method = enum { GET, POST, PUT, DELETE, HEAD, OPTIONS, CONNECT, PATCH, TRACE };

// TODO(haze): MultipartForm,
pub const BodyKind = enum { JSON, Raw, URLEncodedForm };

const StringList = std.ArrayList([]const u8);
pub const HeaderValue = struct {
    parts: StringList,

    /// Owner is responsible for the returned memory
    ///
    /// Transforms
    ///     Cache-Control: no-cache
    ///     Cache-Control: no-store
    /// Into
    ///     Cache-Control: no-cache, no-store
    pub fn value(self: HeaderValue, allocator: std.mem.Allocator) std.mem.Allocator.Error![]u8 {
        // first, find out how much we need to allocate
        // 2 = ", "
        var bytesNeeded = 2 * (self.parts.items.len - 1);
        for (self.parts.items) |part|
            bytesNeeded += part.len;
        var buffer = try allocator.alloc(u8, bytesNeeded);
        var fixed_buffer_stream = std.io.fixedBufferStream(buffer);
        var writer = fixed_buffer_stream.writer();
        for (self.parts.items) |part, idx| {
            writer.writeAll(part) catch unreachable;
            if (idx != self.parts.items.len - 1)
                writer.writeAll(", ") catch unreachable;
        }
        return buffer;
    }

    pub fn init(allocator: std.mem.Allocator) HeaderValue {
        return .{
            .parts = StringList.init(allocator),
        };
    }

    pub fn deinit(self: *HeaderValue) void {
        self.parts.deinit();
        self.* = undefined;
    }
};

pub const HeaderMap = std.StringArrayHashMap(HeaderValue);

pub const Body = struct {
    kind: BodyKind,
    bytes: []const u8,
};

pub const Request = struct {
    const Self = @This();

    pub const Error = error{MissingScheme};

    method: Method,
    url: []const u8,
    headers: ?HeaderMap = null,
    body: ?Body = null,
    use_global_connection_pool: bool,
    tls_configuration: ?libressl.TlsConfiguration = null,
};

pub const Response = struct {
    const Self = @This();
    headers: HeaderMap,
    body: ?[]u8 = null,
    allocator: std.mem.Allocator,
    status_code: hzzp.StatusCode,

    pub fn init(allocator: std.mem.Allocator, status_code: hzzp.StatusCode) Self {
        return .{
            .headers = HeaderMap.init(allocator),
            .allocator = allocator,
            .status_code = status_code,
        };
    }

    pub fn deinit(self: *Self) void {
        var headerIter = self.headers.iterator();
        while (headerIter.next()) |kv| {
            self.allocator.free(kv.key_ptr.*);
            for (kv.value_ptr.parts.items) |item| {
                self.allocator.free(item);
            }
            kv.value_ptr.parts.deinit();
        }
        self.headers.deinit();
        if (self.body) |body|
            self.allocator.free(body);
        self.* = undefined;
    }
};
