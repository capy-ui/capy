const std = @import("std");
const libressl = @import("main.zig");

test "server & client" {
    const message = "bruh moment";
    var params = libressl.TlsConfigurationParams{
        .ca = .{ .memory = @embedFile("test_files/root.pem") },
        .cert = .{ .memory = @embedFile("test_files/server.crt") },
        .key = .{ .memory = @embedFile("test_files/server.key") },
    };
    const conf = try params.build();

    var stream_server = std.net.StreamServer.init(.{});
    try stream_server.listen(std.net.Address.parseIp("::", 0) catch unreachable);

    var ssl_stream_server = try libressl.SslServer.wrap(conf, stream_server);

    const serverFn = struct {
        fn serverFn(server: *libressl.SslServer, message_to_send: []const u8) !void {
            defer server.deinit();
            var ssl_connection = try server.accept();
            defer ssl_connection.deinit();

            var writer = ssl_connection.writer();
            try writer.writeAll(message_to_send);
        }
    }.serverFn;

    var thread = try std.Thread.spawn(.{}, serverFn, .{ &ssl_stream_server, message });
    defer thread.join();

    var client = try std.net.tcpConnectToAddress(stream_server.listen_address);
    var ssl_client = try libressl.SslStream.wrapClientStream(conf, client, "localhost");

    defer ssl_client.deinit();

    var client_buf: [11]u8 = undefined;
    var client_reader = ssl_client.reader();
    _ = try client_reader.readAll(&client_buf);
    try std.testing.expectEqualStrings(message, &client_buf);
}
