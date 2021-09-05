const root = @import("root");
const builtin = @import("builtin");
const std = @import("std");
const backend = @import("backend.zig");
const style = @import("style.zig");
const Widget = @import("widget.zig").Widget;
const Class  = @import("widget.zig").Class;
const Size = @import("data.zig").Size;

/// Allocator used for small, short-lived and repetitive allocations.
/// You can change this by setting the `zgtScratchAllocator` field in your main file
/// or by setting the `zgtAllocator` field which will also apply as lasting allocator.
pub const scratch_allocator = if (@hasDecl(root, "zgtScratchAllocator")) root.zgtScratchAllocator
    else if (@hasDecl(root, "zgtAllocator")) root.zgtAllocator
    else std.heap.page_allocator;

/// Allocator used for bigger, longer-lived but rare allocations (example: widgets).
/// You can change this by setting the `zgtLastingAllocator` field in your main file
/// or by setting the `zgtAllocator` field which will also apply as scratch allocator.
pub const lasting_allocator = if (@hasDecl(root, "zgtLastingAllocator")) root.zgtScratchAllocator
    else if (@hasDecl(root, "zgtAllocator")) root.zgtAllocator
    else std.heap.page_allocator;

pub fn All(comptime T: type) type {
    return struct {
        pub usingnamespace Events(T);
        pub usingnamespace Widgeting(T);
    };
}

// Styling
// pub fn Styling(comptime T: type) type {
//     return struct {
//         pub usingnamespace Measurement(T);
//     };
// }

pub fn Widgeting(comptime T: type) type {
    return struct {

        pub const WidgetClass = Class {
            .showFn = showWidget,
            .preferredSizeFn = getPreferredSizeWidget
        };

        pub fn showWidget(widget: *Widget) anyerror!void {
            const component = @intToPtr(*T, widget.data);
            try component.show();
            widget.peer = component.peer.?.peer;
        }

        pub fn getPreferredSizeWidget(widget: *const Widget, available: Size) Size {
            const component = @intToPtr(*T, widget.data);
            return component.getPreferredSize(available);
        }

        pub fn getWidth(self: *T) u32 {
            if (self.peer == null) return 0;
            return @intCast(u32, self.peer.?.getWidth());
        }

        pub fn getHeight(self: *T) u32 {
            if (self.peer == null) return 0;
            return @intCast(u32, self.peer.?.getHeight());
        }

    };
}

// pub fn Property(comptime T: type, comptime name: []const u8) type {
     // Depends on #6709
//     return struct {

//     };
// }

// Events
pub const RedrawError = error {
    MissingPeer
};

pub fn Events(comptime T: type) type {
    return struct {
        pub const Callback       = fn(widget: *T) anyerror!void;
        pub const DrawCallback   = fn(widget: *T, ctx: backend.Canvas.DrawContext) anyerror!void;
        pub const ButtonCallback = fn(widget: *T, button: backend.MouseButton, pressed: bool, x: f64, y: f64) anyerror!void;
        pub const ScrollCallback = fn(widget: *T, dx: f64, dy: f64) anyerror!void;
        pub const ResizeCallback = fn(widget: *T, size: Size) anyerror!void;
        const HandlerList        = std.ArrayList(Callback);
        const DrawHandlerList    = std.ArrayList(DrawCallback);
        const ButtonHandlerList  = std.ArrayList(ButtonCallback);
        const ScrollHandlerList  = std.ArrayList(ScrollCallback);
        const ResizeHandlerList  = std.ArrayList(ResizeCallback);

        pub const Handlers = struct {
            clickHandlers: HandlerList,
            drawHandlers: DrawHandlerList,
            buttonHandlers: ButtonHandlerList,
            scrollHandlers: ScrollHandlerList,
            resizeHandlers: ResizeHandlerList
        };

        pub fn init_events(self: T) T {
            var obj = self;
            obj.handlers = .{
                .clickHandlers = HandlerList.init(lasting_allocator),
                .drawHandlers = DrawHandlerList.init(lasting_allocator),
                .buttonHandlers = ButtonHandlerList.init(lasting_allocator),
                .scrollHandlers = ScrollHandlerList.init(lasting_allocator),
                .resizeHandlers = ResizeHandlerList.init(lasting_allocator)
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
                if (std.io.is_async) {
                    // can't use writeStackTrace as it is async but errorHandler should not be async!
                } else {
                    if (std.debug.getSelfDebugInfo()) |debug_info| {
                        var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
                        defer arena.deinit();
                        std.debug.writeStackTrace(trace.*, writer, &arena.allocator, debug_info, .no_color) catch {};
                    } else |_| { }
                }
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
                func(self, ctx) catch |err| errorHandler(err);
            }
        }

        fn buttonHandler(button: backend.MouseButton, pressed: bool, x: f64, y: f64, data: usize) void {
            const self = @intToPtr(*T, data);
            for (self.handlers.buttonHandlers.items) |func| {
                func(self, button, pressed, x, y) catch |err| errorHandler(err);
            }
        }

        fn scrollHandler(dx: f64, dy: f64, data: usize) void {
            const self = @intToPtr(*T, data);
            for (self.handlers.scrollHandlers.items) |func| {
                func(self, dx, dy) catch |err| errorHandler(err);
            }
        }

        fn resizeHandler(width: u32, height: u32, data: usize) void {
            const self = @intToPtr(*T, data);
            const size = Size { .width = width, .height = height };
            for (self.handlers.resizeHandlers.items) |func| {
                func(self, size) catch |err| errorHandler(err);
            }
        }

        pub fn show_events(self: *T) !void {
            self.peer.?.setUserData(self);
            try self.peer.?.setCallback(.Click      , clickHandler);
            try self.peer.?.setCallback(.Draw       , drawHandler);
            try self.peer.?.setCallback(.MouseButton, buttonHandler);
            try self.peer.?.setCallback(.Scroll     , scrollHandler);
            try self.peer.?.setCallback(.Resize     , resizeHandler);
        }

        pub fn addClickHandler(self: *T, handler: Callback) !void {
            try self.handlers.clickHandlers.append(handler);
        }

        pub fn addDrawHandler(self: *T, handler: DrawCallback) !void {
            try self.handlers.drawHandlers.append(handler);
        }

        pub fn addButtonHandler(self: *T, handler: ButtonCallback) !void {
            try self.handlers.buttonHandlers.append(handler);
        }

        pub fn addScrollHandler(self: *T, handler: ScrollCallback) !void {
            try self.handlers.scrollHandlers.append(handler);
        }

        pub fn addResizeHandler(self: *T, handler: ResizeCallback) !void {
            try self.handlers.resizeHandlers.append(handler);
        }

        pub fn requestDraw(self: *T) !void {
            if (self.peer) |*peer| {
                try peer.requestDraw();
            } else {
                return RedrawError.MissingPeer;
            }
        }
    };
}
