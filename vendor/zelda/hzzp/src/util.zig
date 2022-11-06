const std = @import("std");

// This is only used on buffers with an LF delimiter, so only CR needs to be checked
// LF is a valid line ending (RFC 7230, Section 3.5)
pub inline fn normalizeLineEnding(buffer: []const u8) []const u8 {
    if (buffer[buffer.len - 1] == '\r') return buffer[0 .. buffer.len - 1];

    return buffer;
}

pub const TransferEncoding = enum {
    content_length,
    chunked,
    unknown,
};

pub const ParserState = enum {
    start_line,
    header,
    body,
};

/// Compares two of any type for equality. Containers are compared on a field-by-field basis,
/// where possible. Pointers are not followed. Slices are compared by contents.
pub fn reworkedMetaEql(a: anytype, b: @TypeOf(a)) bool {
    const T = @TypeOf(a);

    switch (@typeInfo(T)) {
        .Struct => |info| {
            inline for (info.fields) |field_info| {
                if (!reworkedMetaEql(@field(a, field_info.name), @field(b, field_info.name))) return false;
            }
            return true;
        },
        .ErrorUnion => {
            if (a) |a_p| {
                if (b) |b_p| return reworkedMetaEql(a_p, b_p) else |_| return false;
            } else |a_e| {
                if (b) |_| return false else |b_e| return a_e == b_e;
            }
        },
        .Union => |info| {
            if (info.tag_type) |Tag| {
                const tag_a = std.meta.activeTag(a);
                const tag_b = std.meta.activeTag(b);
                if (tag_a != tag_b) return false;

                inline for (info.fields) |field_info| {
                    if (@field(Tag, field_info.name) == tag_a) {
                        return reworkedMetaEql(@field(a, field_info.name), @field(b, field_info.name));
                    }
                }
                return false;
            }

            @compileError("cannot compare untagged union type " ++ @typeName(T));
        },
        .Array => {
            if (a.len != b.len) return false;
            for (a) |e, i|
                if (!reworkedMetaEql(e, b[i])) return false;
            return true;
        },
        .Vector => |info| {
            var i: usize = 0;
            while (i < info.len) : (i += 1) {
                if (!reworkedMetaEql(a[i], b[i])) return false;
            }
            return true;
        },
        .Pointer => |info| {
            return switch (info.size) {
                .One, .Many, .C => a == b,
                .Slice => std.mem.eql(info.child, a, b),
            };
        },
        .Optional => {
            if (a == null and b == null) return true;
            if (a == null or b == null) return false;
            return reworkedMetaEql(a.?, b.?);
        },
        else => return a == b,
    }
}
