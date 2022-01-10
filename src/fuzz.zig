//! Randomly test data and lower it down
const std = @import("std");

pub fn forAll(comptime T: type) Iterator(T) {
    return Iterator(T).init();
}

pub fn Iterator(comptime T: type) type {
    return struct {
        count: usize = 0,
        rand: std.rand.DefaultPrng,
        start: i64,

        pub const Self = @This();
        const DETERMINISTIC_TEST = false;

        pub fn init() Self {
            return Self{
                .rand = std.rand.DefaultPrng.init(if (DETERMINISTIC_TEST) 0 else
                @truncate(u64, @bitCast(u128, std.time.nanoTimestamp()))),
                .start = std.time.milliTimestamp(),
            };
        }

        pub fn next(self: *Self) ?T {
            if (!comptime std.meta.trait.hasUniqueRepresentation(T)) {
                @compileError(@typeName(T) ++ " doesn't have an unique representation");
            }
            //if (self.count >= 10) return null;
            if (std.time.milliTimestamp() >= self.start + 100) {
                std.log.scoped(.iterator).debug("Did {d} rounds in {d} ms", .{ self.count, std.time.milliTimestamp() - self.start });
                return null;
            }

            self.count += 1;
            var bytes: [@sizeOf(T)]u8 = undefined;
            self.rand.fill(&bytes);
            return std.mem.bytesToValue(T, &bytes);
        }
    };
}

const ColorContainer = struct {
    color: @import("color.zig").Color,
};

test "simple struct init" {
    var all = forAll(@import("color.zig").Color);
    while (all.next()) |color| {
        var container = ColorContainer{ .color = color };
        try std.testing.expectEqual(color, container.color);
    }
}
