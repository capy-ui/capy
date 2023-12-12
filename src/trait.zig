const std = @import("std");

pub usingnamespace if (@hasField(std.meta,"trait")) std.meta.trait else struct {
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
    pub fn is(comptime id: std.builtin.TypeId) fn (type) bool {
        const Closure = struct {
            pub fn trait(comptime T: type) bool {
                return id == @typeInfo(T);
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
};
