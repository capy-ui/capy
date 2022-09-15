const std = @import("std");

const hzzp = @import("../main.zig");
const util = @import("../util.zig");

const response_parser = @import("../main.zig").parser.response;

pub const ResponseParser = response_parser.ResponseParser;
pub const PayloadEvent = response_parser.PayloadEvent;
pub const StatusEvent = response_parser.StatusEvent;
pub const Event = response_parser.Event;

const ascii = std.ascii;
const mem = std.mem;

const assert = std.debug.assert;

pub fn create(buffer: []u8, reader: anytype, writer: anytype) BaseClient(@TypeOf(reader), @TypeOf(writer)) {
    // Any buffer smaller than 16 cannot read the most simple status line (1xx A HTTP/1.1\r\n)
    assert(buffer.len >= 16);

    return BaseClient(@TypeOf(reader), @TypeOf(writer)).init(buffer, reader, writer);
}

pub fn BaseClient(comptime Reader: type, comptime Writer: type) type {
    const ParserType = ResponseParser(Reader);

    return struct {
        const Self = @This();

        encoding: util.TransferEncoding = .unknown,
        head_finished: bool = false,

        read_buffer: []u8,
        parser: ParserType,
        writer: Writer,

        payload_size: usize = 0,
        payload_index: usize = 0,

        // Whether a reader is currently using the read_buffer. if true, parser.next should NOT be called since the
        // reader expects all of the data.
        self_contained: bool = false,

        pub fn init(buffer: []u8, input: Reader, output: Writer) Self {
            return .{
                .read_buffer = buffer,
                .parser = ParserType.init(buffer, input),
                .writer = output,
            };
        }

        pub fn reset(self: *Self) void {
            self.encoding = .unknown;
            self.head_finished = false;

            self.parser.reset();

            self.payload_size = 0;
            self.payload_index = 0;

            self.self_contained = false;
        }

        pub fn writeStatusLine(self: *Self, method: []const u8, path: []const u8) Writer.Error!void {
            assert(!self.head_finished);

            try self.writer.writeAll(method);
            try self.writer.writeAll(" ");
            try self.writer.writeAll(path);
            try self.writer.writeAll(" HTTP/1.1\r\n");
        }

        // This makes interacting with URI parsers like Vexu/zuri much nicer, because you don't need to reconstruct the path.
        pub fn writeStatusLineParts(self: *Self, method: []const u8, path: []const u8, query: ?[]const u8, fragment: ?[]const u8) Writer.Error!void {
            assert(!self.head_finished);

            try self.writer.writeAll(method);
            try self.writer.writeAll(" ");
            try self.writer.writeAll(path);

            if (query) |qs| {
                try self.writer.writeAll("?");
                try self.writer.writeAll(qs);
            }

            if (fragment) |frag| {
                try self.writer.writeAll("#");
                try self.writer.writeAll(frag);
            }

            try self.writer.writeAll(" HTTP/1.1\r\n");
        }

        pub fn writeHeaderValue(self: *Self, name: []const u8, value: []const u8) Writer.Error!void {
            assert(!self.head_finished);

            // This should also guarantee that the value is actually chunked
            if (ascii.eqlIgnoreCase(name, "transfer-encoding")) {
                self.encoding = .chunked;
            } else if (ascii.eqlIgnoreCase(name, "content-length")) {
                self.encoding = .content_length;
            }

            try self.writer.writeAll(name);
            try self.writer.writeAll(": ");
            try self.writer.writeAll(value);
            try self.writer.writeAll("\r\n");
        }

        pub fn writeHeaderFormat(self: *Self, name: []const u8, comptime format: []const u8, args: anytype) Writer.Error!void {
            assert(!self.head_finished);

            // This should also guarantee that the value is actually chunked
            if (ascii.eqlIgnoreCase(name, "transfer-encoding")) {
                self.encoding = .chunked;
            } else if (ascii.eqlIgnoreCase(name, "content-length")) {
                self.encoding = .content_length;
            }

            try self.writer.writeAll(name);
            try self.writer.writeAll(": ");
            try self.writer.print(format, args);
            try self.writer.writeAll("\r\n");
        }

        pub fn writeHeader(self: *Self, header: hzzp.Header) Writer.Error!void {
            assert(!self.head_finished);

            try self.writeHeaderValue(header.name, header.value);
        }

        pub fn writeHeaders(self: *Self, headers: hzzp.HeadersSlice) Writer.Error!void {
            assert(!self.head_finished);

            for (headers) |header| {
                try self.writeHeader(header);
            }
        }

        pub fn finishHeaders(self: *Self) Writer.Error!void {
            if (!self.head_finished) try self.writer.writeAll("\r\n");

            self.head_finished = true;
        }

        pub fn writePayload(self: *Self, data: ?[]const u8) Writer.Error!void {
            switch (self.encoding) {
                .unknown, .content_length => {
                    if (data) |payload| {
                        try self.writer.writeAll(payload);
                    }
                },
                .chunked => {
                    if (data) |payload| {
                        try std.fmt.formatInt(payload.len, 16, .lower, .{}, self.writer);
                        try self.writer.writeAll("\r\n");
                        try self.writer.writeAll(payload);
                        try self.writer.writeAll("\r\n");
                    } else {
                        try self.writer.writeAll("0\r\n");
                    }
                },
            }
        }

        pub const NextError = ParserType.NextError;
        pub fn next(self: *Self) NextError!?Event {
            assert(!self.self_contained);

            return self.parser.next();
        }

        pub fn readNextHeader(self: *Self) NextError!?hzzp.Header {
            if (self.parser.state != .header) return null;
            assert(!self.self_contained);

            if (try self.parser.next()) |event| {
                switch (event) {
                    .head_done, .end => return null,
                    .header => |header| return header,
                    .status,
                    .payload,
                    .skip,
                    => unreachable,
                }
            }
        }

        pub const Chunk = PayloadEvent;
        pub fn readNextChunk(self: *Self) NextError!?Chunk {
            if (self.parser.state != .body) return null;
            assert(!self.self_contained);

            if (try self.parser.next()) |event| {
                switch (event) {
                    .payload => |chunk| return chunk,
                    .skip, .end => return null,
                    .status,
                    .header,
                    .head_done,
                    => unreachable,
                }
            }
        }

        pub fn readNextChunkBuffer(self: *Self, buffer: []u8) NextError!usize {
            if (self.parser.state != .body) return 0;
            self.self_contained = true;

            if (self.payload_index >= self.payload_size) {
                if (try self.parser.next()) |event| {
                    switch (event) {
                        .payload => |chunk| {
                            self.payload_index = 0;
                            self.payload_size = chunk.data.len;
                        },

                        .skip, .end => {
                            self.self_contained = false;
                            self.payload_index = 0;
                            self.payload_size = 0;

                            return 0;
                        },
                        .status,
                        .header,
                        .head_done,
                        => unreachable,
                    }
                } else {
                    self.self_contained = false;
                    self.payload_index = 0;
                    self.payload_size = 0;

                    return 0;
                }
            }

            const start = self.payload_index;
            const size = std.math.min(buffer.len, self.payload_size - start);
            const end = start + size;

            mem.copy(u8, buffer[0..size], self.read_buffer[start..end]);
            self.payload_index = end;

            return size;
        }

        pub const PayloadReader = std.io.Reader(*Self, NextError, readNextChunkBuffer);

        pub fn reader(self: *Self) PayloadReader {
            assert(self.parser.state == .body);

            return .{ .context = self };
        }
    };
}

const testing = std.testing;
const io = std.io;

fn testNextField(parser: anytype, expected: ?Event) !void {
    const actual = try parser.next();

    try testing.expect(@import("../util.zig").reworkedMetaEql(actual, expected));
}

test "decodes a simple response" {
    var read_buffer: [32]u8 = undefined;
    var output = std.ArrayList(u8).init(testing.allocator);
    defer output.deinit();

    var response = "HTTP/1.1 404 Not Found\r\nHost: localhost\r\nContent-Length: 4\r\n\r\ngood";
    var expected = "GET / HTTP/1.1\r\nHeader1: value1\r\nHeader2: value2\r\nHeader3: value3\r\nHeader4: value4\r\n\r\npayload";

    var reader = io.fixedBufferStream(response).reader();
    var writer = output.writer();
    var client = create(&read_buffer, reader, writer);

    const headers = [_]hzzp.Header{
        .{ .name = "Header3", .value = "value3" },
        .{ .name = "Header4", .value = "value4" },
    };

    try client.writeStatusLine("GET", "/");
    try client.writeHeaderValue("Header1", "value1");
    try client.writeHeader(.{ .name = "Header2", .value = "value2" });
    try client.writeHeaders(std.mem.span(&headers));
    try client.finishHeaders();
    try client.writePayload("payload");

    try testing.expectEqualStrings(output.items, expected);

    try testNextField(&client, .{
        .status = .{
            .version = .{
                .major = 1,
                .minor = 1,
            },
            .code = 404,
            .reason = "Not Found",
        },
    });

    try testNextField(&client, .{
        .header = .{
            .name = "Host",
            .value = "localhost",
        },
    });

    try testNextField(&client, .{
        .header = .{
            .name = "Content-Length",
            .value = "4",
        },
    });

    try testNextField(&client, Event.head_done);

    var payload_reader = client.reader();

    var slice = try payload_reader.readAllAlloc(testing.allocator, 16);
    defer testing.allocator.free(slice);

    try testing.expectEqualStrings(slice, "good");
}

comptime {
    std.testing.refAllDecls(@This());
}
