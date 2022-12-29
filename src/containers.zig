const std = @import("std");
const backend = @import("backend.zig");
const Widget = @import("widget.zig").Widget;
const lasting_allocator = @import("internal.zig").lasting_allocator;
const Size = @import("data.zig").Size;
const Rectangle = @import("data.zig").Rectangle;

const convertTupleToWidgets = @import("internal.zig").convertTupleToWidgets;

pub const Layout = *const fn (peer: Callbacks, widgets: []Widget) void;
const Callbacks = struct {
    userdata: usize,
    moveResize: *const fn (data: usize, peer: backend.PeerType, x: u32, y: u32, w: u32, h: u32) void,
    getSize: *const fn (data: usize) Size,
    computingPreferredSize: bool,
    availableSize: ?Size = null,
    layoutConfig: [16]u8,

    pub fn getLayoutConfig(self: Callbacks, comptime T: type) T {
        comptime std.debug.assert(@sizeOf(T) <= 16);
        const slice = self.layoutConfig[0..@sizeOf(T)];
        return @ptrCast(*const T, @alignCast(@alignOf(T), slice)).*;
    }
};

fn getExpandedCount(widgets: []Widget) u32 {
    var expandedCount: u32 = 0;
    for (widgets) |widget| {
        if (widget.container_expanded) expandedCount += 1;
    }

    return expandedCount;
}

const ColumnRowConfig = struct {
    spacing: u32 = 0,
    wrapping: bool = false,
};

pub fn ColumnLayout(peer: Callbacks, widgets: []Widget) void {
    const expandedCount = getExpandedCount(widgets);
    const config = peer.getLayoutConfig(ColumnRowConfig);

    const totalAvailableHeight = @intCast(u32, peer.getSize(peer.userdata).height -| (widgets.len -| 1) * config.spacing);

    var childHeight = if (expandedCount == 0) 0 else @intCast(u32, totalAvailableHeight) / expandedCount;
    for (widgets) |widget| {
        if (!widget.container_expanded) {
            const available = if (expandedCount > 0) Size.init(0, 0) else Size.init(peer.getSize(peer.userdata).width, totalAvailableHeight);
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
    for (widgets) |widget, i| {
        const isLastWidget = i == widgets.len - 1;
        if (widget.peer) |widgetPeer| {
            const available = Size{
                .width = @intCast(u32, peer.getSize(peer.userdata).width),
                .height = if (widget.container_expanded) childHeight else (@intCast(u32, peer.getSize(peer.userdata).height) -| @floatToInt(u32, childY)),
            };
            const preferred = widget.getPreferredSize(available);
            const size = blk: {
                if (widget.container_expanded) {
                    // if we're computing preferred size, avoid inflating and return preferred width
                    if (peer.computingPreferredSize) {
                        break :blk Size.init(preferred.width, available.height);
                    } else {
                        break :blk available;
                    }
                } else if (widget.alignX.get() == null and !peer.computingPreferredSize) {
                    break :blk Size.intersect(available, Size.init(available.width, preferred.height));
                } else {
                    if (peer.computingPreferredSize and widget.alignX.get() != null and widget.alignX.get().? > 0) {
                        break :blk Size.intersect(available, Size.init(available.width, preferred.height));
                    }
                    break :blk Size.intersect(available, preferred);
                }
            };

            const alignX = std.math.clamp(widget.alignX.get() orelse 0, 0, 1);
            var x = @floatToInt(u32, @floor(alignX * @intToFloat(f32, peer.getSize(peer.userdata).width -| size.width)));
            if (widget.container_expanded or peer.computingPreferredSize) x = 0;
            peer.moveResize(peer.userdata, widgetPeer, x, @floatToInt(u32, @floor(childY)), size.width, size.height);
            childY += @intToFloat(f32, size.height) + if (isLastWidget) 0 else @intToFloat(f32, config.spacing);
        }
    }
}

pub fn RowLayout(peer: Callbacks, widgets: []Widget) void {
    const expandedCount = getExpandedCount(widgets);
    const config = peer.getLayoutConfig(ColumnRowConfig);

    const totalAvailableWidth = @intCast(u32, peer.getSize(peer.userdata).width -| (widgets.len -| 1) * config.spacing);

    var childWidth = if (expandedCount == 0) 0 else @intCast(u32, totalAvailableWidth) / expandedCount;
    for (widgets) |widget| {
        if (!widget.container_expanded) {
            const available = if (expandedCount > 0) Size.init(0, 0) else Size.init(totalAvailableWidth, peer.getSize(peer.userdata).height);
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
    for (widgets) |widget, i| {
        const isLastWidget = i == widgets.len - 1;
        if (widget.peer) |widgetPeer| {
            const available = Size{
                .width = if (widget.container_expanded) childWidth else (@intCast(u32, peer.getSize(peer.userdata).width) -| @floatToInt(u32, childX)),
                .height = @intCast(u32, peer.getSize(peer.userdata).height),
            };
            const preferred = widget.getPreferredSize(available);
            const size = blk: {
                if (widget.container_expanded) {
                    // if we're computing preferred size, avoid inflating and return preferred height
                    if (peer.computingPreferredSize) {
                        break :blk Size.init(available.width, preferred.height);
                    } else {
                        break :blk available;
                    }
                } else if (!peer.computingPreferredSize) {
                    break :blk Size.intersect(available, Size.init(preferred.width, available.height));
                } else {
                    break :blk Size.intersect(available, preferred);
                }
            };

            const y: u32 = 0;
            peer.moveResize(peer.userdata, widgetPeer, @floatToInt(u32, @floor(childX)), y, size.width, size.height);
            childX += @intToFloat(f32, size.width) + if (isLastWidget) 0 else @intToFloat(f32, config.spacing);
        }
    }
}

pub fn MarginLayout(peer: Callbacks, widgets: []Widget) void {
    const margin = peer.getLayoutConfig(Rectangle);
    if (widgets.len > 1) {
        std.log.scoped(.zgt).warn("Margin container has more than one widget!", .{});
        return;
    }

    if (widgets[0].peer) |widgetPeer| {
        const available = peer.getSize(peer.userdata);
        const left = std.math.lossyCast(u32, margin.x());
        const top = std.math.lossyCast(u32, margin.y());
        const right = margin.width();
        const bottom = margin.height();

        if (peer.computingPreferredSize) {
            // What to return for computing preferred size
            const preferredSize = widgets[0].getPreferredSize(.{ .width = 0, .height = 0 });
            peer.moveResize(peer.userdata, widgetPeer, left, top, preferredSize.width + right, preferredSize.height + bottom);
        } else {
            // What to return for actual layouting
            const preferredSize = widgets[0].getPreferredSize(available);

            const finalSize = Size.intersect(preferredSize, available);
            //peer.moveResize(peer.userdata, widgetPeer, 0, 0, finalSize.width, finalSize.height);
            peer.moveResize(peer.userdata, widgetPeer, left, top, finalSize.width -| left -| right, finalSize.height -| top -| bottom);
        }
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
    layoutConfig: [16]u8,

    /// The widget associated to this Container_Impl
    widget: ?*Widget = null,

    pub fn init(childrens: std.ArrayList(Widget), config: GridConfig, layout: Layout, layoutConfig: anytype) !Container_Impl {
        const LayoutConfig = @TypeOf(layoutConfig);
        comptime std.debug.assert(@sizeOf(LayoutConfig) <= 16);
        var layoutConfigBytes: [16]u8 = undefined;
        if (@sizeOf(LayoutConfig) > 0) {
            layoutConfigBytes[0..@sizeOf(LayoutConfig)].* = std.mem.toBytes(layoutConfig);
        }

        var container = Container_Impl.init_events(Container_Impl{
            .peer = null,
            .childrens = childrens,
            .expand = config.expand == .Fill,
            .layout = layout,
            .layoutConfig = layoutConfigBytes,
        });
        _ = container.setName(config.name);
        _ = container.set("alignX", config.alignX);
        _ = container.set("alignY", config.alignY);
        try container.addResizeHandler(&onResize);
        return container;
    }

    pub fn onResize(self: *Container_Impl, size: Size) !void {
        _ = size;
        self.relayout();
    }

    pub fn getChildAt(self: *Container_Impl, index: usize) !*Widget {
        if (index >= self.childrens.items.len) return error.OutOfBounds;
        return &self.childrens.items[index];
    }

    pub fn getChild(self: *Container_Impl, name: []const u8) ?*Widget {
        // TODO: use hash map (maybe acting as cache?) for performance
        for (self.childrens.items) |*widget| {
            if (widget.name.*.get()) |widgetName| {
                if (std.mem.eql(u8, name, widgetName)) {
                    return widget;
                }
            }

            if (widget.cast(Container_Impl)) |container| {
                //return container.getChild(name) orelse continue;

                // workaround a stage2 bug
                // TODO: reduce to a unit test and report to ziglang/zig
                const function = getChild;
                return function(container, name) orelse continue;
            }
        }
        return null;
    }

    /// Combines getChild() and Widget.as()
    pub fn getChildAs(self: *Container_Impl, comptime T: type, name: []const u8) ?*T {
        if (self.getChild(name)) |widget| {
            return widget.as(T);
        } else {
            return null;
        }
    }

    pub fn getPreferredSize(self: *Container_Impl, available: Size) Size {
        var size: Size = Size{ .width = 0, .height = 0 };
        const callbacks = Callbacks{
            .userdata = @ptrToInt(&size),
            .moveResize = fakeResMove,
            .getSize = fakeSize,
            .computingPreferredSize = true,
            .availableSize = available,
            .layoutConfig = self.layoutConfig,
        };
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
            self.relayout();
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

    pub fn relayout(self: *Container_Impl) void {
        if (self.relayouting.load(.SeqCst) == true) return;
        if (self.peer) |peer| {
            self.relayouting.store(true, .SeqCst);
            const callbacks = Callbacks{
                .userdata = @ptrToInt(&peer),
                .moveResize = moveResize,
                .getSize = getSize,
                .computingPreferredSize = false,
                .layoutConfig = self.layoutConfig,
            };
            self.layout(callbacks, self.childrens.items);
            self.relayouting.store(false, .SeqCst);
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
            genericWidget.as(ComponentType).dataWrappers.widget = slot;
        }

        if (self.peer) |*peer| {
            try slot.show();
            peer.add(slot.peer.?);
        }

        self.relayout();
    }

    pub fn removeByIndex(self: *Container_Impl, index: usize) void {
        // TODO: deinit widget here?
        const widget = self.childrens.items[index];
        // Remove from the component
        if (self.peer) |*peer| {
            peer.remove(widget.peer.?);
        }
        // And finally remove from the list, and relayout to apply changes
        std.debug.assert(std.meta.eql(
            self.childrens.orderedRemove(index),
            widget,
        ));
        self.relayout();
    }

    pub fn removeAll(self: *Container_Impl) void {
        while (self.childrens.items.len > 0) {
            self.removeByIndex(0);
        }
    }

    pub fn _deinit(self: *Container_Impl) void {
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

const Expand = enum {
    /// The grid should take the minimal size that its childrens want
    No,
    /// The grid should expand to its maximum size by padding non-expanded childrens
    Fill,
};

pub const GridConfig = struct {
    expand: Expand = .No,
    name: ?[]const u8 = null,
    alignX: ?f32 = null,
    alignY: ?f32 = null,
    spacing: u32 = 5,
    wrapping: bool = false,
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
    return try Container_Impl.init(try convertTupleToWidgets(childrens), .{}, StackLayout, {});
}

pub inline fn Row(config: GridConfig, childrens: anytype) anyerror!Container_Impl {
    return try Container_Impl.init(try convertTupleToWidgets(childrens), config, RowLayout, ColumnRowConfig{ .spacing = config.spacing, .wrapping = config.wrapping });
}

pub inline fn Column(config: GridConfig, childrens: anytype) anyerror!Container_Impl {
    return try Container_Impl.init(try convertTupleToWidgets(childrens), config, ColumnLayout, ColumnRowConfig{ .spacing = config.spacing, .wrapping = config.wrapping });
}

pub inline fn Margin(margin: Rectangle, child: anytype) anyerror!Container_Impl {
    return try Container_Impl.init(try convertTupleToWidgets(.{child}), .{}, MarginLayout, margin);
}

// TODO: align component
pub const AlignOptions = struct {
    // TODO: switch to pivot + align system or keep current system where both are combined?
    alignX: f32 = 0.5,
    alignY: f32 = 0.5,
};

pub inline fn Align(opts: AlignOptions, child: anytype) anyerror!Container_Impl {
    _ = opts;
    _ = child;
    @compileError("TODO: align");
}
