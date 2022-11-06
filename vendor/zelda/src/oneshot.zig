const std = @import("std");
const req = @import("request.zig");
const Client = @import("client.zig").Client;

const BasicPerformFunctionPrototype = fn (*std.mem.Allocator, []const u8) anyerror!req.Response;

pub fn get(allocator: std.mem.Allocator, url: []const u8) !req.Response {
    var client = try Client.init(allocator, .{});
    defer client.deinit();

    var request = req.Request{
        .method = .GET,
        .url = url,
        .use_global_connection_pool = true,
    };

    return try client.perform(request);
}

pub fn post(allocator: std.mem.Allocator, url: []const u8, body: ?req.Body) !req.Response {
    var client = try Client.init(allocator, .{});
    defer client.deinit();

    var request = req.Request{
        .method = .POST,
        .url = url,
        .body = body,
        .use_global_connection_pool = true,
    };

    return try client.perform(request);
}

/// Caller is responsible for freeing the returned type
pub fn postAndParseResponse(
    comptime Type: type,
    parse_options: std.json.ParseOptions,
    allocator: std.mem.Allocator,
    url: []const u8,
    body: ?req.Body,
) !Type {
    var response = try post(allocator, url, body);
    defer response.deinit(); // we can throw the response away because parse will copy into the structure

    const response_bytes = response.body orelse return error.MissingResponseBody;
    var token_stream = std.json.TokenStream.init(response_bytes);
    return std.json.parse(Type, &token_stream, parse_options);
}

pub fn postJson(allocator: std.mem.Allocator, url: []const u8, json_value: anytype, stringify_options: std.json.StringifyOptions) !req.Response {
    var buffer = std.ArrayList(u8).init(allocator);
    defer buffer.deinit();

    var writer = buffer.writer();
    try std.json.stringify(json_value, stringify_options, writer);
    return post(allocator, url, req.Body{ .kind = .JSON, .bytes = buffer.items });
}

/// Caller is responsible for caling std.json.parseFree (with the same parseOptions) on the returned value
const PostAndParseOptions = struct {
    allocator: std.mem.Allocator,
    parse_options: std.json.ParseOptions = .{},
    stringify_options: std.json.StringifyOptions = .{},
};
fn parseOptionsWithAllocator(allocator: std.mem.Allocator, options: std.json.ParseOptions) std.json.ParseOptions {
    var newOpts = options;
    newOpts.allocator = allocator;
    return newOpts;
}

pub fn postJsonAndParseResponse(comptime OutputType: type, url: []const u8, json_value: anytype, options: PostAndParseOptions) !OutputType {
    var response = try postJson(options.allocator, url, json_value, options.stringify_options);
    defer response.deinit();

    const response_bytes = response.body orelse return error.MissingResponseBody;
    var token_stream = std.json.TokenStream.init(response_bytes);
    return std.json.parse(OutputType, &token_stream, parseOptionsWithAllocator(options.allocator, options.parse_options));
}

/// Caller is responsible for freeing the returned type
pub fn getAndParseResponse(
    comptime Type: type,
    parse_options: std.json.ParseOptions,
    allocator: std.mem.Allocator,
    url: []const u8,
) !Type {
    var response = try get(allocator, url);
    defer response.deinit(); // we can throw the response away because parse will copy into the structure

    const response_body = response.body orelse return error.MissingResponseBody;
    var json = std.json.TokenStream.init(response_body);

    return std.json.parse(Type, &json, parse_options);
}
