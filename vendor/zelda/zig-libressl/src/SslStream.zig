const std = @import("std");
const out = std.log.scoped(.ssl_stream);
const root = @import("main.zig");
const tls = root.tls;

const Self = @This();

tls_configuration: root.TlsConfiguration,
tls_context: *tls.tls,
tcp_stream: std.net.Stream,
address: ?std.net.Address = null,

const WrapError = error{ OutOfMemory, BadTlsConfiguration, TlsConnectSocket, TlsAcceptSocket };

pub fn wrapClientStream(
    tls_configuration: root.TlsConfiguration,
    tcp_stream: std.net.Stream,
    server_name: []const u8,
) WrapError!Self {
    var maybe_tls_context = tls.tls_client();
    if (maybe_tls_context == null) return error.OutOfMemory;

    var tls_context = maybe_tls_context.?;
    if (tls.tls_configure(tls_context, tls_configuration.config) == -1)
        return error.BadTlsConfiguration;

    if (tls.tls_connect_socket(tls_context, tcp_stream.handle, server_name.ptr) == -1)
        return error.TlsConnectSocket;

    return Self{
        .tls_configuration = tls_configuration,
        .tls_context = tls_context,
        .tcp_stream = tcp_stream,
    };
}

pub fn wrapServerStream(tls_configuration: root.TlsConfiguration, tls_context: *tls.tls, connection: std.net.StreamServer.Connection) WrapError!Self {
    return Self{
        .tls_configuration = tls_configuration,
        .tls_context = tls_context,
        .tcp_stream = connection.stream,
        .address = connection.address,
    };
}

pub fn deinit(self: *Self) void {
    root.closeTlsContext(self.tls_context, self.tcp_stream.handle) catch |e| {
        root.out.err("Failed to call tls_close on client: {} ({s})", .{ e, tls.tls_error(self.tls_context) });
    };
    tls.tls_free(self.tls_context);
    self.tcp_stream.close();
    self.* = undefined;
}

pub const ReadError = error{ReadFailure};
pub const Reader = std.io.Reader(Self, ReadError, Self.read);
pub fn read(self: Self, buffer: []u8) ReadError!usize {
    var output = attemptTlsFunction(.read, tls.tls_read, self.tls_context, buffer, self.tcp_stream.handle);
    if (output == -1) {
        if (@import("builtin").mode == .Debug) {
            out.err("libtls read error: {s}", .{
                std.mem.span(tls.tls_error(self.tls_context)),
            });
        }
        return error.ReadFailure;
    }
    return @intCast(usize, output);
}
pub fn reader(self: Self) Reader {
    return Reader{ .context = self };
}

pub const WriteError = error{WriteFailure};
pub const Writer = std.io.Writer(Self, WriteError, Self.write);

const tls_func_kind = enum { read, write };
fn attemptTlsFunction(
    comptime tls_function_kind: tls_func_kind,
    function: switch (tls_function_kind) {
        .read => fn (?*tls.tls, ?*anyopaque, usize) callconv(.C) isize,
        .write => fn (?*tls.tls, ?*const anyopaque, usize) callconv(.C) isize,
    },
    tls_context: *tls.tls,
    buffer: switch (tls_function_kind) {
        .read => []u8,
        .write => []const u8,
    },
    fd: std.os.socket_t,
) isize {
    var output = function(tls_context, buffer.ptr, buffer.len);
    if (std.io.is_async) {
        while (output == tls.TLS_WANT_POLLIN or output == tls.TLS_WANT_POLLOUT) {
            if (output == tls.TLS_WANT_POLLIN) {
                std.event.Loop.instance.?.waitUntilFdReadable(fd);
            } else {
                std.event.Loop.instance.?.waitUntilFdWritable(fd);
            }
            output = function(tls_context, buffer.ptr, buffer.len);
        }
    } else {
        while (output == tls.TLS_WANT_POLLIN or output == tls.TLS_WANT_POLLOUT) {
            output = function(tls_context, buffer.ptr, buffer.len);
        }
    }
    return output;
}

pub fn write(self: Self, buffer: []const u8) WriteError!usize {
    var output = attemptTlsFunction(.write, tls.tls_write, self.tls_context, buffer, self.tcp_stream.handle);
    if (output == -1) {
        if (@import("builtin").mode == .Debug) {
            out.err("libtls write error: {s}", .{
                std.mem.span(tls.tls_error(self.tls_context)),
            });
        }
        return error.WriteFailure;
    }
    return @intCast(usize, output);
}
pub fn writer(self: Self) Writer {
    return Writer{ .context = self };
}
