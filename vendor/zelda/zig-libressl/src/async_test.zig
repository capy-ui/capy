const std = @import("std");
const libressl = @import("main.zig");

test "async server & client" {
    const ClientCount = 16;

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

    const Server = struct {
        fn serverFn(server: *libressl.SslServer, message_to_send: []const u8) !void {
            defer server.deinit();

            var current_client: usize = 0;
            var client_frames: [ClientCount]@Frame(@This().handleClient) = undefined;

            while (current_client < ClientCount) : (current_client += 1) {
                client_frames[current_client] = async @This().handleClient(try server.accept(), message_to_send);
            }

            for (client_frames) |*frame| {
                try await frame;
            }
        }

        fn handleClient(
            stream: libressl.SslStream,
            message_to_send: []const u8,
        ) !void {
            var writer = stream.writer();
            try writer.writeAll(message_to_send);
        }
    };

    var server_frame = async Server.serverFn(&ssl_stream_server, message);

    const clientFn = struct {
        fn clientFn(
            server_address: std.net.Address,
            tls_configuration: libressl.TlsConfiguration,
        ) !void {
            var client = try std.net.tcpConnectToAddress(server_address);
            var ssl_client = try libressl.SslStream.wrapClientStream(tls_configuration, client, "localhost");
            defer ssl_client.deinit();

            var client_buf: [message.len]u8 = undefined;
            var client_reader = ssl_client.reader();
            const bytes_read = try client_reader.read(&client_buf);
            const response = client_buf[0..bytes_read];
            try std.testing.expectEqualStrings(message, response);
        }
    }.clientFn;

    var client_frames: [ClientCount]@Frame(clientFn) = undefined;

    var client_count: usize = 0;
    while (client_count < ClientCount) : (client_count += 1) {
        client_frames[client_count] = async clientFn(stream_server.listen_address, conf);
    }

    for (client_frames) |*frame| {
        try await frame;
    }

    try await server_frame;
}
