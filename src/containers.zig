const std = @import("std");
const backend = @import("backend.zig");
const Widget = @import("widget.zig").Widget;
const lasting_allocator = @import("internal.zig").lasting_allocator;
const Size = @import("data.zig").Size;
const Rectangle = @import("data.zig").Rectangle;

pub const Layout = fn (peer: Callbacks, widgets: []Widget) void;
const Callbacks = struct {
    userdata: usize,
    moveResize: fn (data: usize, peer: backend.PeerType, x: u32, y: u32, w: u32, h: u32) void,
    getSize: fn (data: usize) Size,
    computingPreferredSize: bool,
    availableSize: ?Size = null,
};

fn getExpandedCount(widgets: []Widget) u32 {
    var expandedCount: u32 = 0;
    for (widgets) |widget| {
        if (widget.container_expanded) expandedCount += 1;
    }

    return expandedCount;
}

pub fn ColumnLayout(peer: Callbacks, widgets: []Widget) void {
    //const count = @intCast(u32, widgets.len);
    const expandedCount = getExpandedCount(widgets);

    var childHeight = if (expandedCount == 0) 0 else @intCast(u32, peer.getSize(peer.userdata).height) / expandedCount;
    for (widgets) |widget| {
        if (!widget.container_expanded) {
            const available = if (expandedCount > 0) Size.init(0, 0) else peer.getSize(peer.userdata);
            const divider = if (expandedCount == 0) 1 else expandedCount;
            const takenHeight = widget.getPreferredSize(available).height / divider;
            if (childHeight >= takenHeight) {
                childHeight -= takenHeight;
            } else {
                childHeight = 0;
            }
        }
    }

    var childY: f32 = 0.0;
    for (widgets) |*widget| {
        if (widget.peer) |widgetPeer| {
            const available = Size{ .width = @intCast(u32, peer.getSize(peer.userdata).width), .height = if (widget.container_expanded) childHeight else (@intCast(u32, peer.getSize(peer.userdata).height) - @floatToInt(u32, childY)) };
            const preferred = widget.getPreferredSize(available);
            const size = if (widget.container_expanded) available else Size.intersect(available, preferred);
            const alignX = std.math.clamp(widget.alignX.get(), 0, 1);
            var x = @floatToInt(u32, @floor(alignX * @intToFloat(f32, peer.getSize(peer.userdata).width -| preferred.width)));
            if (widget.container_expanded or peer.computingPreferredSize) x = 0;
            peer.moveResize(peer.userdata, widgetPeer, x, @floatToInt(u32, @floor(childY)), size.width, size.height);
            childY += @intToFloat(f32, size.height);
        }
    }
}

pub fn RowLayout(peer: Callbacks, widgets: []Widget) void {
    //const count = @intCast(u32, widgets.len);
    const expandedCount = getExpandedCount(widgets);

    var childWidth = if (expandedCount == 0) 0 else @intCast(u32, peer.getSize(peer.userdata).width) / expandedCount;
    for (widgets) |widget| {
        if (!widget.container_expanded) {
            const available = peer.getSize(peer.userdata);
            const divider = if (expandedCount == 0) 1 else expandedCount;
            const takenWidth = widget.getPreferredSize(available).width / divider;
            if (childWidth >= takenWidth) {
                childWidth -= takenWidth;
            } else {
                childWidth = 0;
            }
        }
    }

    var childX: f32 = 0.0;
    for (widgets) |widget| {
        if (widget.peer) |widgetPeer| {
            if (@floatToInt(u32, childX) >= peer.getSize(peer.userdata).width) {
                break;
            }
            const available = Size{ .width = if (widget.container_expanded) childWidth else (@intCast(u32, peer.getSize(peer.userdata).width) - @floatToInt(u32, childX)), .height = @intCast(u32, peer.getSize(peer.userdata).height) };
            const preferred = widget.getPreferredSize(available);
            const size = if (widget.container_expanded) available else Size.intersect(available, preferred);
            const alignY = std.math.clamp(widget.alignY.get(), 0, 1);
            var y = @floatToInt(u32, @floor(alignY * @intToFloat(f32, peer.getSize(peer.userdata).height -| preferred.height)));
            if (widget.container_expanded or peer.computingPreferredSize) y = 0;
            peer.moveResize(peer.userdata, widgetPeer, @floatToInt(u32, @floor(childX)), y, size.width, size.height);
            childX += @intToFloat(f32, size.width);
        }
    }
}

pub fn MarginLayout(peer: Callbacks, widgets: []Widget) void {
    const margin = Rectangle{ .left = 5, .top = 5, .right = 5, .bottom = 5 };
    if (widgets.len > 1) {
        std.log.scoped(.zgt).warn("Margin container has more than one widget!", .{});
        return;
    }

    if (widgets[0].peer) |widgetPeer| {
        const available = peer.getSize(peer.userdata);
        const preferredSize = widgets[0].getPreferredSize(.{ .width = 0, .height = 0 });

        // const size = Size {
        //     .width = std.math.max(@intCast(u32, preferredSize.width), margin.left + margin.right) - margin.left - margin.right,
        //     .height = std.math.max(@intCast(u32, preferredSize.height), margin.top + margin.bottom) - margin.top - margin.bottom
        // };
        // _ = size;
        //const finalSize = Size.combine(preferredSize, available);
        _ = widgetPeer;
        _ = preferredSize;
        _ = margin;
        //peer.moveResize(peer.userdata, widgetPeer, margin.left, margin.top, finalSize.width, finalSize.height);
        peer.moveResize(peer.userdata, widgetPeer, 0, 0, available.width, available.height);
    }
}

pub fn StackLayout(peer: Callbacks, widgets: []Widget) void {
    const size = peer.getSize(peer.userdata);
    for (widgets) |widget| {
        if (widget.peer) |widgetPeer| {
            const widgetSize = if (peer.computingPreferredSize) widget.getPreferredSize(peer.availableSize.?) else size;
            peer.moveResize(peer.userdata, widgetPeer, 0, 0, widgetSize.width, widgetSize.height);
        }
    }
}

pub const Container_Impl = struct {
    pub usingnamespace @import("internal.zig").All(Container_Impl);

    peer: ?backend.Container,
    handlers: Container_Impl.Handlers = undefined,
    dataWrappers: Container_Impl.DataWrappers = .{},
    childrens: std.ArrayList(Widget),
    expand: bool,
    relayouting: std.atomic.Atomic(bool) = std.atomic.Atomic(bool).init(false),
    layout: Layout,

    /// The widget associated to this Container_Impl
    widget: ?*Widget = null,

    pub fn init(childrens: std.ArrayList(Widget), config: GridConfig, layout: Layout) !Container_Impl {
        var column = Container_Impl.init_events(Container_Impl{ .peer = null, .childrens = childrens, .expand = config.expand == .Fill, .layout = layout })
            .setName(config.name);
        try column.addResizeHandler(onResize);
        return column;
    }

    pub fn onResize(self: *Container_Impl, size: Size) !void {
        _ = size;
        try self.relayout();
    }

    pub fn getAt(self: *Container_Impl, index: usize) !*Widget {
        if (index >= self.childrens.items.len) return error.OutOfBounds;
        return &self.childrens.items[index];
    }

    pub fn get(self: *Container_Impl, name: []const u8) ?*Widget {
        // TODO: use hash map (maybe acting as cache?) for performance
        for (self.childrens.items) |*widget| {
            if (widget.name.*) |widgetName| {
                if (std.mem.eql(u8, name, widgetName)) {
                    return widget;
                }
            }

            if (widget.cast(Container_Impl)) |container| {
                return container.get(name);
            }
        }
        return null;
    }

    pub fn getPreferredSize(self: *Container_Impl, available: Size) Size {
        _ = available;

        var size: Size = Size{ .width = 0, .height = 0 };
        const callbacks = Callbacks{ .userdata = @ptrToInt(&size), .moveResize = fakeResMove, .getSize = fakeSize, .computingPreferredSize = true, .availableSize = available };
        self.layout(callbacks, self.childrens.items);
        return size;
    }

    pub fn show(self: *Container_Impl) !void {
        if (self.peer == null) {
            var peer = try backend.Container.create();
            for (self.childrens.items) |*widget| {
                if (self.expand) {
                    widget.container_expanded = true;
                }
                try widget.show();
                peer.add(widget.peer.?);
            }
            self.peer = peer;
            try self.show_events();
            try self.relayout();
        }
    }

    pub fn _showWidget(widget: *Widget, self: *Container_Impl) !void {
        self.widget = widget;
        for (self.childrens.items) |*child| {
            child.parent = widget;
        }
    }

    fn fakeSize(data: usize) Size {
        _ = data;
        return Size{
            .width = std.math.maxInt(u32) / 2, // divide by 2 to leave some room
            .height = std.math.maxInt(u32) / 2,
        };
    }

    fn fakeResMove(data: usize, widget: backend.PeerType, x: u32, y: u32, w: u32, h: u32) void {
        const size = @intToPtr(*Size, data);
        _ = widget;
        size.width = std.math.max(size.width, x + w);
        size.height = std.math.max(size.height, y + h);
    }

    fn getSize(data: usize) Size {
        const peer = @intToPtr(*backend.Container, data);
        return Size{ .width = @intCast(u32, peer.getWidth()), .height = @intCast(u32, peer.getHeight()) };
    }

    fn moveResize(data: usize, widget: backend.PeerType, x: u32, y: u32, w: u32, h: u32) void {
        @intToPtr(*backend.Container, data).move(widget, x, y);
        @intToPtr(*backend.Container, data).resize(widget, w, h);
    }

    pub fn relayout(self: *Container_Impl) !void {
        if (self.relayouting.load(.Acquire) == true) return;
        if (self.peer) |peer| {
            self.relayouting.store(true, .Release);
            const callbacks = Callbacks{ .userdata = @ptrToInt(&peer), .moveResize = moveResize, .getSize = getSize, .computingPreferredSize = false };
            self.layout(callbacks, self.childrens.items);
            self.relayouting.store(false, .Release);
        }
    }

    pub fn add(self: *Container_Impl, widget: anytype) !void {
        const ComponentType = @import("internal.zig").DereferencedType(@TypeOf(widget));

        var genericWidget = try @import("internal.zig").genericWidgetFrom(widget);
        if (self.expand) {
            genericWidget.container_expanded = true;
        }

        if (self.widget) |parent| {
            genericWidget.parent = parent;
        }

        const slot = try self.childrens.addOne();
        slot.* = genericWidget;
        if (@hasField(ComponentType, "dataWrappers")) {
            widget.as(ComponentType).dataWrappers.widget = slot;
        }

        if (self.peer) |*peer| {
            try slot.show();
            peer.add(slot.peer.?);
        }

        try self.relayout();
    }

    pub fn deinit(self: *Container_Impl, widget: *Widget) void {
        _ = widget;
        for (self.childrens.items) |*child| {
            child.deinit();
        }
        self.childrens.deinit();
    }
};

fn isErrorUnion(comptime T: type) bool {
    return switch (@typeInfo(T)) {
        .ErrorUnion => true,
        else => false,
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

        const ComponentType = @import("internal.zig").DereferencedType(@TypeOf(child));
        const widget = try @import("internal.zig").genericWidgetFrom(child);
        if (ComponentType != Widget) {
            inline for (std.meta.fields(ComponentType)) |compField| {
                if (comptime @import("data.zig").isDataWrapper(compField.field_type)) {
                    const wrapper = @field(widget.as(ComponentType), compField.name);
                    if (wrapper.updater) |updater| {
                        std.log.info("data updater of {s} field '{s}'", .{ @typeName(ComponentType), compField.name });

                        // cannot get parent as of now
                        try @import("data.zig").proneUpdater(updater, undefined);
                    }
                }
            }
        }
        const slot = try list.addOne();
        slot.* = widget;

        if (ComponentType != Widget) {
            widget.as(ComponentType).dataWrappers.widget = slot;
        }
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
    name: ?[]const u8 = null,
};

/// Set the style of the child to expanded by creating and showing the widget early.
pub inline fn Expanded(child: anytype) anyerror!Widget {
    var widget = try @import("internal.zig").genericWidgetFrom(if (comptime isErrorUnion(@TypeOf(child)))
        try child
    else
        child);
    widget.container_expanded = true;
    return widget;
}

pub inline fn Stack(childrens: anytype) anyerror!Container_Impl {
    return try abstractContainerConstructor(Container_Impl, childrens, .{}, StackLayout);
}

pub inline fn Row(config: GridConfig, childrens: anytype) anyerror!Container_Impl {
    return try abstractContainerConstructor(Container_Impl, childrens, config, RowLayout);
}

pub inline fn Column(config: GridConfig, childrens: anytype) anyerror!Container_Impl {
    return try abstractContainerConstructor(Container_Impl, childrens, config, ColumnLayout);
}

pub inline fn Margin(child: anytype) anyerror!Container_Impl {
    return try abstractContainerConstructor(Container_Impl, .{child}, GridConfig{}, MarginLayout);
}
