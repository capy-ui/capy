const std = @import("std");

const ascii = std.ascii;
const mem = std.mem;
const fs = std.fs;
const io = std.io;

pub fn main() !void {
    const allocator = std.heap.page_allocator;

    const out = try fs.cwd().createFile("status_codes.zig", .{});
    defer out.close();

    const stdout = out.writer();

    const file = try fs.cwd().openFile("status_codes.csv", .{});
    defer file.close();

    const content = try file.readToEndAlloc(allocator, 4 * 1024);
    defer allocator.free(content);

    try stdout.writeAll("// zig fmt: off\n");
    try stdout.writeAll("pub const StatusCode = enum(u10) {\n");
    try stdout.writeAll("    // https://www.iana.org/assignments/http-status-codes/http-status-codes.txt (2018-09-21)\n");

    var line_it = mem.split(mem.trim(u8, content, &ascii.spaces), "\r\n");
    _ = line_it.next();

    while (line_it.next()) |line| {
        var value_it = mem.split(line, ",");

        const code = value_it.next().?;
        const name = value_it.next().?;
        const rfc = value_it.rest();

        if (code[1] == '0' and code[2] == '0') try stdout.writeAll("\n");

        try stdout.writeAll("    ");
        if (mem.eql(u8, name, "Unassigned") or mem.eql(u8, name, "(Unused)")) {
            try stdout.print("// {s} {s}", .{ code, name });
        } else {
            var len = name.len;

            switch (code[0]) {
                '1' => {
                    try stdout.writeAll("info_");
                    len += 5;
                },
                '2' => {
                    try stdout.writeAll("success_");
                    len += 8;
                },
                '3' => {
                    try stdout.writeAll("redirect_");
                    len += 9;
                },
                '4' => {
                    try stdout.writeAll("client_");
                    len += 7;
                },
                '5' => {
                    try stdout.writeAll("server_");
                    len += 7;
                },
                else => unreachable,
            }

            for (name) |c| {
                if (ascii.isPunct(c) or ascii.isSpace(c)) {
                    try stdout.writeAll("_");
                } else {
                    try stdout.writeByte(ascii.toLower(c));
                }
            }

            try stdout.print(" = {s},", .{code});

            try stdout.writeByteNTimes(' ', 40 - len);

            try stdout.print("// {s}", .{mem.trim(u8, rfc, "[\"]")});
        }

        try stdout.writeAll("\n");
    }

    try stdout.writeAll(
        \\
        \\    _,
        \\
        \\    pub fn code(self: StatusCode) std.meta.Tag(StatusCode) {
        \\        return @enumToInt(self);
        \\    }
        \\
        \\    pub fn isValid(self: StatusCode) bool {
        \\        return @enumToInt(self) >= 100 and @enumToInt(self) < 600;
        \\    }
        \\
        \\    pub const Group = enum { info, success, redirect, client_error, server_error, invalid };
        \\    pub fn group(self: StatusCode) Group {
        \\        return switch (self.code()) {
        \\            100...199 => .info,
        \\            200...299 => .success,
        \\            300...399 => .redirect,
        \\            400...499 => .client_error,
        \\            500...599 => .server_error,
        \\            else => .invalid,
        \\        };
        \\    }
        \\
    );

    try stdout.writeAll("};\n");
    try stdout.writeAll("// zig fmt: on");
}
