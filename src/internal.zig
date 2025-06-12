//! Internal namespace for Capy

const root = @import("root");
const builtin = @import("builtin");
const std = @import("std");
const backend = @import("backend.zig");
// const style = @import("style.zig");
const dataStructures = @import("data.zig");
const Widget = @import("widget.zig").Widget;
const Class = @import("widget.zig").Class;
const Size = dataStructures.Size;
const Atom = dataStructures.Atom;
const Container = @import("containers.zig").Container;
const Layout = @import("containers.zig").Layout;
const MouseButton = @import("backends/shared.zig").MouseButton;
const trait = @import("trait.zig");
const AnimationController = @import("AnimationController.zig");

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
/// or by setting the `capy_allocator` field which will also apply as lasting allocator.
pub const scratch_allocator = if (@hasDecl(root, "capy_scratch_allocator")) root.capy_scratch_allocator else default_allocator;

/// Allocator used for bigger, longer-lived but rare allocations (example: widgets).
/// You can change this by setting the `capy_lasting_allocator` field in your main file
/// or by setting the `capy_allocator` field which will also apply as scratch allocator.
pub const lasting_allocator = if (@hasDecl(root, "capy_lasting_allocator")) root.capy_lasting_allocator else default_allocator;

/// Convenience function for creating widgets
pub fn All(comptime T: type) type {
    return struct {
        pub usingnamespace Events(T);
        pub usingnamespace Widgeting(T);

        pub const WidgetData = struct {
            handlers: T.Handlers = undefined,
            atoms: T.Atoms = .{},
            refcount: std.atomic.Value(u32) = std.atomic.Value(u32).init(0),
            userdata: std.StringHashMapUnmanaged(*anyopaque) = std.StringHashMapUnmanaged(*anyopaque).empty,

            /// The widget representing this component
            /// It is initialised in alloc()
            widget: Widget = undefined,
        };
    };
}

/// Convenience function for creating widgets
pub fn Widgeting(comptime T: type) type {
    return struct {
        pub const WidgetClass = Class{
            .typeName = @typeName(T),

            .showFn = showWidget,
            .deinitFn = deinitWidget,
            .preferredSizeFn = getPreferredSizeWidget,

            .getParentFn = widget_getParent,
            .isDisplayedFn = isDisplayedFn,

            .ref_fn = @ptrCast(&ref),
            .unref_fn = @ptrCast(&unref),
        };

        pub const Atoms = struct {
            opacity: Atom(f32) = Atom(f32).of(1.0),
            displayed: Atom(bool) = Atom(bool).of(true),
            name: Atom(?[]const u8) = Atom(?[]const u8).of(null),
            animation_controller: Atom(*AnimationController) = Atom(*AnimationController).of(AnimationController.null_animation_controller),
        };

        pub const Config = GenerateConfigStruct(T);

        /// Allocates an instance of the component.
        ///
        /// By default, all components are allocated using lasting_allocator, why is it this way and not
        /// with a different allocator for each component? It's because it would cause a lot of trouble if a
        /// was allocated with a different allocator than its children. Enforcing one single allocator
        /// prevents those kind of situations.
        ///
        /// It is important to note that the created component will be counted as having NO REFERENCES.
        /// This means that you must ref() it if you wish to hold a reference to it in a variable instead
        /// instead of directly adding it to a component or a window.
        pub fn alloc(config: Config) *T {
            const instance = lasting_allocator.create(T) catch @panic("out of memory");
            const type_info = @typeInfo(@TypeOf(T.init)).@"fn";
            const return_type = type_info.return_type.?;
            if (comptime type_info.params.len != 1) {
                @panic("no");
            }
            if (comptime isErrorUnion(return_type)) {
                instance.* = T.init(config) catch @panic("error"); // TODO: better? maybe change return type by making alloc() return an error union?
            } else {
                instance.* = T.init(config);
            }
            instance.widget_data.widget = genericWidgetFrom(instance);
            return instance;
        }

        /// Increase the number of references to this component.
        pub fn ref(self: *T) void {
            _ = self.widget_data.refcount.fetchAdd(1, .monotonic);
        }

        /// Decrease the number of references to this component, that is tell Capy
        /// that you stopped using a pointer to the component.
        /// If this number decreases to 0, the function will also deinitialize the component.
        /// This is why this function must only be called after you stopped using a pointer
        /// to the component, as using the pointer after unref() may cause a Use-After-Free.
        pub fn unref(self: *T) void {
            std.debug.assert(self.widget_data.refcount.load(.monotonic) != 0);
            if (self.widget_data.refcount.fetchSub(1, .acq_rel) == 1) {
                self.deinit();
            }
        }

        pub fn showWidget(widget: *Widget) anyerror!void {
            const component = widget.as(T);
            try component.show();
            widget.peer = component.peer.?.peer;

            // if the widget wants to do some operations on showWidget
            if (@hasDecl(T, "_showWidget")) {
                try T._showWidget(widget, component);
            }
        }

        pub fn isDisplayedFn(widget: *const Widget) bool {
            const component = widget.as(T);
            return component.widget_data.atoms.displayed.get();
        }

        pub fn deinitWidget(widget: *Widget) void {
            const component = widget.as(T);
            component.deinit();
        }

        fn deinit(self: *T) void {
            if (@hasDecl(T, "_deinit")) {
                self._deinit();
            }

            self.widget_data.userdata.deinit(lasting_allocator);
            self.widget_data.handlers.clickHandlers.deinit();
            self.widget_data.handlers.drawHandlers.deinit();
            self.widget_data.handlers.buttonHandlers.deinit();
            self.widget_data.handlers.mouseMoveHandlers.deinit();
            self.widget_data.handlers.scrollHandlers.deinit();
            self.widget_data.handlers.resizeHandlers.deinit();
            self.widget_data.handlers.keyTypeHandlers.deinit();
            self.widget_data.handlers.keyPressHandlers.deinit();
            self.widget_data.handlers.propertyChangeHandlers.deinit();

            // deinit all atom properties
            deinitAtoms(self);
            if (self.peer) |peer| peer.deinit();

            lasting_allocator.destroy(self);
        }

        pub fn getPreferredSizeWidget(widget: *const Widget, available: Size) Size {
            const component = widget.as(T);
            return component.getPreferredSize(available);
        }

        /// Get the X position relative to this component's parent
        pub fn getX(self: *T) u32 {
            if (self.peer) |peer| {
                return @intCast(peer.getX());
            } else {
                return 0;
            }
        }

        /// Get the Y position relative to this component's parent
        pub fn getY(self: *T) u32 {
            if (self.peer) |peer| {
                return @intCast(peer.getY());
            } else {
                return 0;
            }
        }

        pub fn getSize(self: *T) Size {
            return Size.init(@floatFromInt(self.getWidth()), @floatFromInt(self.getHeight()));
        }

        pub fn getWidth(self: *T) u32 {
            if (self.peer) |peer| {
                return @intCast(peer.getWidth());
            } else {
                return 0;
            }
        }

        pub fn getHeight(self: *T) u32 {
            if (self.peer) |peer| {
                return @intCast(peer.getHeight());
            } else {
                return 0;
            }
        }

        pub fn asWidget(self: *T) *Widget {
            return &self.widget_data.widget;
        }

        /// Add a userdata to the component. All the component's children can access this userdata
        /// as long as they don't override it themselves.
        pub fn addUserdata(self: *T, comptime U: type, userdata: *U) *T {
            const key: []const u8 = @typeName(U);
            self.widget_data.userdata.put(lasting_allocator, key, userdata) catch @panic("OOM");
            return self;
        }

        /// Get userdata attached to this component or to a component's ancestor.
        pub fn getUserdata(self: *T, comptime U: type) ?*U {
            const key: []const u8 = @typeName(U);
            if (self.widget_data.userdata.get(key)) |value| {
                return @ptrCast(@alignCast(value));
            } else {
                var parent: ?*Widget = self.getParent();
                while (parent != null) : (parent = parent.?.getParent()) {
                    if (parent.?.userdata.get(key)) |value| {
                        return @ptrCast(@alignCast(value));
                    }
                }
                return null;
            }
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
        pub fn bind(self: *T, comptime name: []const u8, other: *Atom(TypeOfProperty(name))) *T {
            if (@hasField(Atoms, name)) {
                @field(self.widget_data.atoms, name).bind(other);
            } else {
                @field(self, name).bind(other);
            }
            self.set(name, other.get());
            return self;
        }

        pub fn getName(self: *T) ?[]const u8 {
            return self.widget_data.atoms.name.get();
        }

        pub fn setName(self: *T, name: ?[]const u8) void {
            self.widget_data.atoms.name.set(name);
        }

        // Returns the parent of the current widget
        pub fn getParent(self: *T) ?*Widget {
            const widget = self.widget_data.widget;
            return widget.parent;
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
                const ancestor = parent.getParent();
                if (ancestor) |newParent| {
                    parent = newParent;
                } else {
                    break;
                }
            }

            return parent;
        }

        pub fn getAnimationController(self: *T) *AnimationController {
            return self.widget_data.atoms.animation_controller.get();
        }

        // /// Clone the component but with the peer set to null
        pub fn clone(self: *T) !*T {
            _ = self;
            @panic("TODO");
            // if (@hasDecl(T, "cloneImpl")) {
            //     return try self.cloneImpl();
            // }
            // // Clone properties only
            // var config: GenerateConfigStruct(T) = undefined;
            // inline for (comptime std.meta.fieldNames(GenerateConfigStruct(T))) |property_name| {
            //     if (comptime !std.mem.eql(u8, property_name, "onclick") and !std.mem.eql(u8, property_name, "ondraw")) {
            //         @field(config, property_name) = self.get(property_name);
            //     }
            // }

            // const cloned = T.alloc(config);
            // return cloned;
        }

        pub fn widget_clone(widget: *const Widget) anyerror!*Widget {
            const component = widget.as(T);
            const cloned = try component.clone();
            return cloned.asWidget();
        }
    };
}

/// Generate a config struct that allows with all the properties of the given type
pub fn GenerateConfigStruct(comptime T: type) type {
    // TODO: .onclick = &.{ handlerOne, handlerTwo }, for other event handlers
    comptime {
        @setEvalBranchQuota(10000);
        var config_fields: []const std.builtin.Type.StructField = &.{};
        iterateFields(&config_fields, T);

        const default_value: ?T.Callback = null;
        const default_draw_value: ?T.DrawCallback = null;
        config_fields = config_fields ++ &[1]std.builtin.Type.StructField{.{
            .name = "onclick",
            .type = ?T.Callback,
            .default_value_ptr = @as(?*const anyopaque, @ptrCast(&default_value)),
            .is_comptime = false,
            .alignment = @alignOf(?T.Callback),
        }};
        config_fields = config_fields ++ &[1]std.builtin.Type.StructField{.{
            .name = "ondraw",
            .type = ?T.DrawCallback,
            .default_value_ptr = @as(?*const anyopaque, @ptrCast(&default_draw_value)),
            .is_comptime = false,
            .alignment = @alignOf(?T.DrawCallback),
        }};

        const t = @Type(.{ .@"struct" = .{
            .layout = .auto,
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
            const default_value = if (field.defaultValue()) |default| default.getUnsafe() else null;
            const has_default_value = field.defaultValue() != null;

            config_fields.* = config_fields.* ++ &[1]std.builtin.Type.StructField{.{
                .name = field.name,
                .type = FieldType.ValueType,
                .default_value_ptr = if (has_default_value) @as(?*const anyopaque, @ptrCast(@alignCast(&default_value))) else null,
                .is_comptime = false,
                .alignment = @alignOf(FieldType.ValueType),
            }};
        } else if (dataStructures.isListAtom(FieldType)) {
            // const default_value = if (field.default_value) |default| @as(*const FieldType, @ptrCast(@alignCast(default))).getUnsafe() else null;
            const default_value = null;
            // const has_default_value = field.default_value != null;
            const has_default_value = false;

            config_fields.* = config_fields.* ++ &[1]std.builtin.Type.StructField{.{
                .name = field.name,
                .type = []const FieldType.ValueType,
                .default_value_ptr = if (has_default_value) @as(?*const anyopaque, @ptrCast(@alignCast(&default_value))) else null,
                .is_comptime = false,
                .alignment = @alignOf(FieldType.ValueType),
            }};
        } else if (comptime trait.is(.@"struct")(FieldType)) {
            iterateFields(config_fields, FieldType);
        }
    }
}

// /// target is a pointer to a component
// /// config is a config struct generated by GenerateConfigStruct(T)
pub fn applyConfigStruct(target: anytype, config: GenerateConfigStruct(std.meta.Child(@TypeOf(target)))) void {
    @setEvalBranchQuota(10000);
    comptime std.debug.assert(@typeInfo(std.meta.Child(@TypeOf(target))) == .@"struct");
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
        } else if (comptime dataStructures.isListAtom(FieldType)) {
            const name = field.name;
            const value = @field(config, name);
            for (value) |item| {
                @field(target, field.name).append(item) catch @panic("OOM");
            }
        } else if (comptime trait.is(.@"struct")(FieldType)) {
            iterateApplyFields(T, &@field(target, field.name), config);
        }
    }
}

pub fn deinitAtoms(target: anytype) void {
    comptime std.debug.assert(@typeInfo(std.meta.Child(@TypeOf(target))) == .@"struct");
    iterateDeinitFields(std.meta.Child(@TypeOf(target)), target);
}

fn iterateDeinitFields(comptime T: type, target: anytype) void {
    inline for (std.meta.fields(std.meta.Child(@TypeOf(target)))) |field| {
        const FieldType = field.type;
        if (comptime dataStructures.isAtom(FieldType)) {
            const name = field.name;
            _ = name;
            @field(target, field.name).deinit();
        } else if (comptime trait.is(.@"struct")(FieldType)) {
            iterateDeinitFields(T, &@field(target, field.name));
        }
    }
}

// /// If T is a pointer, return the type it points to, otherwise return T.
// /// Example: DereferencedType(*Button_Impl) = Button_Impl
pub fn DereferencedType(comptime T: type) type {
    return if (comptime trait.isSingleItemPtr(T))
        std.meta.Child(T)
    else
        T;
}

// /// Create a generic Widget struct from the given component.
pub fn genericWidgetFrom(component: anytype) Widget {
    const ComponentType = @TypeOf(component);
    comptime std.debug.assert(ComponentType != Widget and ComponentType != *Widget);

    // Unless it is already a pointer, we clone the component so that
    // it can be referenced by the Widget we're gonna create.
    comptime std.debug.assert(trait.isSingleItemPtr(ComponentType));
    const Dereferenced = DereferencedType(ComponentType);
    return Widget{
        .data = component,
        .class = &Dereferenced.WidgetClass,
        .name = &component.widget_data.atoms.name,
        .animation_controller = &component.widget_data.atoms.animation_controller,
        .userdata = &component.widget_data.userdata,
    };
}

pub fn getWidgetFrom(component: anytype) *Widget {
    if (@TypeOf(component) == *Widget) {
        return component;
    } else {
        return component.asWidget();
    }
}

pub fn isErrorUnion(comptime T: type) bool {
    return switch (@typeInfo(T)) {
        .error_union => true,
        else => false,
    };
}

pub fn convertTupleToWidgets(childrens: anytype) anyerror!std.ArrayList(*Widget) {
    const fields = std.meta.fields(@TypeOf(childrens));
    var list = std.ArrayList(*Widget).init(lasting_allocator);
    inline for (fields) |field| {
        const element = @field(childrens, field.name);
        const child =
            if (comptime isErrorUnion(@TypeOf(element))) // if it is an error union, unwrap it
                try element
            else
                element;

        const widget = getWidgetFrom(child);
        try list.append(widget);
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
        pub const DrawCallback = *const fn (widget: *anyopaque, ctx: *backend.DrawContext) anyerror!void;
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
                if (@import("builtin").target.cpu.arch.isWasm()) {
                    // can't use writeStackTrace as it is async but errorHandler should not be async!
                    // also can't use writeStackTrace when using WebAssembly
                } else {
                    if (std.debug.getSelfDebugInfo()) |debug_info| {
                        var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
                        defer arena.deinit();
                        std.debug.writeStackTrace(trace.*, writer, debug_info, .no_color) catch {};
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

        fn drawHandler(ctx: *backend.DrawContext, data: usize) void {
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
            const size = Size{ .width = @floatFromInt(width), .height = @floatFromInt(height) };
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
        fn opacityChanged(newValue: f32, userdata: ?*anyopaque) void {
            const widget: *T = @ptrCast(@alignCast(userdata.?));
            if (widget.peer) |*peer| {
                peer.setOpacity(newValue);
            }
        }

        pub fn setupEvents(self: *T) !void {
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

            _ = try self.widget_data.atoms.opacity.addChangeListener(.{ .function = opacityChanged, .userdata = self });
            opacityChanged(self.widget_data.atoms.opacity.get(), self); // call it so it's updated
        }

        fn isValidHandler(comptime U: type) bool {
            if (@typeInfo(U) != .pointer) return false;
            const child = @typeInfo(U).pointer.child;
            if (@typeInfo(child) != .@"fn") return false;
            const return_type = @typeInfo(child).@"fn".return_type.?;
            return @typeInfo(return_type) == .error_union;
        }

        pub fn addClickHandler(self: *T, handler: anytype) !void {
            comptime std.debug.assert(isValidHandler(@TypeOf(handler)));
            try self.widget_data.handlers.clickHandlers.append(@as(Callback, @ptrCast(handler)));
        }

        pub fn addDrawHandler(self: *T, handler: anytype) !void {
            comptime std.debug.assert(isValidHandler(@TypeOf(handler)));
            try self.widget_data.handlers.drawHandlers.append(@as(DrawCallback, @ptrCast(handler)));
        }

        pub fn addMouseButtonHandler(self: *T, handler: anytype) !void {
            comptime std.debug.assert(isValidHandler(@TypeOf(handler)));
            try self.widget_data.handlers.buttonHandlers.append(@as(ButtonCallback, @ptrCast(handler)));
        }

        pub fn addMouseMotionHandler(self: *T, handler: anytype) !void {
            comptime std.debug.assert(isValidHandler(@TypeOf(handler)));
            try self.widget_data.handlers.mouseMoveHandlers.append(@as(MouseMoveCallback, @ptrCast(handler)));
        }

        pub fn addScrollHandler(self: *T, handler: anytype) !void {
            comptime std.debug.assert(isValidHandler(@TypeOf(handler)));
            try self.widget_data.handlers.scrollHandlers.append(@as(ScrollCallback, @ptrCast(handler)));
        }

        pub fn addResizeHandler(self: *T, handler: anytype) !void {
            comptime std.debug.assert(isValidHandler(@TypeOf(handler)));
            try self.widget_data.handlers.resizeHandlers.append(@as(ResizeCallback, @ptrCast(handler)));
        }

        pub fn addKeyTypeHandler(self: *T, handler: anytype) !void {
            comptime std.debug.assert(isValidHandler(@TypeOf(handler)));
            try self.widget_data.handlers.keyTypeHandlers.append(@as(KeyTypeCallback, @ptrCast(handler)));
        }

        pub fn addKeyPressHandler(self: *T, handler: anytype) !void {
            comptime std.debug.assert(isValidHandler(@TypeOf(handler)));
            try self.widget_data.handlers.keyPressHandlers.append(@as(KeyPressCallback, @ptrCast(handler)));
        }

        /// This shouldn't be used by user applications directly.
        /// Instead set a change listener to the corresponding atom.
        pub fn addPropertyChangeHandler(self: *T, handler: anytype) !void {
            comptime std.debug.assert(isValidHandler(@TypeOf(handler)));
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
