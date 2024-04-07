//! Module to handle HTTP(S) requests
//!
//! The module was created because it is a very common operation that's not done the same on every devices
//! (For example, on the Web, you can't make TCP sockets, so std.http won't work)
const std = @import("std");
const internal = @import("internal.zig");
const backend = @import("backend.zig");

// TODO: specify more
pub const SendRequestError = anyerror;

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
    pub const HttpRequest = struct {
        url: []const u8,

        pub fn get(url: []const u8) HttpRequest {
            return HttpRequest{ .url = url };
        }

        pub fn send(self: HttpRequest) !HttpResponse {
            const client = try internal.lasting_allocator.create(std.http.Client);
            client.* = .{ .allocator = internal.lasting_allocator };

            const uri = try std.Uri.parse(self.url);
            const server_header_buffer = try internal.lasting_allocator.alloc(u8, 64 * 1024);
            var request = try client.open(.GET, uri, .{
                .headers = .{},
                .keep_alive = false,
                .server_header_buffer = server_header_buffer,
            });
            try request.send(.{});
            try request.finish();
            return HttpResponse{
                .request = request,
                .client = client,
                .server_header_buffer = server_header_buffer,
            };
        }
    };

    pub const HttpResponse = struct {
        client: *std.http.Client,
        request: std.http.Client.Request,
        server_header_buffer: []u8,

        pub const ReadError = std.http.Client.Request.ReadError;
        pub const Reader = std.io.Reader(*HttpResponse, ReadError, read);

        pub fn isReady(self: *HttpResponse) bool {
            // self.request.wait() catch return true;
            if (self.request.connection == null) return true;
            const connection = self.request.connection.?;
            connection.fill() catch return true;
            if (connection.read_end != 0) {
                self.request.wait() catch {};
                return true;
            } else {
                return false;
            }
        }

        pub fn checkError(self: *HttpResponse) !void {
            try self.request.wait();
            // if (self.response.status_code != .success_ok) {
            //     return error.FailedRequest;
            // }
        }

        pub fn reader(self: *HttpResponse) Reader {
            return .{ .context = self };
        }

        pub fn read(self: *HttpResponse, dest: []u8) ReadError!usize {
            const amt = try self.request.read(dest);
            return amt;
        }

        pub fn deinit(self: *HttpResponse) void {
            self.request.deinit();
            self.client.deinit();
            internal.lasting_allocator.destroy(self.client);
            internal.lasting_allocator.free(self.server_header_buffer);
        }
    };
};
