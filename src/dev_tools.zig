//! Capy Development Tools Server
const std = @import("std");

const DEV_TOOLS_PORT = 42671;

var server: std.net.StreamServer = undefined;
var serverThread: std.Thread = undefined;

var run_server = true;

pub fn init() !void {
    const addr = try std.net.Address.parseIp("0.0.0.0", DEV_TOOLS_PORT);
    server = std.net.StreamServer.init(.{ .reuse_address = true });
    try server.listen(addr);

    serverThread = try std.Thread.spawn(.{}, serverRunner, .{});
}

fn connectionRunner(connection: std.net.StreamServer.Connection) !void {
	std.log.info("accepted connection from {}", .{connection.address});
	const stream = connection.stream;
	_ = stream;
}

fn serverRunner() !void {
    while (run_server) {
        const connection = try server.accept();

    	var connectionThread = try std.Thread.spawn(.{}, connectionRunner, .{ connection });
		connectionThread.join(); // TODO: multiple connections
    }
}

pub fn deinit() void {
    run_server = false;
    serverThread.join();
    server.deinit();
}
