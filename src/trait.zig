const std = @import("std");

// support zig 0.11 as well as current master
pub usingnamespace if (@hasField(std.meta, "trait")) std.meta.trait else struct {
    const TraitFn = fn (type) bool;
    pub fn isNumber(comptime T: type) bool {
        return switch (@typeInfo(T)) {
            .Int, .Float, .ComptimeInt, .ComptimeFloat => true,
            else => false,
        };
    }
    pub fn isContainer(comptime T: type) bool {
        return switch (@typeInfo(T)) {
            .Struct, .Union, .Enum, .Opaque => true,
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
        if (comptime is(.Pointer)(T)) {
            return @typeInfo(T).Pointer.size == .One;
        }
        return false;
    }
    pub fn isIntegral(comptime T: type) bool {
        return switch (@typeInfo(T)) {
            .Int, .ComptimeInt => true,
            else => false,
        };
    }
    pub fn isZigString(comptime T: type) bool {
        return comptime blk: {
            // Only pointer types can be strings, no optionals
            const info = @typeInfo(T);
            if (info != .Pointer) break :blk false;

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
                if (child == .Array) {
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

            .AnyFrame,
            .Enum,
            .ErrorSet,
            .Fn,
            => return true,

            .Bool => return false,

            .Int => |info| return @sizeOf(T) * 8 == info.bits,

            .Pointer => |info| return info.size != .Slice,

            .Array => |info| return comptime hasUniqueRepresentation(info.child),

            .Struct => |info| {
                var sum_size = @as(usize, 0);

                inline for (info.fields) |field| {
                    const FieldType = field.type;
                    if (comptime !hasUniqueRepresentation(FieldType)) return false;
                    sum_size += @sizeOf(FieldType);
                }

                return @sizeOf(T) == sum_size;
            },

            .Vector => |info| return comptime hasUniqueRepresentation(info.child) and
                @sizeOf(T) == @sizeOf(info.child) * info.len,
        }
    }
};
