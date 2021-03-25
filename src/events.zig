const std = @import("std");
const backend = @import("backend.zig");
usingnamespace @import("internal.zig");

pub fn Events(comptime T: type) type {
    return struct {
        pub const Callback    = fn(widget: *T) anyerror!void;
        pub const HandlerList = std.ArrayList(Callback);
        const DrawHandlerList = std.ArrayList(fn(ctx: backend.Canvas.DrawContext, widget: *T) anyerror!void);

        pub const Handlers = struct {
            clickHandlers: HandlerList,
            drawHandlers: DrawHandlerList
        };

        pub fn init_events(self: T) T {
            var obj = self;
            obj.handlers = .{
                .clickHandlers = HandlerList.init(lasting_allocator),
                .drawHandlers = DrawHandlerList.init(lasting_allocator)
            };
            return obj;
        }

        fn errorHandler(err: anyerror) void {
            std.log.err("{s}", .{@errorName(err)});
            var streamBuf: [16384]u8 = undefined;
            var stream = std.io.fixedBufferStream(&streamBuf);
            var writer = stream.writer();
            writer.print("Internal error: {s}.\n", .{@errorName(err)}) catch {};
            if (@errorReturnTrace()) |trace| {
                std.debug.dumpStackTrace(trace.*);
                if (std.debug.getSelfDebugInfo()) |debug_info| {
                    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
                    defer arena.deinit();
                    std.debug.writeStackTrace(trace.*, writer, &arena.allocator, debug_info, .no_color) catch {};
                } else |e| {}
            }
            writer.print("Please check the log.", .{}) catch {};
            backend.showNativeMessageDialog(.Error, "{s}", .{stream.getWritten()});
        }

        fn clickHandler(data: usize) void {
            const self = @intToPtr(*T, data);
            for (self.handlers.clickHandlers.items) |func| {
                func(self) catch |err| errorHandler(err);
            }
        }

        fn drawHandler(ctx: backend.Canvas.DrawContext, data: usize) void {
            const self = @intToPtr(*T, data);
            for (self.handlers.drawHandlers.items) |func| {
                func(ctx, self) catch |err| errorHandler(err);
            }
        }

        pub fn show_events(self: *T) !void {
            self.peer.?.setUserData(self);
            try self.peer.?.setCallback(.Click, clickHandler);
            try self.peer.?.setCallback(.Draw,  drawHandler);
        }

        pub fn addClickHandler(self: *T, handler: Callback) !void {
            try self.handlers.clickHandlers.append(handler);
        }

        pub fn addDrawHandler(self: *T, handler: fn(ctx: backend.Canvas.DrawContext, widget: *T) anyerror!void) !void {
            try self.handlers.drawHandlers.append(handler);
        }
    };
}
