//! URI based system for retrieving assets
const std = @import("std");
const http = @import("http.zig");
const Uri = std.Uri;

const GetError = Uri.ParseError || http.SendRequestError || error{UnsupportedScheme};

pub const AssetHandle = struct {
    data: union(enum) {
        http: http.HttpResponse,
    },

    // TODO: intersection between file and http error
    pub const ReadError = http.HttpResponse.ReadError;
    pub const Reader = std.io.Reader(*AssetHandle, ReadError, read);

    pub fn reader(self: *AssetHandle) Reader {
        return .{ .context = self };
    }

    pub fn read(self: *AssetHandle, dest: []u8) ReadError!usize {
        switch (self.data) {
            .http => |*resp| {
                return try resp.read(dest);
            },
        }
    }

    pub fn deinit(self: *AssetHandle) void {
        switch (self.data) {
            .http => |*resp| {
                resp.deinit();
            },
        }
    }
};

pub fn get(url: []const u8) GetError!AssetHandle {
    const uri = try Uri.parse(url);

    if (std.mem.eql(u8, uri.scheme, "assets")) {
        @panic("TODO: assets handler");
    } else if (std.mem.eql(u8, uri.scheme, "file")) {
        @panic("TODO: file handler");
    } else if (std.mem.eql(u8, uri.scheme, "http") or std.mem.eql(u8, uri.scheme, "https")) {
        const request = http.HttpRequest.get(url);
        var response = try request.send();

        while (!response.isReady()) {
            // TODO: suspend;
        }
        try response.checkError();

        return AssetHandle{ .data = .{ .http = response } };
    } else {
        return error.UnsupportedScheme;
    }
}
