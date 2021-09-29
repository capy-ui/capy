const root = @import("root");
const builtin = @import("builtin");
const std = @import("std");
const backend = @import("backend.zig");
const style = @import("style.zig");
const Widget = @import("widget.zig").Widget;
const Class  = @import("widget.zig").Class;
const Size = @import("data.zig").Size;
const DataWrapper = @import("data.zig").DataWrapper;

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

        pub const DataWrappers = struct {
            opacity: DataWrapper(f64) = DataWrapper(f64).of(1.0),
            alignX: DataWrapper(f32) = DataWrapper(f32).of(0.5),
            alignY: DataWrapper(f32) = DataWrapper(f32).of(0.5),
            name: ?[]const u8 = null
        };

        pub fn showWidget(widget: *Widget) anyerror!void {
            const component = @intToPtr(*T, widget.data);
            try component.show();
            widget.peer = component.peer.?.peer;
        }

        pub fn pointerMoved(self: *T) void {
            self.dataWrappers.opacity.updateBinders();
            self.dataWrappers.alignX.updateBinders();
            self.dataWrappers.alignY.updateBinders();
            if (@hasDecl(T, "_pointerMoved")) {
                self._pointerMoved();
            }
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

        pub fn asWidget(self: *T) anyerror!Widget {
            return try genericWidgetFrom(self);
        }

        // Properties
        // TODO: pub usingnamespace Property(f64, "opacity");

        pub fn setOpacity(self: *T, opacity: f64) void {
            self.dataWrappers.opacity.set(opacity);
        }

        pub fn getOpacity(self: *T) f64 {
            return self.dataWrappers.opacity.get();
        }

        /// Bind the 'opacity' property to argument.
        pub fn bindOpacity(self: *T, other: *DataWrapper(f64)) T {
            self.dataWrappers.opacity.bind(other);
            self.dataWrappers.opacity.set(other.get());
            return self.*;
        }

        /// Bind the 'alignX' property to argument.
        pub fn bindAlignX(self: *T, other: *DataWrapper(f32)) T {
            self.dataWrappers.alignX.bind(other);
            self.dataWrappers.alignX.set(other.get());
            return self.*;
        }

        /// Bind the 'alignY' property to argument.
        pub fn bindAlignY(self: *T, other: *DataWrapper(f32)) T {
            self.dataWrappers.alignY.bind(other);
            self.dataWrappers.alignY.set(other.get());
            return self.*;
        }

    };
}

/// Create a generic Widget struct from the given component.
pub fn genericWidgetFrom(component: anytype) anyerror!Widget {
    const ComponentType = @TypeOf(component);
    if (ComponentType == Widget) return component;

    var cp = if (comptime std.meta.trait.isSingleItemPtr(ComponentType)) component else blk: {
        var copy = try lasting_allocator.create(ComponentType);
        copy.* = component;
        break :blk copy;
    };

    // used to update things like data wrappers, this happens once, at initialization,
    // after that the component isn't moved in memory anymore
    cp.pointerMoved();

    const DereferencedType = 
        if (comptime std.meta.trait.isSingleItemPtr(ComponentType))
            @TypeOf(component.*)
        else
            @TypeOf(component);
    return Widget {
        .data = @ptrToInt(cp),
        .class = &DereferencedType.WidgetClass,
        .name = &cp.dataWrappers.name,
        .alignX = &cp.dataWrappers.alignX,
        .alignY = &cp.dataWrappers.alignY
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
        pub const ButtonCallback = fn(widget: *T, button: backend.MouseButton, pressed: bool, x: u32, y: u32) anyerror!void;
        pub const ScrollCallback = fn(widget: *T, dx: f32, dy: f32) anyerror!void;
        pub const ResizeCallback = fn(widget: *T, size: Size) anyerror!void;
        pub const KeyTypeCallback= fn(widget: *T, key: []const u8) anyerror!void;
        const HandlerList        = std.ArrayList(Callback);
        const DrawHandlerList    = std.ArrayList(DrawCallback);
        const ButtonHandlerList  = std.ArrayList(ButtonCallback);
        const ScrollHandlerList  = std.ArrayList(ScrollCallback);
        const ResizeHandlerList  = std.ArrayList(ResizeCallback);
        const KeyTypeHandlerList = std.ArrayList(KeyTypeCallback);

        pub const Handlers = struct {
            clickHandlers: HandlerList,
            drawHandlers: DrawHandlerList,
            buttonHandlers: ButtonHandlerList,
            scrollHandlers: ScrollHandlerList,
            resizeHandlers: ResizeHandlerList,
            keyTypeHandlers: KeyTypeHandlerList,
            userdata: usize = 0,
        };

        pub fn init_events(self: T) T {
            var obj = self;
            obj.handlers = .{
                .clickHandlers = HandlerList.init(lasting_allocator),
                .drawHandlers = DrawHandlerList.init(lasting_allocator),
                .buttonHandlers = ButtonHandlerList.init(lasting_allocator),
                .scrollHandlers = ScrollHandlerList.init(lasting_allocator),
                .resizeHandlers = ResizeHandlerList.init(lasting_allocator),
                .keyTypeHandlers = KeyTypeHandlerList.init(lasting_allocator)
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

        fn buttonHandler(button: backend.MouseButton, pressed: bool, x: u32, y: u32, data: usize) void {
            const self = @intToPtr(*T, data);
            for (self.handlers.buttonHandlers.items) |func| {
                func(self, button, pressed, x, y) catch |err| errorHandler(err);
            }
        }

        fn keyTypeHandler(str: []const u8, data: usize) void {
            const self = @intToPtr(*T, data);
            for (self.handlers.keyTypeHandlers.items) |func| {
                func(self, str) catch |err| errorHandler(err);
            }
        }

        fn scrollHandler(dx: f32, dy: f32, data: usize) void {
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

        /// When the value is changed in the opacity data wrapper
        fn opacityChanged(newValue: f64, userdata: usize) void {
            const widget = @intToPtr(*T, userdata);
            if (widget.peer) |*peer| {
                peer.setOpacity(newValue);
            }
        }

        pub fn show_events(self: *T) !void {
            self.peer.?.setUserData(self);
            try self.peer.?.setCallback(.Click      , clickHandler);
            try self.peer.?.setCallback(.Draw       , drawHandler);
            try self.peer.?.setCallback(.MouseButton, buttonHandler);
            try self.peer.?.setCallback(.Scroll     , scrollHandler);
            try self.peer.?.setCallback(.Resize     , resizeHandler);
            try self.peer.?.setCallback(.KeyType    , keyTypeHandler);

            _ = try self.dataWrappers.opacity.addChangeListener(.{
                .function = opacityChanged,
                .userdata = @ptrToInt(self)
            });
            opacityChanged(self.dataWrappers.opacity.get(), @ptrToInt(self)); // call it so it's updated
        }

        pub fn addClickHandler(self: *T, handler: Callback) !void {
            try self.handlers.clickHandlers.append(handler);
        }

        pub fn addDrawHandler(self: *T, handler: DrawCallback) !T {
            try self.handlers.drawHandlers.append(handler);
            return self.*;
        }

        pub fn addMouseButtonHandler(self: *T, handler: ButtonCallback) !void {
            try self.handlers.buttonHandlers.append(handler);
        }

        pub fn addScrollHandler(self: *T, handler: ScrollCallback) !void {
            try self.handlers.scrollHandlers.append(handler);
        }

        pub fn addResizeHandler(self: *T, handler: ResizeCallback) !void {
            try self.handlers.resizeHandlers.append(handler);
        }

        pub fn addKeyTypeHandler(self: *T, handler: KeyTypeCallback) !void {
            std.log.info("add", .{});
            try self.handlers.keyTypeHandlers.append(handler);
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
