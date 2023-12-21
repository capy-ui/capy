//! Randomly test data and lower it down
const std = @import("std");
const trait = @import("trait.zig");

pub fn forAll(comptime T: type) Iterator(T) {
    return Iterator(T).init();
}

fn threwError(func: anytype, item: anytype) bool {
    const originalStackDepth: usize = blk: {
        if (@errorReturnTrace()) |trace| {
            break :blk trace.index;
        } else {
            break :blk 0;
        }
    };
    func(item) catch {
        if (@errorReturnTrace()) |trace| {
            // dirty manual tinkering to avoid Zig polluting the return trace
            trace.index = originalStackDepth;
        }
        return true;
    };
    return false;
}

pub fn testFunction(comptime T: type, duration: i64, func: fn (T) anyerror!void) anyerror!void {
    var iterator = Iterator(T).init();
    iterator.duration = duration;

    const Hypothesis = struct {
        elements: std.ArrayList(HypothesisElement),

        const Self = @This();

        const HypothesisElement = union(enum) {
            // only for numbers
            BiggerThan: T,
            SmallerThan: T,

            pub fn format(value: HypothesisElement, comptime _: []const u8, _: std.fmt.FormatOptions, writer: anytype) !void {
                switch (value) {
                    .BiggerThan => |v| {
                        try writer.print("bigger than {d}", .{v});
                    },
                    .SmallerThan => |v| {
                        try writer.print("smaller than {d}", .{v});
                    },
                }
            }
        };

        /// Tries to find counter-examples (case where there is no error) in the
        /// given time and adjust the hypothesis based on that counter-example.
        pub fn refine(self: *Self, time: i64, callback: fn (T) anyerror!void) void {
            var prng = std.rand.DefaultPrng.init(@as(u64, @bitCast(std.time.milliTimestamp())));
            const random = prng.random();

            const timePerElement = @divFloor(time, @as(i64, @intCast(self.elements.items.len)));
            for (self.elements.items) |*element| {
                const start = std.time.milliTimestamp();
                var stepSize: T = 1000;
                while (std.time.milliTimestamp() < start + timePerElement) {
                    switch (element.*) {
                        .BiggerThan => |value| {
                            //const add = random.uintLessThanBiased(T, stepSize);
                            if (threwError(callback, value) and threwError(callback, value -| 1)) {
                                element.* = .{ .BiggerThan = value -| 1 };
                            }
                            // if (threwError(callback, value -| add)) {
                            //     element.* = .{ .BiggerThan = value -| add };
                            //     stepSize *|= 2;
                            //     if (threwError(callback, value +| add)) {
                            //         element.* = .{ .BiggerThan = value +| add };
                            //         stepSize = std.math.max(1, stepSize / 3);
                            //     }
                            // } else {
                            //     //stepSize /= 2;
                            // }
                        },
                        .SmallerThan => |value| {
                            const add = random.uintLessThanBiased(T, stepSize);
                            if (threwError(callback, value +| add)) {
                                element.* = .{ .SmallerThan = value +| add };
                                //stepSize *|= 2;
                                if (stepSize < 1) stepSize = 1;
                            } else {
                                stepSize /= 2;
                            }
                        },
                    }
                }
            }
        }

        pub fn format(value: Self, comptime _: []const u8, _: std.fmt.FormatOptions, writer: anytype) !void {
            for (value.elements.items) |item| {
                try writer.print("{}, ", .{item});
            }
        }

        pub fn deinit(self: Self) void {
            self.elements.deinit();
        }
    };

    // This stores a number of values and tries to found what's in common between thems
    const BreakCondition = struct {
        items: []T,

        const Self = @This();

        pub fn init(items: []T) Self {
            return .{ .items = items };
        }

        pub fn hypothetize(self: *Self, callback: fn (T) anyerror!void) !Hypothesis {
            var elements = std.ArrayList(Hypothesis.HypothesisElement).init(std.testing.allocator);
            if (comptime trait.isNumber(T)) {
                std.sort.sort(T, self.items, {}, comptime std.sort.asc(T));
                const smallest = self.items[0];
                const biggest = self.items[self.items.len - 1];
                try elements.append(.{ .BiggerThan = biggest });
                try elements.append(.{ .SmallerThan = smallest });
            }

            var hypothesis = Hypothesis{ .elements = elements };
            std.debug.print("\nCaught {d} errors. Base hypothesis: {}", .{ self.items.len, hypothesis });
            std.debug.print("\nRefining hypothesis..", .{});
            hypothesis.refine(3000, callback);
            return hypothesis;
        }
    };

    //var errorsWith = std.ArrayList(T).init(std.testing.allocator);
    var errorsWith = std.AutoArrayHashMap(T, void).init(std.testing.allocator);
    defer errorsWith.deinit();
    while (iterator.next()) |item| {
        if (!errorsWith.contains(item)) {
            if (threwError(func, item)) {
                try errorsWith.put(item, {});
            }
        }
    }

    if (errorsWith.count() > 0) {
        var breakCond = BreakCondition.init(errorsWith.keys());
        const hypothesis = try breakCond.hypothetize(func);
        defer hypothesis.deinit();

        std.debug.print("\nThe function fails when using a value that is {}\n", .{hypothesis});
        std.debug.print("---\nError return trace with {any}:\n", .{errorsWith.keys()[0]});
        return try func(errorsWith.keys()[0]);
    }
}

pub fn Iterator(comptime T: type) type {
    return struct {
        count: usize = 0,
        rand: std.rand.DefaultPrng,
        start: i64,
        /// Duration in milliseconds
        duration: i64,

        pub const Self = @This();
        const DETERMINISTIC_TEST = false;

        pub fn init() Self {
            return Self{
                .rand = std.rand.DefaultPrng.init(if (DETERMINISTIC_TEST) 0 else @as(u64, @truncate(@as(u128, @bitCast(std.time.nanoTimestamp()))))),
                .start = std.time.milliTimestamp(),
                .duration = 100,
            };
        }

        pub fn next(self: *Self) ?T {
            if (!comptime std.meta.hasUniqueRepresentation(T)) {
                @compileError(@typeName(T) ++ " doesn't have an unique representation");
            }
            //if (self.count >= 10) return null;
            if (std.time.milliTimestamp() >= self.start + self.duration) {
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
        const container = ColorContainer{ .color = color };
        try std.testing.expectEqual(color, container.color);
    }
}

test "basic bisecting" {
    if (true) return error.SkipZigTest;

    // As we're seeking values under 1000 among 4 billion randomly generated values,
    // we need to run this test for longer
    try testFunction(u16, 500, struct {
        pub fn callback(value: u16) !void {
            try std.testing.expect(value > 1000);
            try std.testing.expect(value < 5000);
        }
    }.callback);
}
