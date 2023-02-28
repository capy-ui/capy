//! Capy Development Tools Server
const std = @import("std");

const DEV_TOOLS_PORT = 42671;
const log = std.log.scoped(.dev_tools);

var server: std.net.StreamServer = undefined;
var serverThread: ?std.Thread = null;

var run_server = true;

pub fn init() !void {
    const addr = try std.net.Address.parseIp("127.0.0.1", DEV_TOOLS_PORT);
    server = std.net.StreamServer.init(.{ .reuse_address = true });
    if (server.listen(addr)) {
        serverThread = try std.Thread.spawn(.{}, serverRunner, .{});
        log.debug("Server opened at {}", .{addr});
        log.debug("Run 'zig build dev-tools' to debug this application", .{});
        log.debug("You can add 'pub const enable_dev_tools = false;' to your main file in order to disable dev tools.", .{});
    } else |err| {
        log.warn("Could not open server: {s}", .{@errorName(err)});
    }
}

fn connectionRunner(connection: std.net.StreamServer.Connection) !void {
    log.debug("accepted connection from {}", .{connection.address});
    const stream = connection.stream;
    _ = stream;
}

fn serverRunner() !void {
    while (run_server) {
        const connection = try server.accept();

        var connectionThread = try std.Thread.spawn(.{}, connectionRunner, .{connection});
        connectionThread.join(); // TODO: multiple connections
    }
}

pub fn deinit() void {
    run_server = false;
    if (serverThread) |thread| {
        thread.join();
    }
    server.deinit();
}
