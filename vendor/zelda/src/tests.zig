const std = @import("std");
const zelda = @import("zelda");

// NOTE: this test will fail if ziglang.org is down!
test "fetch status code of ziglang.org" {
    defer zelda.cleanup();
    var response = try zelda.get(std.testing.allocator, "https://ziglang.org");
    defer response.deinit();

    try std.testing.expectEqual(@as(u10, 200), @enumToInt(response.status_code));
}

const HTTPBinResponse = struct {
    data: []const u8,
};

test "post some data and get it back" {
    defer zelda.cleanup();

    const data = "bruh moment";

    var response = try zelda.postAndParseResponse(HTTPBinResponse, .{
        .allocator = std.testing.allocator,
        .ignore_unknown_fields = true,
    }, std.testing.allocator, "https://httpbin.org/post", .{ .kind = .Raw, .bytes = data });
    defer std.json.parseFree(HTTPBinResponse, response, .{
        .allocator = std.testing.allocator,
        .ignore_unknown_fields = true,
    });

    try std.testing.expectEqualStrings(data, response.data);
}

const TestDataStruct = struct {
    number_of_bruhs: usize,
    bruh_status: []const u8,
    maximum_bruh_enabled: bool,
};

test "post some json data and get it back" {
    defer zelda.cleanup();

    var source = TestDataStruct{
        .number_of_bruhs = 69,
        .bruh_status = "engaged",
        .maximum_bruh_enabled = true,
    };
    var http_bin_response = try zelda.postJsonAndParseResponse(HTTPBinResponse, "https://httpbin.org/post", source, .{
        .allocator = std.testing.allocator,
        .parse_options = .{ .ignore_unknown_fields = true },
    });
    defer std.json.parseFree(HTTPBinResponse, http_bin_response, .{
        .allocator = std.testing.allocator,
        .ignore_unknown_fields = true,
    });

    var token_stream = std.json.TokenStream.init(http_bin_response.data);
    var obj = try std.json.parse(TestDataStruct, &token_stream, .{
        .allocator = std.testing.allocator,
        .ignore_unknown_fields = true,
    });
    defer std.json.parseFree(TestDataStruct, obj, .{
        .allocator = std.testing.allocator,
        .ignore_unknown_fields = true,
    });

    try std.testing.expectEqual(source.number_of_bruhs, obj.number_of_bruhs);
    try std.testing.expectEqual(source.maximum_bruh_enabled, obj.maximum_bruh_enabled);
    try std.testing.expectEqualStrings(source.bruh_status, obj.bruh_status);
}
