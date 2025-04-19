const std = @import("std");

// support zig 0.11 as well as current master
pub usingnamespace if (@hasField(std.meta, "trait")) std.meta.trait else struct {
    const TraitFn = fn (type) bool;
    pub fn isNumber(comptime T: type) bool {
        return switch (@typeInfo(T)) {
            .int, .float, .comptime_int, .comptime_float => true,
            else => false,
        };
    }
    pub fn isContainer(comptime T: type) bool {
        return switch (@typeInfo(T)) {
            .@"struct", .@"union", .@"enum", .@"opaque" => true,
            else => false,
        };
    }
    pub fn is(comptime id: std.builtin.TypeId) TraitFn {
        const Closure = struct {
            pub fn trait(comptime T: type) bool {
                return id == @typeInfo(T);
            }
        };
        return Closure.trait;
    }
    pub fn isPtrTo(comptime id: std.builtin.TypeId) TraitFn {
        const Closure = struct {
            pub fn trait(comptime T: type) bool {
                if (!comptime isSingleItemPtr(T)) return false;
                return id == @typeInfo(std.meta.Child(T));
            }
        };
        return Closure.trait;
    }
    pub fn isSingleItemPtr(comptime T: type) bool {
        if (comptime is(.pointer)(T)) {
            return @typeInfo(T).pointer.size == .one;
        }
        return false;
    }
    pub fn isIntegral(comptime T: type) bool {
        return switch (@typeInfo(T)) {
            .int, .comptime_int => true,
            else => false,
        };
    }
    pub fn isZigString(comptime T: type) bool {
        return comptime blk: {
            // Only pointer types can be strings, no optionals
            const info = @typeInfo(T);
            if (info != .pointer) break :blk false;

            const ptr = &info.Pointer;
            // Check for CV qualifiers that would prevent coerction to []const u8
            if (ptr.is_volatile or ptr.is_allowzero) break :blk false;

            // If it's already a slice, simple check.
            if (ptr.size == .Slice) {
                break :blk ptr.child == u8;
            }

            // Otherwise check if it's an array type that coerces to slice.
            if (ptr.size == .One) {
                const child = @typeInfo(ptr.child);
                if (child == .array) {
                    const arr = &child.Array;
                    break :blk arr.child == u8;
                }
            }

            break :blk false;
        };
    }
    pub fn hasUniqueRepresentation(comptime T: type) bool {
        switch (@typeInfo(T)) {
            else => return false, // TODO can we know if it's true for some of these types ?

            .@"anyframe",
            .@"enum",
            .error_set,
            .@"fn",
            => return true,

            .bool => return false,

            .int => |info| return @sizeOf(T) * 8 == info.bits,

            .pointer => |info| return info.size != .Slice,

            .array => |info| return comptime hasUniqueRepresentation(info.child),

            .@"struct" => |info| {
                var sum_size = @as(usize, 0);

                inline for (info.fields) |field| {
                    const FieldType = field.type;
                    if (comptime !hasUniqueRepresentation(FieldType)) return false;
                    sum_size += @sizeOf(FieldType);
                }

                return @sizeOf(T) == sum_size;
            },

            .vector => |info| return comptime hasUniqueRepresentation(info.child) and
                @sizeOf(T) == @sizeOf(info.child) * info.len,
        }
    }
};
