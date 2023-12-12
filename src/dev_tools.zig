//! Capy Development Tools Server
const std = @import("std");
const internal = @import("internal.zig");

const DEV_TOOLS_PORT = 42671;
const log = std.log.scoped(.dev_tools);

var server: std.net.StreamServer = undefined;
var serverThread: ?std.Thread = null;

var run_server = true;

const ObjectId = u32;

pub const RequestId = enum(u8) {
    get_windows_num,
    get_window,
    get_property,
};

// Superset of RequestId
pub const ResponseId = enum(u8) {
    // responses
    get_windows_num,
    get_window,
    get_property,

    // events
    property_updated,
};

pub const Request = union(RequestId) {
    get_windows_num: struct {},
    get_window: struct {
        index: u32,
    },
    get_property: struct {
        object: ObjectId,
        property_name: []const u8,
    },
};

pub const Response = union(ResponseId) {
    get_windows_num: struct {
        num: u32,
    },
    get_window: struct {
        window: ObjectId,
    },
    get_property: struct {
        value_id: ObjectId,
    },
    property_updated: struct {
        object: ObjectId,
        property_name: []const u8,
    },
};

pub fn init() !void {
    if (@import("builtin").single_threaded) {
        return;
    }
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

fn readStructField(comptime T: type, reader: anytype) !T {
    if (comptime std.meta.trait.isIntegral(T)) {
        return try reader.readIntBig(T);
    } else if (T == []const u8) {
        const length = try std.leb.readULEB128(u32, reader);
        const bytes = try internal.lasting_allocator.alloc(u8, length);
        try reader.readNoEof(bytes);
        return bytes;
    }
}

fn writeStructField(comptime T: type, writer: anytype, value: T) !void {
    if (comptime std.meta.trait.isIntegral(T)) {
        try writer.writeIntBig(T, value);
    } else if (T == []const u8) {
        try std.leb.writeULEB128(writer, value.len);
        _ = try writer.writeAll(value);
    }
}

fn readStruct(comptime T: type, reader: anytype) !T {
    var value: T = undefined;
    inline for (std.meta.fields(T)) |field| {
        @field(value, field.name) = try readStructField(field.type, reader);
    }
    return value;
}

fn writeStruct(comptime T: type, value: T, writer: anytype) !void {
    inline for (std.meta.fields(T)) |field| {
        try writeStructField(field.type, writer, @field(value, field.name));
    }
}

fn writeResponse(writer: anytype, response: Response) !void {
    const tag = std.meta.activeTag(response);
    try writer.writeIntBig(u8, @intFromEnum(tag));
    inline for (std.meta.fields(Response)) |response_field| {
        if (tag == @field(ResponseId, response_field.name)) {
            const ResponseType = response_field.type;
            try writeStruct(ResponseType, @field(response, response_field.name), writer);
        }
    }
}

fn writeRequest(writer: anytype, request: Request) !void {
    const tag = std.meta.activeTag(request);
    try writer.writeIntBig(u8, @intFromEnum(tag));
    inline for (std.meta.fields(Request)) |request_field| {
        if (tag == @field(RequestId, request_field.name)) {
            const RequestType = request_field.type;
            try writeStruct(RequestType, @field(request, request_field.name), writer);
        }
    }
}

fn connectionRunner(connection: std.net.StreamServer.Connection) !void {
    log.debug("accepted connection from {}", .{connection.address});
    const stream = connection.stream;

    const reader = stream.reader();
    const writer = stream.writer();

    while (true) {
        const request_id = try reader.readEnum(RequestId, .Big);
        std.log.info("request id: 0x{}", .{request_id});
        inline for (std.meta.fields(Request)) |request_field| {
            const RequestType = request_field.type;
            if (request_id == @field(RequestId, request_field.name)) {
                const request = try readStruct(RequestType, reader);
                switch (request_id) {
                    RequestId.get_windows_num => {
                        try writeResponse(writer, .{
                            .get_windows_num = .{ .num = 1 },
                        });
                    },
                    else => @panic("TODO"),
                }
                std.log.info("{s}: {}", .{ request_field.name, request });
            }
        }
    }
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
