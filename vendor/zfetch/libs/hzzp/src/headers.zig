const std = @import("std");

const ascii = std.ascii;
const mem = std.mem;

const common = @import("common.zig");

pub const Header = struct {
    name: []const u8,
    value: []const u8,
};

pub const HeadersSlice = []const Header;

const HeaderList = std.ArrayList(Header);
pub const Headers = struct {
    allocator: mem.Allocator,
    list: HeaderList,

    pub fn init(allocator: mem.Allocator) Headers {
        return .{
            .allocator = allocator,
            .list = HeaderList.init(allocator),
        };
    }

    pub fn deinit(self: *Headers) void {
        for (self.list.items) |header| {
            self.allocator.free(header.name);
            self.allocator.free(header.value);
        }

        self.list.deinit();
    }

    pub inline fn ensureCapacity(self: *Headers, new_capacity: usize) !void {
        return self.list.ensureCapacity(new_capacity);
    }

    pub fn appendValue(self: *Headers, name: []const u8, value: []const u8) !void {
        const duped_name = try self.allocator.dupe(u8, name);
        const duped_value = try self.allocator.dupe(u8, value);

        try self.list.append(.{
            .name = duped_name,
            .value = duped_value,
        });
    }

    pub inline fn append(self: *Headers, header: Header) !void {
        return self.appendValue(header.name, header.value);
    }

    pub inline fn appendSlice(self: *Headers, headers: HeadersSlice) !void {
        for (headers) |header| {
            try self.appendValue(header.name, header.value);
        }
    }

    pub fn contains(self: Headers, name: []const u8) bool {
        for (self.list.items) |header| {
            if (ascii.eqlIgnoreCase(header.name, name)) {
                return true;
            }
        }

        return false;
    }

    pub fn search(self: Headers, name: []const u8) ?Header {
        for (self.list.items) |header| {
            if (ascii.eqlIgnoreCase(header.name, name)) {
                return header;
            }
        }

        return null;
    }

    pub fn indexOf(self: Headers, name: []const u8) ?usize {
        for (self.list.items) |header, index| {
            if (ascii.eqlIgnoreCase(header.name, name)) {
                return index;
            }
        }

        return null;
    }

    pub fn set(self: *Headers, name: []const u8, value: []const u8) !void {
        if (self.indexOf(name)) |idx| {
            const duped_value = try self.allocator.dupe(u8, value);
            const old = self.list.items[idx];

            // Is this safe? possible use-after-free in userland code.
            self.allocator.free(old.value);

            self.list.items[idx] = .{
                .name = old.name,
                .value = duped_value,
            };
        } else {
            return self.appendValue(name, value);
        }
    }

    pub fn get(self: Headers, name: []const u8) ?[]const u8 {
        if (self.search(name)) |header| {
            return header.value;
        } else {
            return null;
        }
    }
};

const testing = std.testing;

test "headers append and get properly" {
    var headers = Headers.init(testing.allocator);
    defer headers.deinit();

    var list = [_]Header{
        .{ .name = "Header2", .value = "value2" },
        .{ .name = "Header3", .value = "value3" },
    };

    try headers.appendValue("Host", "localhost");
    try headers.append(.{ .name = "Header1", .value = "value1" });
    try headers.appendSlice(&list);

    try testing.expectEqualStrings("value1", headers.search("Header1").?.value);
    try testing.expect(headers.contains("Header2"));
    try testing.expect(headers.indexOf("Header3").? == 3);

    try testing.expectEqualStrings("value1", headers.get("Header1").?);

    try headers.set("Header1", "value4");

    try testing.expectEqualStrings("value4", headers.get("Header1").?);
}

comptime {
    std.testing.refAllDecls(@This());
}
