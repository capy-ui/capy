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
            return HttpRequest { .url = url };
        }

        pub fn send(self: HttpRequest) HttpResponse {
            return .{ .peer = backend.Http.send(self.url) };
        }
    };

    pub const HttpResponse = struct {
        peer: backend.HttpResponse,

        pub const ReadError = error {};
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

        pub fn deinit(self: *const HttpResponse) void {
            internal.lasting_allocator.destroy(self);
        }

    };
} else struct {
    // TODO: implement using ziget
};
