const std = @import("std");
const backend = @import("backend.zig");

pub fn Events(comptime T: type) type {
    return struct {
        pub const Callback    = fn(widget: *T) anyerror!void;
        pub const HandlerList = std.ArrayList(Callback);

        pub fn init_events(self: T) T {
            var obj = self;
            obj.clickHandlers = HandlerList.init(std.heap.page_allocator);
            return obj;
        }

        fn clickHandler(data: usize) void {
            const self = @intToPtr(*T, data);
            for (self.clickHandlers.items) |func| {
                func(self) catch |err| {
                    std.log.err("{s}", .{@errorName(err)});
                    var streamBuf: [4096]u8 = undefined;
                    var stream = std.io.fixedBufferStream(&streamBuf);
                    var writer = stream.writer();
                    writer.print("Internal error: {s}.\n", .{@errorName(err)}) catch unreachable;
                    if (@errorReturnTrace()) |trace| {
                        std.debug.dumpStackTrace(trace.*);
                        if (std.debug.getSelfDebugInfo()) |debug_info| {
                            var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
                            defer arena.deinit();
                            std.debug.writeStackTrace(trace.*, writer, &arena.allocator, debug_info, .no_color) catch {};
                        } else |e| {}

                    }
                    writer.writeAll("Please check the log.") catch unreachable;
                    backend.showNativeMessageDialog(.Error, "{s}", .{stream.getWritten()});
                };
            }
        }

        pub fn show_events(self: *T) !void {
            self.peer.?.setUserData(self);
            try self.peer.?.setCallback(.Click, clickHandler);
        }

        pub fn addClickHandler(self: *T, handler: Callback) !void {
            try self.clickHandlers.append(handler);
        }
    };
}
