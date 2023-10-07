const root = @import("root");
const builtin = @import("builtin");
const std = @import("std");
const backend = @import("backend.zig");
const style = @import("style.zig");
const dataStructures = @import("data.zig");
const Widget = @import("widget.zig").Widget;
const Class = @import("widget.zig").Class;
const Size = dataStructures.Size;
const Atom = dataStructures.Atom;
const Container = @import("containers.zig").Container;
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

        pub const WidgetData = struct {
            handlers: T.Handlers = undefined,
            atoms: T.Atoms = .{},
        };
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
            .getParentFn = widget_getParent,
            .isDisplayedFn = isDisplayedFn,
        };

        pub const Atoms = struct {
            opacity: Atom(f32) = Atom(f32).of(1.0),
            displayed: Atom(bool) = Atom(bool).of(true),
            name: Atom(?[]const u8) = Atom(?[]const u8).of(null),

            /// The widget representing this component
            widget: ?*Widget = null,
        };

        pub const Config = GenerateConfigStruct(T);

        pub fn showWidget(widget: *Widget) anyerror!void {
            const component = widget.as(T);
            try component.show();
            widget.peer = component.peer.?.peer;

            // if the widget wants to do some operations on showWidget
            if (@hasDecl(T, "_showWidget")) {
                try T._showWidget(widget, component);
            }
        }

        pub fn setWidgetFn(widget: *Widget) void {
            const component = widget.as(T);
            component.widget_data.atoms.widget = widget;
        }

        pub fn isDisplayedFn(widget: *const Widget) bool {
            const component = widget.as(T);
            return component.widget_data.atoms.displayed.get();
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

            self.widget_data.atoms.widget = null;
            self.widget_data.atoms.opacity.deinit();

            self.widget_data.handlers.clickHandlers.deinit();
            self.widget_data.handlers.drawHandlers.deinit();
            self.widget_data.handlers.buttonHandlers.deinit();
            self.widget_data.handlers.mouseMoveHandlers.deinit();
            self.widget_data.handlers.scrollHandlers.deinit();
            self.widget_data.handlers.resizeHandlers.deinit();
            self.widget_data.handlers.keyTypeHandlers.deinit();

            // TODO: deinit all datawrapper properties
            if (self.peer) |peer| peer.deinit();
        }

        pub fn pointerMoved(self: *T) void {
            self.widget_data.atoms.opacity.updateBinders();
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
            return @as(u32, @intCast(self.peer.?.getWidth()));
        }

        pub fn getHeight(self: *T) u32 {
            if (self.peer == null) return 0;
            return @as(u32, @intCast(self.peer.?.getHeight()));
        }

        pub fn asWidget(self: *T) anyerror!Widget {
            return try genericWidgetFrom(self);
        }

        // TODO: consider using something like https://github.com/MasterQ32/any-pointer for userdata
        // to get some safety
        pub fn setUserdata(self: *T, userdata: ?*anyopaque) void {
            self.widget_data.handlers.userdata = userdata;
        }

        pub fn getUserdata(self: *T, comptime U: type) U {
            return @as(U, @ptrCast(self.widget_data.handlers.userdata));
        }

        // Properties
        fn TypeOfProperty(comptime name: []const u8) type {
            if (@hasField(T, name)) {
                return @TypeOf(@field(@as(T, undefined), name)).ValueType;
            } else if (@hasField(Atoms, name)) {
                return @TypeOf(@field(@as(Atoms, undefined), name)).ValueType;
            } else {
                comptime {
                    var compileError: []const u8 = "No such property: " ++ name;
                    if (T == Container) {
                        compileError = compileError ++ ", did you mean to use getChild() ?";
                    }
                    @compileError(compileError);
                }
            }
        }

        // This method temporarily returns the component for chaining methods
        // This will be reconsidered later and thus might be removed.
        pub fn set(self: *T, comptime name: []const u8, value: TypeOfProperty(name)) void {
            if (@hasField(Atoms, name)) {
                @field(self.widget_data.atoms, name).set(value);
            } else {
                @field(self, name).set(value);
            }
        }

        pub fn get(self: *T, comptime name: []const u8) TypeOfProperty(name) {
            if (@hasField(Atoms, name)) {
                return @field(self.widget_data.atoms, name).get();
            } else {
                return @field(self, name).get();
            }
        }

        /// Bind the given property to argument
        pub fn bind(immutable_self: *const T, comptime name: []const u8, other: *Atom(TypeOfProperty(name))) T {
            // TODO: use another system for binding components
            // This is DANGEROUSLY unsafe (and unoptimized)
            const self = @as(*T, @ptrFromInt(@intFromPtr(immutable_self)));

            if (@hasField(Atoms, name)) {
                @field(self.widget_data.atoms, name).bind(other);
            } else {
                @field(self, name).bind(other);
            }
            self.set(name, other.get());
            return immutable_self.*;
        }

        pub fn getName(self: *T) ?[]const u8 {
            return self.widget_data.atoms.name;
        }

        pub fn setName(self: *T, name: ?[]const u8) void {
            self.widget_data.atoms.name.set(name);
        }

        pub fn getWidget(self: *T) ?*Widget {
            return self.widget_data.atoms.widget;
        }

        // Returns the parent of the current widget
        pub fn getParent(self: *T) ?*Widget {
            if (self.widget_data.atoms.widget) |widget| {
                if (widget.parent) |parent| {
                    return parent;
                }
            }
            return null;
        }

        fn widget_getParent(widget: *const Widget) ?*Widget {
            const component = widget.as(T);
            return component.getParent();
        }

        /// Go up the widget tree until we find the root (which is the component
        /// put with window.set()
        /// Returns null if the component is unparented.
        pub fn getRoot(self: *T) ?*Widget {
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
        const default_draw_value: ?T.DrawCallback = null;
        config_fields = config_fields ++ &[1]std.builtin.Type.StructField{.{
            .name = "onclick",
            .type = ?T.Callback,
            .default_value = @as(?*const anyopaque, @ptrCast(&default_value)),
            .is_comptime = false,
            .alignment = @alignOf(?T.Callback),
        }};
        config_fields = config_fields ++ &[1]std.builtin.Type.StructField{.{
            .name = "ondraw",
            .type = ?T.DrawCallback,
            .default_value = @as(?*const anyopaque, @ptrCast(&default_draw_value)),
            .is_comptime = false,
            .alignment = @alignOf(?T.DrawCallback),
        }};

        const t = @Type(.{ .Struct = .{
            .layout = .Auto,
            .backing_integer = null,
            .fields = config_fields,
            .decls = &.{},
            .is_tuple = false,
        } });
        return t;
    }
}

fn iterateFields(comptime config_fields: *[]const std.builtin.Type.StructField, comptime T: type) void {
    for (std.meta.fields(T)) |field| {
        const FieldType = field.type;
        if (dataStructures.isAtom(FieldType)) {
            const default_value = if (field.default_value) |default| @as(*const FieldType, @ptrCast(@alignCast(default))).getUnsafe() else null;
            const has_default_value = field.default_value != null;

            config_fields.* = config_fields.* ++ &[1]std.builtin.Type.StructField{.{
                .name = field.name,
                .type = FieldType.ValueType,
                .default_value = if (has_default_value) @as(?*const anyopaque, @ptrCast(@alignCast(&default_value))) else null,
                .is_comptime = false,
                .alignment = @alignOf(FieldType.ValueType),
            }};
        } else if (comptime std.meta.trait.is(.Struct)(FieldType)) {
            iterateFields(config_fields, FieldType);
        }
    }
}

/// target is a pointer to a component
/// config is a config struct generated by GenerateConfigStruct(T)
pub fn applyConfigStruct(target: anytype, config: GenerateConfigStruct(std.meta.Child(@TypeOf(target)))) void {
    std.debug.assert(std.meta.trait.isPtrTo(.Struct)(@TypeOf(target)));
    iterateApplyFields(std.meta.Child(@TypeOf(target)), target, config);

    if (config.onclick) |onclick| {
        target.addClickHandler(onclick) catch unreachable; // TODO: improve
    }
    if (config.ondraw) |ondraw| {
        target.addDrawHandler(ondraw) catch unreachable; // TODO: improve
    }
}

fn iterateApplyFields(comptime T: type, target: anytype, config: GenerateConfigStruct(T)) void {
    inline for (std.meta.fields(std.meta.Child(@TypeOf(target)))) |field| {
        const FieldType = field.type;
        if (comptime dataStructures.isAtom(FieldType)) {
            const name = field.name;
            @field(target, field.name).set(
                @field(config, name),
            );
        } else if (comptime std.meta.trait.is(.Struct)(FieldType)) {
            iterateApplyFields(T, &@field(target, field.name), config);
        }
    }
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
/// This method will set atoms.widget field and can only be called once.
pub fn genericWidgetFrom(component: anytype) anyerror!Widget {
    const ComponentType = @TypeOf(component);
    if (ComponentType == Widget) return component;

    if (component.widget_data.atoms.widget != null) {
        return error.ComponentAlreadyHasWidget;
    }

    // Unless it is already a pointer, we clone the component so that
    // it can be referenced by the Widget we're gonna create.
    var cp = if (comptime std.meta.trait.isSingleItemPtr(ComponentType)) component else blk: {
        var copy = try lasting_allocator.create(ComponentType);
        copy.* = component;
        break :blk copy;
    };

    // Update things like data wrappers, this happens once, at initialization,
    // after that the component isn't moved in memory anymore
    cp.pointerMoved();

    const Dereferenced = DereferencedType(ComponentType);
    return Widget{
        .data = cp,
        .class = &Dereferenced.WidgetClass,
        .name = &cp.widget_data.atoms.name,
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
            widget.as(ComponentType).widget_data.atoms.widget = slot;
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
        pub const PropertyChangeCallback = *const fn (widget: *anyopaque, property_name: []const u8, new_value: *const anyopaque) anyerror!void;
        const HandlerList = std.ArrayList(Callback);
        const DrawHandlerList = std.ArrayList(DrawCallback);
        const ButtonHandlerList = std.ArrayList(ButtonCallback);
        const MouseMoveHandlerList = std.ArrayList(MouseMoveCallback);
        const ScrollHandlerList = std.ArrayList(ScrollCallback);
        const ResizeHandlerList = std.ArrayList(ResizeCallback);
        const KeyTypeHandlerList = std.ArrayList(KeyTypeCallback);
        const KeyPressHandlerList = std.ArrayList(KeyPressCallback);
        const PropertyChangeHandlerList = std.ArrayList(PropertyChangeCallback);

        pub const Handlers = struct {
            clickHandlers: HandlerList,
            drawHandlers: DrawHandlerList,
            buttonHandlers: ButtonHandlerList,
            mouseMoveHandlers: MouseMoveHandlerList,
            scrollHandlers: ScrollHandlerList,
            resizeHandlers: ResizeHandlerList,
            keyTypeHandlers: KeyTypeHandlerList,
            keyPressHandlers: KeyPressHandlerList,
            propertyChangeHandlers: PropertyChangeHandlerList,
            userdata: ?*anyopaque = null,
        };

        pub fn init_events(self: T) T {
            var obj = self;
            obj.widget_data.handlers = .{
                .clickHandlers = HandlerList.init(lasting_allocator),
                .drawHandlers = DrawHandlerList.init(lasting_allocator),
                .buttonHandlers = ButtonHandlerList.init(lasting_allocator),
                .mouseMoveHandlers = MouseMoveHandlerList.init(lasting_allocator),
                .scrollHandlers = ScrollHandlerList.init(lasting_allocator),
                .resizeHandlers = ResizeHandlerList.init(lasting_allocator),
                .keyTypeHandlers = KeyTypeHandlerList.init(lasting_allocator),
                .keyPressHandlers = KeyPressHandlerList.init(lasting_allocator),
                .propertyChangeHandlers = PropertyChangeHandlerList.init(lasting_allocator),
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
            const self = @as(*T, @ptrFromInt(data));
            for (self.widget_data.handlers.clickHandlers.items) |func| {
                func(self) catch |err| errorHandler(err);
            }
        }

        fn drawHandler(ctx: *backend.Canvas.DrawContext, data: usize) void {
            const self = @as(*T, @ptrFromInt(data));
            for (self.widget_data.handlers.drawHandlers.items) |func| {
                func(self, ctx) catch |err| errorHandler(err);
            }
        }

        fn buttonHandler(button: MouseButton, pressed: bool, x: i32, y: i32, data: usize) void {
            const self = @as(*T, @ptrFromInt(data));
            for (self.widget_data.handlers.buttonHandlers.items) |func| {
                func(self, button, pressed, x, y) catch |err| errorHandler(err);
            }
        }

        fn mouseMovedHandler(x: i32, y: i32, data: usize) void {
            const self = @as(*T, @ptrFromInt(data));
            for (self.widget_data.handlers.mouseMoveHandlers.items) |func| {
                func(self, x, y) catch |err| errorHandler(err);
            }
        }

        fn keyTypeHandler(str: []const u8, data: usize) void {
            const self = @as(*T, @ptrFromInt(data));
            for (self.widget_data.handlers.keyTypeHandlers.items) |func| {
                func(self, str) catch |err| errorHandler(err);
            }
        }

        fn keyPressHandler(keycode: u16, data: usize) void {
            const self = @as(*T, @ptrFromInt(data));
            for (self.widget_data.handlers.keyPressHandlers.items) |func| {
                func(self, keycode) catch |err| errorHandler(err);
            }
        }

        fn scrollHandler(dx: f32, dy: f32, data: usize) void {
            const self = @as(*T, @ptrFromInt(data));
            for (self.widget_data.handlers.scrollHandlers.items) |func| {
                func(self, dx, dy) catch |err| errorHandler(err);
            }
        }

        fn resizeHandler(width: u32, height: u32, data: usize) void {
            const self = @as(*T, @ptrFromInt(data));
            const size = Size{ .width = width, .height = height };
            for (self.widget_data.handlers.resizeHandlers.items) |func| {
                func(self, size) catch |err| errorHandler(err);
            }
        }

        fn propertyChangeHandler(name: []const u8, value: *const anyopaque, data: usize) void {
            const self = @as(*T, @ptrFromInt(data));
            for (self.widget_data.handlers.propertyChangeHandlers.items) |func| {
                func(self, name, value) catch |err| errorHandler(err);
            }
        }

        /// When the value is changed in the opacity data wrapper
        fn opacityChanged(newValue: f32, userdata: usize) void {
            const widget = @as(*T, @ptrFromInt(userdata));
            std.log.info("opaccity changed to {d}", .{newValue});
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
            try self.peer.?.setCallback(.PropertyChange, propertyChangeHandler);

            _ = try self.widget_data.atoms.opacity.addChangeListener(.{ .function = opacityChanged, .userdata = @intFromPtr(self) });
            opacityChanged(self.widget_data.atoms.opacity.get(), @intFromPtr(self)); // call it so it's updated
        }

        pub fn addClickHandler(self: *T, handler: anytype) !void {
            try self.widget_data.handlers.clickHandlers.append(@as(Callback, @ptrCast(handler)));
        }

        pub fn addDrawHandler(self: *T, handler: anytype) !void {
            try self.widget_data.handlers.drawHandlers.append(@as(DrawCallback, @ptrCast(handler)));
        }

        pub fn addMouseButtonHandler(self: *T, handler: anytype) !void {
            try self.widget_data.handlers.buttonHandlers.append(@as(ButtonCallback, @ptrCast(handler)));
        }

        pub fn addMouseMotionHandler(self: *T, handler: anytype) !void {
            try self.widget_data.handlers.mouseMoveHandlers.append(@as(MouseMoveCallback, @ptrCast(handler)));
        }

        pub fn addScrollHandler(self: *T, handler: anytype) !void {
            try self.widget_data.handlers.scrollHandlers.append(@as(ScrollCallback, @ptrCast(handler)));
        }

        pub fn addResizeHandler(self: *T, handler: anytype) !void {
            try self.widget_data.handlers.resizeHandlers.append(@as(ResizeCallback, @ptrCast(handler)));
        }

        pub fn addKeyTypeHandler(self: *T, handler: anytype) !void {
            try self.widget_data.handlers.keyTypeHandlers.append(@as(KeyTypeCallback, @ptrCast(handler)));
        }

        pub fn addKeyPressHandler(self: *T, handler: anytype) !void {
            try self.widget_data.handlers.keyPressHandlers.append(@as(KeyPressCallback, @ptrCast(handler)));
        }

        /// This shouldn't be used by user applications directly.
        /// Instead set a change listener to the corresponding data wrapper.
        pub fn addPropertyChangeHandler(self: *T, handler: anytype) !void {
            try self.widget_data.handlers.propertyChangeHandlers.append(@as(PropertyChangeCallback, @ptrCast(handler)));
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
