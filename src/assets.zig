//! URI based system for retrieving assets
const std = @import("std");
const http = @import("http.zig");
const internal = @import("internal.zig");
const log = std.log.scoped(.assets);
const Uri = std.Uri;

const GetError = Uri.ParseError || http.SendRequestError || error{UnsupportedScheme} || std.mem.Allocator.Error;

pub const AssetHandle = struct {
    data: union(enum) {
        http: http.HttpResponse,
        file: std.fs.File,
    },

    // TODO: intersection between file and http error
    pub const ReadError = http.HttpResponse.ReadError || std.fs.File.ReadError;
    pub const Reader = std.io.Reader(*AssetHandle, ReadError, read);

    pub fn reader(self: *AssetHandle) Reader {
        return .{ .context = self };
    }

    pub fn bufferedReader(self: *AssetHandle) std.io.BufferedReader(4096, Reader) {
        return std.io.bufferedReaderSize(4096, self.reader());
    }

    pub fn read(self: *AssetHandle, dest: []u8) ReadError!usize {
        switch (self.data) {
            .http => |*resp| {
                return try resp.read(dest);
            },
            .file => |file| {
                return try file.read(dest);
            },
        }
    }

    pub fn deinit(self: *AssetHandle) void {
        switch (self.data) {
            .http => |*resp| {
                resp.deinit();
            },
            .file => |file| {
                file.close();
            },
        }
    }
};

pub fn get(url: []const u8) GetError!AssetHandle {
    // Normalize the URI for the file:// and asset:// scheme
    var out_url: [4096]u8 = undefined;
    const new_size = std.mem.replacementSize(u8, url, "///", "/");
    _ = std.mem.replace(u8, url, "///", "/", &out_url);

    const uri = try Uri.parse(out_url[0..new_size]);
    log.debug("Loading {s}", .{url});

    if (std.mem.eql(u8, uri.scheme, "asset")) {
        // TODO: on wasm load from the web (in relative path)
        // TODO: on pc make assets into a bundle and use @embedFile ? this would ease loading times on windows which
        //       notoriously BAD I/O performance
        var buffer: [std.fs.MAX_PATH_BYTES]u8 = undefined;
        const cwd_path = try std.fs.realpath(".", &buffer);

        // The URL path as a raw string (without percent-encoding)
        const raw_uri_path = try uri.path.toRawMaybeAlloc(internal.scratch_allocator);
        defer internal.scratch_allocator.free(raw_uri_path);

        const asset_path = try std.fs.path.join(internal.scratch_allocator, &.{ cwd_path, "assets/", raw_uri_path });
        defer internal.scratch_allocator.free(asset_path);
        log.debug("-> {s}", .{asset_path});

        const file = try std.fs.openFileAbsolute(asset_path, .{ .mode = .read_only });
        return AssetHandle{ .data = .{ .file = file } };
    } else if (std.mem.eql(u8, uri.scheme, "file")) {
        const raw_uri_path = try uri.path.toRawMaybeAlloc(internal.scratch_allocator);
        defer internal.scratch_allocator.free(raw_uri_path);

        log.debug("-> {path}", .{uri.path});
        const file = try std.fs.openFileAbsolute(raw_uri_path, .{ .mode = .read_only });
        return AssetHandle{ .data = .{ .file = file } };
    } else if (std.mem.eql(u8, uri.scheme, "http") or std.mem.eql(u8, uri.scheme, "https")) {
        const request = http.HttpRequest.get(url);
        var response = try request.send();

        while (!response.isReady()) {
            // TODO: suspend; when async is back
        }
        try response.checkError();

        return AssetHandle{ .data = .{ .http = response } };
    } else {
        return error.UnsupportedScheme;
    }
}
