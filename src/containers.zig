const std = @import("std");
const backend = @import("backend.zig");
const Widget = @import("widget.zig").Widget;
usingnamespace @import("internal.zig");
usingnamespace @import("data.zig");

pub const Layout = fn(peer: backend.Container, widgets: []Widget) void;

pub fn ColumnLayout(peer: backend.Container, widgets: []Widget) void {
    const count = @intCast(u32, widgets.len);
    const childHeight = @intCast(u32, peer.getHeight()) / count;
    for (widgets) |widget, idx| {
        if (widget.peer) |widgetPeer| {
            peer.move(widgetPeer,
                0, 
                @intCast(u32, childHeight * idx) // this cannot be higher than the container's height so it shouldn't overflow
            );
            const size = Size {
                .width = @intCast(u32, peer.getWidth()), // self.width
                .height = childHeight
            };
            peer.resize(widgetPeer, size.width, size.height);
        }
    }
}

pub fn RowLayout(peer: backend.Container, widgets: []Widget) void {
    const count = @intCast(u32, widgets.len);
    const childWidth = @intCast(u32, peer.getWidth()) / count;
    for (widgets) |widget, idx| {
        if (widget.peer) |widgetPeer| {
            peer.move(widgetPeer,
                @intCast(u32, childWidth * idx), // this cannot be higher than the container's width so it shouldn't overflow
                0
            );
            const size = Size {
                .width = childWidth, // self.width
                .height = @intCast(u32, peer.getHeight())
            };
            peer.resize(widgetPeer, size.width, size.height);
        }
    }
}

const Stack_Impl = struct {
    peer: backend.Stack,
    childrens: std.ArrayList(Widget),

    pub fn init(childrens: std.ArrayList(Widget)) !Stack_Impl {
        const peer = try backend.Stack.create();
        for (childrens.items) |widget| {
            peer.add(widget.peer);
        }
        return Stack_Impl {
            .peer = peer,
            .childrens = childrens
        };
    }

    pub fn add(self: *Stack_Impl, widget: anytype) !void {
        // self.peer.put(widget.peer, 
        //     try std.math.cast(c_int, x),
        //     try std.math.cast(c_int, y)
        // );
    }
};

const Container_Impl = struct {
    pub usingnamespace @import("internal.zig").All(Container_Impl);

    peer: ?backend.Container,
    handlers: Container_Impl.Handlers = undefined,
    childrens: std.ArrayList(Widget),
    expand: bool,
    relayouting: bool = false,
    layout: Layout,

    pub fn init(childrens: std.ArrayList(Widget), config: GridConfig, layout: Layout) !Container_Impl {
        var column = Container_Impl.init_events(Container_Impl {
            .peer = null,
            .childrens = childrens,
            .expand = config.expand == .Fill,
            .layout = layout
        });
        try column.addResizeHandler(onResize);
        return column;
    }

    /// Internal function used at initialization.
    /// It is used to move some pointers so things do not break.
    pub fn pointerMoved(self: *Container_Impl) void {}

    pub fn onResize(self: *Container_Impl, size: Size) !void {
        try self.relayout();
    }

    pub fn getPreferredSize(self: *Container_Impl) Size {
        return Size { .width = 500.0, .height = 200.0 };
    }

    pub fn show(self: *Container_Impl) !void {
        if (self.peer == null) {
            var peer = try backend.Container.create();
            //peer.expand = self.expand;
            for (self.childrens.items) |*widget| {
                try widget.show();
                peer.add(widget.peer.?);
            }
            self.peer = peer;
            try self.show_events();
            try self.relayout();
        }
    }

    pub fn relayout(self: *Container_Impl) !void {
        if (self.relayouting) return;
        if (self.peer) |peer| {
            self.relayouting = true;
            self.layout(peer, self.childrens.items);
            self.relayouting = false;
        }
    }

    pub fn add(self: *Container_Impl, widget: anytype) !void {
        const allocator = self.childrens.allocator;
        const genericWidget = genericWidgetFrom(widget);

        if (self.peer) |*peer| {
            peer.add(genericWidget.peer, genericWidget.container_expanded);
        }

        try self.childrens.append(genericWidget);
    }
};

/// Create a generic Widget struct from the given component.
fn genericWidgetFrom(component: anytype) anyerror!Widget {
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
        .class = &DereferencedType.WidgetClass
    };
}

fn isErrorUnion(comptime T: type) bool {
    return switch (@typeInfo(T)) {
        .ErrorUnion => true,
        else => false
    };
}

fn abstractContainerConstructor(comptime T: type, childrens: anytype, config: anytype, layout: Layout) anyerror!T {
    const fields = std.meta.fields(@TypeOf(childrens));
    var list = std.ArrayList(Widget).init(lasting_allocator);
    inline for (fields) |field| {
        const element = @field(childrens, field.name);
        const child = 
            if (comptime isErrorUnion(@TypeOf(element))) // if it is an error union, unwrap it
                try element
            else
                element;
        
        const widget = try genericWidgetFrom(child);
        try list.append(widget);
    }

    return try T.init(list, config, layout);
} 

const Expand = enum {
    /// The grid should take the minimal size that its childrens want
    No,
    /// The grid should expand to its maximum size by padding non-expanded childrens
    Fill,
};

const GridConfig = struct {
    expand: Expand = .No,
};

/// Set the style of the child to expanded by creating and showing the widget early.
pub fn Expanded(child: anytype) callconv(.Inline) anyerror!Widget {
    var widget = try genericWidgetFrom(
        if (comptime isErrorUnion(@TypeOf(child)))
            try child
        else
            child);
    widget.container_expanded = true;
    return widget;
}

pub fn Stack(childrens: anytype) callconv(.Inline) anyerror!Stack_Impl {
    return try abstractContainerConstructor(Stack_Impl, childrens, .{});
}

pub fn Row(config: GridConfig, childrens: anytype) callconv(.Inline) anyerror!Container_Impl {
    return try abstractContainerConstructor(Container_Impl, childrens, config, RowLayout);
}

pub fn Column(config: GridConfig, childrens: anytype) callconv(.Inline) anyerror!Container_Impl {
    return try abstractContainerConstructor(Container_Impl, childrens, config, ColumnLayout);
}
