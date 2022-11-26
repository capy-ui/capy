const root = @import("root");
const builtin = @import("builtin");
const std = @import("std");
const backend = @import("backend.zig");
const style = @import("style.zig");
const dataStructures = @import("data.zig");
const Widget = @import("widget.zig").Widget;
const Class = @import("widget.zig").Class;
const Size = dataStructures.Size;
const DataWrapper = dataStructures.DataWrapper;
const Container_Impl = @import("containers.zig").Container_Impl;
const Layout = @import("containers.zig").Layout;
const MouseButton = @import("backends/shared.zig").MouseButton;

const link_libc = @import("builtin").link_libc;

/// The default allocator if capy_scratch_allocator or capy_lasting_allocator isn't defined
const default_allocator = blk: {
    if (@hasDecl(root, "capy_allocator")) {
        break :blk root.capy_allocator;
    } else if (@import("builtin").is_test) {
        break :blk std.testing.allocator;
    } else if (link_libc) {
        break :blk std.heap.c_allocator;
    } else {
        break :blk std.heap.page_allocator;
    }
};

/// Allocator used for small, short-lived and repetitive allocations.
/// You can change this by setting the `capy_scratch_allocator` field in your main file
/// or by setting the `zgtAllocator` field which will also apply as lasting allocator.
pub const scratch_allocator = if (@hasDecl(root, "capy_scratch_allocator")) root.capy_scratch_allocator else default_allocator;

/// Allocator used for bigger, longer-lived but rare allocations (example: widgets).
/// You can change this by setting the `capy_lasting_allocator` field in your main file
/// or by setting the `zgtAllocator` field which will also apply as scratch allocator.
pub const lasting_allocator = if (@hasDecl(root, "capy_lasting_allocator")) root.capy_lasting_allocator else default_allocator;

/// Convenience function for creating widgets
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

/// Convenience function for creating widgets
pub fn Widgeting(comptime T: type) type {
    return struct {
        pub const WidgetClass = Class{
            .typeName = @typeName(T),

            .showFn = showWidget,
            .deinitFn = deinitWidget,
            .preferredSizeFn = getPreferredSizeWidget,
            .setWidgetFn = setWidgetFn,
        };

        pub const DataWrappers = struct {
            opacity: DataWrapper(f32) = DataWrapper(f32).of(1.0),
            alignX: DataWrapper(?f32) = DataWrapper(?f32).of(null),
            alignY: DataWrapper(?f32) = DataWrapper(?f32).of(null),
            name: DataWrapper(?[]const u8) = DataWrapper(?[]const u8).of(null),

            /// The widget representing this component
            widget: ?*Widget = null,
        };

        pub const Config = GenerateConfigStruct(T);

        /// When alignX or alignY is changed, this will trigger a parent relayout
        fn alignChanged(new: ?f32, userdata: usize) void {
            _ = new;

            const widget = @intToPtr(*Widget, userdata);
            if (widget.parent) |parent| {
                const container = parent.as(@import("containers.zig").Container_Impl);
                container.relayout();
            }
        }

        pub fn showWidget(widget: *Widget) anyerror!void {
            const component = widget.as(T);
            try component.show();
            widget.peer = component.peer.?.peer;

            _ = try component.dataWrappers.alignX.addChangeListener(.{ .function = alignChanged, .userdata = @ptrToInt(widget) });
            _ = try component.dataWrappers.alignY.addChangeListener(.{ .function = alignChanged, .userdata = @ptrToInt(widget) });

            // if the widget wants to do some operations on showWidget
            if (@hasDecl(T, "_showWidget")) {
                try T._showWidget(widget, component);
            }
        }

        pub fn setWidgetFn(widget: *Widget) void {
            const component = widget.as(T);
            component.dataWrappers.widget = widget;
        }

        pub fn deinitWidget(widget: *Widget) void {
            const component = widget.as(T);
            component.deinit();

            if (widget.allocator) |allocator| allocator.destroy(component);
        }

        pub fn deinit(self: *T) void {
            if (@hasDecl(T, "_deinit")) {
                self._deinit();
            }

            self.dataWrappers.widget = null;
            self.dataWrappers.opacity.deinit();
            self.dataWrappers.alignX.deinit();
            self.dataWrappers.alignY.deinit();

            self.handlers.clickHandlers.deinit();
            self.handlers.drawHandlers.deinit();
            self.handlers.buttonHandlers.deinit();
            self.handlers.mouseMoveHandlers.deinit();
            self.handlers.scrollHandlers.deinit();
            self.handlers.resizeHandlers.deinit();
            self.handlers.keyTypeHandlers.deinit();

            if (self.peer) |peer| peer.deinit();
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
            const component = widget.as(T);
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

        // TODO: consider using something like https://github.com/MasterQ32/any-pointer for userdata
        // to get some safety
        pub fn setUserdata(self: *T, userdata: ?*anyopaque) void {
            self.handlers.userdata = userdata;
        }

        pub fn getUserdata(self: *T, comptime U: type) U {
            return @ptrCast(U, self.handlers.userdata);
        }

        // Properties
        fn TypeOfProperty(comptime name: []const u8) type {
            if (@hasField(T, name)) {
                return @TypeOf(@field(@as(T, undefined), name)).ValueType;
            } else if (@hasField(DataWrappers, name)) {
                return @TypeOf(@field(@as(DataWrappers, undefined), name)).ValueType;
            } else {
                comptime {
                    var compileError: []const u8 = "No such property: " ++ name;
                    if (T == Container_Impl) {
                        compileError = compileError ++ ", did you mean to use getChild() ?";
                    }
                    @compileError(compileError);
                }
            }
        }

        // This method temporarily returns the component for chaining methods
        // This will be reconsidered later and thus might be removed.
        pub fn set(self: *T, comptime name: []const u8, value: TypeOfProperty(name)) void {
            if (@hasField(DataWrappers, name)) {
                @field(self.dataWrappers, name).set(value);
            } else {
                @field(self, name).set(value);
            }
        }

        pub fn get(self: T, comptime name: []const u8) TypeOfProperty(name) {
            if (@hasField(DataWrappers, name)) {
                return @field(self.dataWrappers, name).get();
            } else {
                return @field(self, name).get();
            }
        }

        /// Bind the given property to argument
        pub fn bind(self: *T, comptime name: []const u8, other: *DataWrapper(TypeOfProperty(name))) void {
            if (@hasField(DataWrappers, name)) {
                @field(self.dataWrappers, name).bind(other);
            } else {
                @field(self, name).bind(other);
            }
            self.set(name, other.get());
        }

        pub fn getName(self: *T) ?[]const u8 {
            return self.dataWrappers.name;
        }

        pub fn setName(self: *T, name: ?[]const u8) void {
            self.dataWrappers.name.set(name);
        }

        pub fn getWidget(self: *T) ?*Widget {
            return self.dataWrappers.widget;
        }

        // This can return a Container_Impl as parents are always a container
        pub fn getParent(self: *T) ?*Container_Impl {
            if (self.dataWrappers.widget) |widget| {
                if (widget.parent) |parent| {
                    return parent.as(Container_Impl);
                }
            }
            return null;
        }

        /// Go up the widget tree until we find the root (which is the component
        /// put with window.set()
        /// Returns null if the component is unparented.
        pub fn getRoot(self: *T) ?*Container_Impl {
            var parent = self.getParent() orelse return null;
            while (true) {
                const ancester = parent.getParent();
                if (ancester) |newParent| {
                    parent = newParent;
                } else {
                    break;
                }
            }

            return parent;
        }
    };
}

/// Generate a config struct that allows with all the properties of the given type
pub fn GenerateConfigStruct(comptime T: type) type {
    // TODO: .onclick = &.{ handlerOne, handlerTwo }, for other event handlers
    comptime {
        var config_fields: []const std.builtin.Type.StructField = &.{};
        iterateFields(&config_fields, T);

        const default_value: ?T.Callback = null;
        config_fields = config_fields ++ &[1]std.builtin.Type.StructField{.{
            .name = "onclick",
            .field_type = ?*const fn (widget: *anyopaque) anyerror!void,
            .default_value = @ptrCast(?*const anyopaque, &default_value),
            .is_comptime = false,
            .alignment = @alignOf(?T.Callback),
        }};


        const t = @Type(.{ .Struct = .{
            .layout = .Auto,
            .backing_integer = null,
            .fields = config_fields,
            .decls = &.{},
            .is_tuple = false,
        } });
    // @compileError(t);
        return t;
    }
}

fn iterateFields(comptime config_fields: *[]const std.builtin.Type.StructField, comptime T: type) void {
    for (std.meta.fields(T)) |field| {
        const FieldType = field.field_type;
        if (dataStructures.isDataWrapper(FieldType)) {
            const default_value = if (field.default_value) |default| @ptrCast(*const FieldType, @alignCast(@alignOf(FieldType), default)).getUnsafe() else null;
            const has_default_value = field.default_value != null;

            config_fields.* = config_fields.* ++ &[1]std.builtin.Type.StructField{.{
                .name = field.name,
                .field_type = FieldType.ValueType,
                .default_value = if (has_default_value) @ptrCast(?*const anyopaque, @alignCast(1, &default_value)) else null,
                .is_comptime = false,
                .alignment = @alignOf(FieldType.ValueType),
            }};
        } else if (comptime std.meta.trait.is(.Struct)(FieldType)) {
            iterateFields(config_fields, FieldType);
        }
    }
}

pub fn applyConfigStruct(target: anytype, config: anytype) void {
    _ = target;
    _ = config;
}

/// If T is a pointer, return the type it points to, otherwise return T.
/// Example: DereferencedType(*Button_Impl) = Button_Impl
pub fn DereferencedType(comptime T: type) type {
    return if (comptime std.meta.trait.isSingleItemPtr(T))
        std.meta.Child(T)
    else
        T;
}

/// Create a generic Widget struct from the given component.
/// This method will set dataWrappers.widget field and can only be called once.
pub fn genericWidgetFrom(component: anytype) anyerror!Widget {
    const ComponentType = @TypeOf(component);
    if (ComponentType == Widget) return component;

    if (component.dataWrappers.widget != null) {
        return error.ComponentAlreadyHasWidget;
    }

    // Unless it is already a pointer, we clone the component so that
    // it can be referenced by the Widget we're gonna create.
    var cp = if (comptime std.meta.trait.isSingleItemPtr(ComponentType)) component else blk: {
        var copy = try lasting_allocator.create(ComponentType);
        copy.* = component;
        break :blk copy;
    };

    // Udate things like data wrappers, this happens once, at initialization,
    // after that the component isn't moved in memory anymore
    cp.pointerMoved();

    const Dereferenced = DereferencedType(ComponentType);
    return Widget{
        .data = cp,
        .class = &Dereferenced.WidgetClass,
        .name = &cp.dataWrappers.name,
        .alignX = &cp.dataWrappers.alignX,
        .alignY = &cp.dataWrappers.alignY,
        .allocator = if (comptime std.meta.trait.isSingleItemPtr(ComponentType)) null else lasting_allocator,
    };
}

pub fn isErrorUnion(comptime T: type) bool {
    return switch (@typeInfo(T)) {
        .ErrorUnion => true,
        else => false,
    };
}

pub fn convertTupleToWidgets(childrens: anytype) anyerror!std.ArrayList(Widget) {
    const fields = std.meta.fields(@TypeOf(childrens));
    var list = std.ArrayList(Widget).init(lasting_allocator);
    inline for (fields) |field| {
        const element = @field(childrens, field.name);
        const child =
            if (comptime isErrorUnion(@TypeOf(element))) // if it is an error union, unwrap it
            try element
        else
            element;

        const ComponentType = @import("internal.zig").DereferencedType(@TypeOf(child));
        const widget = try @import("internal.zig").genericWidgetFrom(child);
        const slot = try list.addOne();
        slot.* = widget;

        if (ComponentType != Widget) {
            widget.as(ComponentType).dataWrappers.widget = slot;
        }
    }

    return list;
}

// pub fn Property(comptime T: type, comptime name: []const u8) type {
// Depends on #6709
//     return struct {

//     };
// }

// Events
pub const RedrawError = error{MissingPeer};

/// Convenience function for creating widgets
pub fn Events(comptime T: type) type {
    return struct {
        /// Blocked on https://github.com/ziglang/zig/issues/12325
        //pub const Callback = *const fn (widget: *T) anyerror!void;
        //pub const DrawCallback = *const fn (widget: *T, ctx: *backend.Canvas.DrawContext) anyerror!void;
        //pub const ButtonCallback = *const fn (widget: *T, button: MouseButton, pressed: bool, x: i32, y: i32) anyerror!void;
        //pub const MouseMoveCallback = *const fn (widget: *T, x: i32, y: i32) anyerror!void;
        //pub const ScrollCallback = *const fn (widget: *T, dx: f32, dy: f32) anyerror!void;
        //pub const ResizeCallback = *const fn (widget: *T, size: Size) anyerror!void;
        //pub const KeyTypeCallback = *const fn (widget: *T, key: []const u8) anyerror!void;
        //pub const KeyPressCallback = *const fn (widget: *T, keycode: u16) anyerror!void;

        // Temporary workaround: use *anyopaque
        pub const Callback = *const fn (widget: *anyopaque) anyerror!void;
        pub const DrawCallback = *const fn (widget: *anyopaque, ctx: *backend.Canvas.DrawContext) anyerror!void;
        pub const ButtonCallback = *const fn (widget: *anyopaque, button: MouseButton, pressed: bool, x: i32, y: i32) anyerror!void;
        pub const MouseMoveCallback = *const fn (widget: *anyopaque, x: i32, y: i32) anyerror!void;
        pub const ScrollCallback = *const fn (widget: *anyopaque, dx: f32, dy: f32) anyerror!void;
        pub const ResizeCallback = *const fn (widget: *anyopaque, size: Size) anyerror!void;
        pub const KeyTypeCallback = *const fn (widget: *anyopaque, key: []const u8) anyerror!void;
        pub const KeyPressCallback = *const fn (widget: *anyopaque, keycode: u16) anyerror!void;
        const HandlerList = std.ArrayList(Callback);
        const DrawHandlerList = std.ArrayList(DrawCallback);
        const ButtonHandlerList = std.ArrayList(ButtonCallback);
        const MouseMoveHandlerList = std.ArrayList(MouseMoveCallback);
        const ScrollHandlerList = std.ArrayList(ScrollCallback);
        const ResizeHandlerList = std.ArrayList(ResizeCallback);
        const KeyTypeHandlerList = std.ArrayList(KeyTypeCallback);
        const KeyPressHandlerList = std.ArrayList(KeyPressCallback);

        pub const Handlers = struct {
            clickHandlers: HandlerList,
            drawHandlers: DrawHandlerList,
            buttonHandlers: ButtonHandlerList,
            mouseMoveHandlers: MouseMoveHandlerList,
            scrollHandlers: ScrollHandlerList,
            resizeHandlers: ResizeHandlerList,
            keyTypeHandlers: KeyTypeHandlerList,
            keyPressHandlers: KeyPressHandlerList,
            userdata: ?*anyopaque = null,
        };

        pub fn init_events(self: T) T {
            var obj = self;
            obj.handlers = .{
                .clickHandlers = HandlerList.init(lasting_allocator),
                .drawHandlers = DrawHandlerList.init(lasting_allocator),
                .buttonHandlers = ButtonHandlerList.init(lasting_allocator),
                .mouseMoveHandlers = MouseMoveHandlerList.init(lasting_allocator),
                .scrollHandlers = ScrollHandlerList.init(lasting_allocator),
                .resizeHandlers = ResizeHandlerList.init(lasting_allocator),
                .keyTypeHandlers = KeyTypeHandlerList.init(lasting_allocator),
                .keyPressHandlers = KeyPressHandlerList.init(lasting_allocator),
            };
            return obj;
        }

        fn errorHandler(err: anyerror) callconv(.Unspecified) void {
            std.log.err("{s}", .{@errorName(err)});
            var streamBuf: [16384]u8 = undefined;
            var stream = std.io.fixedBufferStream(&streamBuf);
            var writer = stream.writer();
            writer.print("Internal error: {s}.\n", .{@errorName(err)}) catch {};
            if (@errorReturnTrace()) |trace| {
                std.debug.dumpStackTrace(trace.*);
                if (comptime std.io.is_async or @import("builtin").target.isWasm()) {
                    // can't use writeStackTrace as it is async but errorHandler should not be async!
                    // also can't use writeStackTrace when using WebAssembly
                } else {
                    if (std.debug.getSelfDebugInfo()) |debug_info| {
                        var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
                        defer arena.deinit();
                        std.debug.writeStackTrace(trace.*, writer, arena.allocator(), debug_info, .no_color) catch {};
                    } else |_| {}
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

        fn drawHandler(ctx: *backend.Canvas.DrawContext, data: usize) void {
            const self = @intToPtr(*T, data);
            for (self.handlers.drawHandlers.items) |func| {
                func(self, ctx) catch |err| errorHandler(err);
            }
        }

        fn buttonHandler(button: MouseButton, pressed: bool, x: i32, y: i32, data: usize) void {
            const self = @intToPtr(*T, data);
            for (self.handlers.buttonHandlers.items) |func| {
                func(self, button, pressed, x, y) catch |err| errorHandler(err);
            }
        }

        fn mouseMovedHandler(x: i32, y: i32, data: usize) void {
            const self = @intToPtr(*T, data);
            for (self.handlers.mouseMoveHandlers.items) |func| {
                func(self, x, y) catch |err| errorHandler(err);
            }
        }

        fn keyTypeHandler(str: []const u8, data: usize) void {
            const self = @intToPtr(*T, data);
            for (self.handlers.keyTypeHandlers.items) |func| {
                func(self, str) catch |err| errorHandler(err);
            }
        }

        fn keyPressHandler(keycode: u16, data: usize) void {
            const self = @intToPtr(*T, data);
            for (self.handlers.keyPressHandlers.items) |func| {
                func(self, keycode) catch |err| errorHandler(err);
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
            const size = Size{ .width = width, .height = height };
            for (self.handlers.resizeHandlers.items) |func| {
                func(self, size) catch |err| errorHandler(err);
            }
        }

        /// When the value is changed in the opacity data wrapper
        fn opacityChanged(newValue: f32, userdata: usize) void {
            const widget = @intToPtr(*T, userdata);
            if (widget.peer) |*peer| {
                peer.setOpacity(newValue);
            }
        }

        pub fn show_events(self: *T) !void {
            self.peer.?.setUserData(self);
            try self.peer.?.setCallback(.Click, clickHandler);
            try self.peer.?.setCallback(.Draw, drawHandler);
            try self.peer.?.setCallback(.MouseButton, buttonHandler);
            try self.peer.?.setCallback(.MouseMotion, mouseMovedHandler);
            try self.peer.?.setCallback(.Scroll, scrollHandler);
            try self.peer.?.setCallback(.Resize, resizeHandler);
            try self.peer.?.setCallback(.KeyType, keyTypeHandler);
            try self.peer.?.setCallback(.KeyPress, keyPressHandler);

            _ = try self.dataWrappers.opacity.addChangeListener(.{ .function = opacityChanged, .userdata = @ptrToInt(self) });
            opacityChanged(self.dataWrappers.opacity.get(), @ptrToInt(self)); // call it so it's updated
        }

        pub fn addClickHandler(self: *T, handler: anytype) !void {
            try self.handlers.clickHandlers.append(@ptrCast(Callback, handler));
        }

        pub fn addDrawHandler(self: *T, handler: anytype) !T {
            try self.handlers.drawHandlers.append(@ptrCast(DrawCallback, handler));
            return self.*;
        }

        pub fn addMouseButtonHandler(self: *T, handler: anytype) !void {
            try self.handlers.buttonHandlers.append(@ptrCast(ButtonCallback, handler));
        }

        pub fn addMouseMotionHandler(self: *T, handler: anytype) !void {
            try self.handlers.mouseMoveHandlers.append(@ptrCast(MouseMoveCallback, handler));
        }

        pub fn addScrollHandler(self: *T, handler: anytype) !void {
            try self.handlers.scrollHandlers.append(@ptrCast(ScrollCallback, handler));
        }

        pub fn addResizeHandler(self: *T, handler: anytype) !void {
            try self.handlers.resizeHandlers.append(@ptrCast(ResizeCallback, handler));
        }

        pub fn addKeyTypeHandler(self: *T, handler: anytype) !void {
            try self.handlers.keyTypeHandlers.append(@ptrCast(KeyTypeCallback, handler));
        }

        pub fn addKeyPressHandler(self: *T, handler: anytype) !void {
            try self.handlers.keyPressHandlers.append(@ptrCast(KeyPressCallback, handler));
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
