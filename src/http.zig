//! Module to handle HTTP(S) requests
//!
//! The module was created because it is a very common operation that's not done the same on every devices
//! (For example, on the Web, you can't make TCP sockets, so std.http won't work)
const std = @import("std");
const internal = @import("internal.zig");
const backend = @import("backend.zig");

// TODO: specify more
pub const SendRequestError = anyerror;

pub const HttpRequest = if (backend.Http != void) struct {
    const Self = @This();
    url: []const u8,

    pub fn get(url: []const u8) Self {
        return Self{ .url = url };
    }

    pub fn send(self: Self) !HttpResponse {
        return HttpResponse{ .peer = backend.Http.send(self.url) };
    }
} else struct {
    const Self = @This();
    url: []const u8,

    pub fn get(url: []const u8) Self {
        return Self{ .url = url };
    }

    pub fn send(self: Self) !HttpResponse {
        _ = self;
        // TODO: rewrite for Zig 0.15.2 std.http.Client API
        @panic("std.http.Client support not yet ported to Zig 0.15.2");
    }
};

pub const HttpResponse = if (backend.Http != void) struct {
    const Self = @This();
    peer: backend.HttpResponse,

    pub const ReadError = error{};

    pub fn isReady(self: *Self) bool {
        return self.peer.isReady();
    }

    pub fn checkError(self: *Self) !void {
        _ = self;
    }

    pub fn read(self: *Self, dest: []u8) ReadError!usize {
        return self.peer.read(dest);
    }

    pub fn readAllAlloc(self: *Self, alloc: std.mem.Allocator, max_size: usize) ![]u8 {
        _ = max_size;
        var result = std.ArrayList(u8).empty;
        var buf: [4096]u8 = undefined;
        while (true) {
            const n = try self.read(&buf);
            if (n == 0) break;
            try result.appendSlice(alloc, buf[0..n]);
        }
        return result.toOwnedSlice(alloc);
    }

    pub fn deinit(self: *Self) void {
        _ = self;
    }
} else struct {
    const Self = @This();

    pub const ReadError = error{HttpNotAvailable};

    pub fn isReady(_: *Self) bool {
        return false;
    }

    pub fn checkError(_: *Self) !void {}

    pub fn read(_: *Self, _: []u8) ReadError!usize {
        return error.HttpNotAvailable;
    }

    pub fn readAllAlloc(_: *Self, _: std.mem.Allocator, _: usize) ![]u8 {
        return error.HttpNotAvailable;
    }

    pub fn deinit(_: *Self) void {}
};
