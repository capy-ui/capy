//! Module to handle HTTP(S) requests
//! This is useful as it is a very common operation that's not done the same on every devices
//! (For example, on the Web, you can't make TCP sockets, so no 3rd party lib)
const std = @import("std");
const internal = @import("internal.zig");
const backend = @import("backend.zig");

pub usingnamespace if (@hasDecl(backend, "Http")) struct {
    pub const HttpRequest = struct {
        url: []const u8,

        pub fn get(url: []const u8) HttpRequest {
            return HttpRequest{ .url = url };
        }

        pub fn send(self: HttpRequest) !HttpResponse {
            return HttpResponse{ .peer = backend.Http.send(self.url) };
        }
    };

    pub const HttpResponse = struct {
        peer: backend.HttpResponse,

        pub const ReadError = error{};
        pub const Reader = std.io.Reader(*HttpResponse, ReadError, read);

        // This weird and clunky polling async API is used because Zig evented I/O mode
        // is completely broken at the moment.
        pub fn isReady(self: *HttpResponse) bool {
            return self.peer.isReady();
        }

        pub fn checkError(self: *HttpResponse) !void {
            // TODO: return possible errors
            _ = self;
        }

        pub fn reader(self: *HttpResponse) Reader {
            return .{ .context = self };
        }

        pub fn read(self: *HttpResponse, dest: []u8) ReadError!usize {
            return self.peer.read(dest);
        }

        pub fn deinit(self: *HttpResponse) void {
            _ = self; // TODO?
        }
    };
} else struct {
    const zfetch = @import("zfetch");

    // TODO: implement using ziget
    pub const HttpRequest = struct {
        url: []const u8,

        pub fn get(url: []const u8) HttpRequest {
            return HttpRequest{ .url = url };
        }

        pub fn send(self: HttpRequest) !HttpResponse {
            var headers = zfetch.Headers.init(internal.scratch_allocator);
            defer headers.deinit();

            var req = try zfetch.Request.init(internal.lasting_allocator, self.url, null);
            try req.do(.GET, headers, null);
            return HttpResponse{ .req = req };
        }
    };

    pub const HttpResponse = struct {
        req: *zfetch.Request,

        pub const ReadError = zfetch.Request.Reader.Error;
        pub const Reader = std.io.Reader(*HttpResponse, ReadError, read);

        pub fn isReady(self: *HttpResponse) bool {
            _ = self;
            return true;
        }

        pub fn checkError(self: *HttpResponse) !void {
            _ = self;
        }

        pub fn reader(self: *HttpResponse) Reader {
            return .{ .context = self };
        }

        pub fn read(self: *HttpResponse, dest: []u8) ReadError!usize {
            return self.req.reader().read(dest);
        }

        pub fn deinit(self: *HttpResponse) void {
            self.req.deinit();
        }
    };
};

/// Applies URI encoding and replaces all reserved characters with their respective %XX code.
pub fn urlEncode(allocator: std.mem.Allocator, input: []const u8) error{OutOfMemory}![]const u8 {
    // Code from https://github.com/MasterQ32/zig-uri
    var outsize: usize = 0;
    for (input) |c| {
        outsize += if (isUnreserved(c)) @as(usize, 1) else 3;
    }
    var output = try allocator.alloc(u8, outsize);
    var outptr: usize = 0;

    for (input) |c| {
        if (isUnreserved(c)) {
            output[outptr] = c;
            outptr += 1;
        } else {
            var buf: [2]u8 = undefined;
            _ = std.fmt.bufPrint(&buf, "{X:0>2}", .{c}) catch unreachable;

            output[outptr + 0] = '%';
            output[outptr + 1] = buf[0];
            output[outptr + 2] = buf[1];
            outptr += 3;
        }
    }
    return output;
}

/// unreserved  = ALPHA / DIGIT / "-" / "." / "_" / "~"
fn isUnreserved(c: u8) bool {
    return switch (c) {
        'A'...'Z', 'a'...'z', '0'...'9', '-', '.', '_', '~' => true,
        else => false,
    };
}
