const std = @import("std");
const backend = @import("backend.zig");
const Widget = @import("widget.zig").Widget;
const global_allocator = @import("internal.zig").allocator;
const Size = @import("data.zig").Size;
const Rectangle = @import("data.zig").Rectangle;
const AnimationController = @import("AnimationController.zig");
const capy = @import("capy.zig");

const isErrorUnion = @import("internal.zig").isErrorUnion;
const convertTupleToWidgets = @import("internal.zig").convertTupleToWidgets;

pub const Layout = *const fn (peer: Callbacks, widgets: []*Widget) void;
const Callbacks = struct {
    userdata: usize,
    moveResize: *const fn (data: usize, peer: backend.PeerType, x: u32, y: u32, w: u32, h: u32) void,
    getSize: *const fn (data: usize) Size,
    setTabOrder: *const fn (data: usize, peers: []const backend.PeerType) void,
    computingPreferredSize: bool,
    availableSize: ?Size = null,
    layoutConfig: [Container.LAYOUT_CONFIG_SIZE]u8 align(8),

    pub fn getLayoutConfig(self: Callbacks, comptime T: type) T {
        comptime std.debug.assert(@sizeOf(T) <= Container.LAYOUT_CONFIG_SIZE);
        const slice = self.layoutConfig[0..@sizeOf(T)];
        return @as(*const T, @ptrCast(@alignCast(slice))).*;
    }
};

fn getExpandedCount(widgets: []const *const Widget) u32 {
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

/// Arranges items vertically.
pub fn ColumnLayout(peer: Callbacks, widgets: []*Widget) void {
    const expandedCount = getExpandedCount(widgets);
    const config = peer.getLayoutConfig(ColumnRowConfig);
    const spacing: f32 = @floatFromInt(config.spacing);

    const totalAvailableHeight: f32 = @max(0, peer.getSize(peer.userdata).height - @as(f32, @floatFromInt((widgets.len -| 1) * config.spacing)));

    var childHeight = if (expandedCount == 0) 0 else totalAvailableHeight / @as(f32, @floatFromInt(expandedCount));
    for (widgets) |widget| {
        if (!widget.container_expanded) {
            const available = if (expandedCount > 0) Size.init(0, 0) else Size.init(peer.getSize(peer.userdata).width, totalAvailableHeight);
            const divider: f32 = if (expandedCount == 0) 1 else @floatFromInt(expandedCount);
            const takenHeight = widget.getPreferredSize(available).height / divider;
            if (childHeight >= takenHeight) {
                childHeight -= takenHeight;
            } else {
                childHeight = 0;
            }
        }
    }

    var childY: f32 = 0.0;
    // Child X is different from 0 only when 'wrapping' property is set to true
    var childX: f32 = 0.0;
    for (widgets, 0..) |widget, i| {
        const isLastWidget = i == widgets.len - 1;
        if (widget.peer) |widgetPeer| {
            const minimumSize = widget.getPreferredSize(Size.init(1, 1));
            if (config.wrapping) {
                if (childY >= @max(0, peer.getSize(peer.userdata).height - minimumSize.height)) {
                    childY = 0;
                    // TODO: largest width of all the column
                    childX += minimumSize.width;
                }
            }

            const available = Size{
                .width = peer.getSize(peer.userdata).width,
                .height = if (widget.container_expanded) childHeight else @max(0, peer.getSize(peer.userdata).height - childY),
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
                } else if (!peer.computingPreferredSize) {
                    const width = if (config.wrapping) preferred.width else available.width;
                    break :blk Size.intersect(available, Size.init(width, preferred.height));
                } else {
                    break :blk Size.intersect(available, preferred);
                }
            };

            peer.moveResize(peer.userdata, widgetPeer, @intFromFloat(childX), @intFromFloat(childY), @intFromFloat(size.width), @intFromFloat(size.height));
            childY += size.height + if (isLastWidget) 0 else spacing;
        }
    }

    var peers = std.ArrayList(backend.PeerType).initCapacity(global_allocator, widgets.len) catch return;
    defer peers.deinit();

    for (widgets) |widget| {
        if (widget.peer) |widget_peer| {
            peers.appendAssumeCapacity(widget_peer);
        }
    }

    // TODO: RTL support
    peer.setTabOrder(peer.userdata, peers.items);
}

/// Arranges items horizontally.
pub fn RowLayout(peer: Callbacks, widgets: []*Widget) void {
    const expandedCount = getExpandedCount(widgets);
    const config = peer.getLayoutConfig(ColumnRowConfig);
    const spacing: f32 = @floatFromInt(config.spacing);

    const totalAvailableWidth: f32 = @max(0, peer.getSize(peer.userdata).width - @as(f32, @floatFromInt((widgets.len -| 1) * config.spacing)));

    var childWidth = if (expandedCount == 0) 0 else totalAvailableWidth / @as(f32, @floatFromInt(expandedCount));
    for (widgets) |widget| {
        if (!widget.container_expanded) {
            const available = if (expandedCount > 0) Size.init(0, 0) else Size.init(totalAvailableWidth, peer.getSize(peer.userdata).height);
            const divider: f32 = if (expandedCount == 0) 1.0 else @floatFromInt(expandedCount);
            const takenWidth = widget.getPreferredSize(available).width / divider;
            if (childWidth >= takenWidth) {
                childWidth -= takenWidth;
            } else {
                childWidth = 0;
            }
        }
    }

    var childX: f32 = 0.0;
    // Child Y is different from 0 only when 'wrapping' property is set to true
    var childY: f32 = 0.0;
    for (widgets, 0..) |widget, i| {
        const isLastWidget = i == widgets.len - 1;
        if (widget.peer) |widgetPeer| {
            const minimumSize = widget.getPreferredSize(Size.init(1, 1));
            if (config.wrapping) {
                if (childX >= peer.getSize(peer.userdata).width - minimumSize.width) {
                    childX = 0;
                    // TODO: largest height of all the row
                    childY += minimumSize.height;
                }
            }

            const available = Size{
                .width = if (widget.container_expanded) childWidth else @max(0, peer.getSize(peer.userdata).width - childX),
                .height = peer.getSize(peer.userdata).height,
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
                    const height = if (config.wrapping) preferred.height else available.height;
                    break :blk Size.intersect(available, Size.init(preferred.width, height));
                } else {
                    break :blk Size.intersect(available, preferred);
                }
            };

            peer.moveResize(
                peer.userdata,
                widgetPeer,
                @intFromFloat(childX),
                @intFromFloat(childY),
                @intFromFloat(size.width),
                @intFromFloat(size.height),
            );
            childX += size.width + if (isLastWidget) 0.0 else spacing;
        }
    }

    var peers = std.ArrayList(backend.PeerType).initCapacity(global_allocator, widgets.len) catch return;
    defer peers.deinit();

    for (widgets) |widget| {
        if (widget.peer) |widget_peer| {
            peers.appendAssumeCapacity(widget_peer);
        }
    }

    // TODO: RTL support
    peer.setTabOrder(peer.userdata, peers.items);
}

/// Positions one item according to the given margins.
pub fn MarginLayout(peer: Callbacks, widgets: []*Widget) void {
    const margin_rect = peer.getLayoutConfig(Rectangle);
    if (widgets.len > 1) {
        std.log.scoped(.capy).warn("Margin container has more than one widget!", .{});
        return;
    }

    if (widgets[0].peer) |widgetPeer| {
        const available = peer.getSize(peer.userdata);
        const left = margin_rect.x();
        const top = margin_rect.y();
        const right = margin_rect.width();
        const bottom = margin_rect.height();

        if (peer.computingPreferredSize) {
            // What to return for computing preferred size
            const preferredSize = widgets[0].getPreferredSize(.{ .width = 0, .height = 0 });
            peer.moveResize(
                peer.userdata,
                widgetPeer,
                @intFromFloat(left),
                @intFromFloat(top),
                @intFromFloat(preferredSize.width + right),
                @intFromFloat(preferredSize.height + bottom),
            );
        } else {
            // What to return for actual layouting
            const preferredSize = widgets[0].getPreferredSize(available);

            //const finalSize = Size.intersect(preferredSize, available);
            _ = preferredSize;
            const finalSize = available;

            //peer.moveResize(peer.userdata, widgetPeer, 0, 0, finalSize.width, finalSize.height);
            peer.moveResize(
                peer.userdata,
                widgetPeer,
                @intFromFloat(left),
                @intFromFloat(top),
                @intFromFloat(@max(0, finalSize.width - left - right)),
                @intFromFloat(@max(0, finalSize.height - top - bottom)),
            );
        }
    }
}

/// Stacks items on top of each other, from the first to the last.
pub fn StackLayout(peer: Callbacks, widgets: []*Widget) void {
    const size = peer.getSize(peer.userdata);
    for (widgets) |widget| {
        if (widget.peer) |widgetPeer| {
            const widgetSize = if (peer.computingPreferredSize) widget.getPreferredSize(peer.availableSize.?) else size;
            peer.moveResize(peer.userdata, widgetPeer, 0, 0, @intFromFloat(widgetSize.width), @intFromFloat(widgetSize.height));
        }
    }
}

pub const GridLayoutConfig = struct {
    pub const LengthUnit = union(enum) {
        fraction: u32,
        pixels: u32,
        auto,
    };

    pub const JustifyContent = enum {
        flow,
        space_between,
        space_around,
        space_evenly,
    };

    pub const Packing = enum {
        forward,
        /// Densely pack the grid, although this might change the order of components.
        dense,
    };

    pub const FlowOrder = enum { row, column };

    template_columns: []const LengthUnit = &.{},
    template_rows: []const LengthUnit = &.{},
    justify_content: JustifyContent = .flow,
    column_spacing: u32 = 0,
    row_spacing: u32 = 0,
    auto_rows: LengthUnit = .auto,
    auto_columns: LengthUnit = .auto,
    packing: Packing = .forward,
    flow_order: FlowOrder = .row,
};

/// Grid layout based on the CSS Grid algorithm
pub fn GridLayout(peer: Callbacks, widgets: []*Widget) void {
    const size = peer.getSize(peer.userdata);

    const GridColumn = struct {
        x: f32,
        width: f32,
    };

    const GridRow = struct {
        y: f32,
        height: f32,
    };

    const MAX_COLUMNS = 10_000;
    const MAX_ROWS = 10_000;

    var columns = std.BoundedArray(GridColumn, MAX_COLUMNS).init(0) catch unreachable;
    var rows = std.BoundedArray(GridRow, MAX_ROWS).init(0) catch unreachable;
    const config = peer.getLayoutConfig(GridLayoutConfig);

    // 1. Columns and rows placement
    if (config.flow_order != .row) {
        std.debug.panic("TODO: column flow order", .{});
    }
    {
        var column_x: f32 = 0;
        var remaining_width: f32 = size.width - @as(f32, @floatFromInt(config.column_spacing * (config.template_columns.len -| 1)));
        var total_fractions: f32 = 0;
        for (config.template_columns) |column_length| {
            switch (column_length) {
                .fraction => |fr| {
                    std.debug.assert(fr != 0);
                    total_fractions += @floatFromInt(fr);
                },
                .pixels => |px| remaining_width -= @floatFromInt(px),
                .auto => std.debug.panic("TODO: implement auto template column", .{}),
            }
        }
        remaining_width = @max(0, remaining_width);

        for (config.template_columns) |column_length| {
            const width: f32 = switch (column_length) {
                .fraction => |fr| @as(f32, @floatFromInt(fr)) * remaining_width / total_fractions,
                .pixels => |px| @floatFromInt(px),
                .auto => 0, // TBD using a two-pass algorithm
            };
            columns.appendAssumeCapacity(.{ .x = column_x, .width = width });
            column_x += width + @as(f32, @floatFromInt(config.column_spacing));
        }
    }
    if (columns.len == 0 and config.flow_order == .row) {
        columns.appendAssumeCapacity(.{ .x = 0, .width = size.width });
    }

    {
        var row_y: f32 = 0;
        var remaining_height: f32 = size.height - @as(f32, @floatFromInt(config.row_spacing * (config.template_rows.len -| 1)));
        var total_fractions: f32 = 0;
        for (config.template_rows) |row_length| {
            switch (row_length) {
                .fraction => |fr| {
                    std.debug.assert(fr != 0);
                    total_fractions += @floatFromInt(fr);
                },
                .pixels => |px| remaining_height -= @floatFromInt(px),
                .auto => std.debug.panic("TODO: implement auto template row", .{}),
            }
        }
        remaining_height = @max(0, remaining_height);

        for (config.template_rows) |row_length| {
            const height: f32 = switch (row_length) {
                .fraction => |fr| @as(f32, @floatFromInt(fr)) * remaining_height / total_fractions,
                .pixels => |px| @floatFromInt(px),
                .auto => 0, // TBD using a two-pass algorithm
            };
            rows.appendAssumeCapacity(.{ .y = row_y, .height = height });
            row_y += height + @as(f32, @floatFromInt(config.row_spacing));
        }
    }
    if (config.justify_content != .flow) {
        std.debug.panic("TODO: non-flow justify content", .{});
    }

    // Assert that columns' X are in ascending order
    std.debug.assert(std.sort.isSorted(GridColumn, columns.constSlice(), {}, struct {
        fn asc(_: void, lhs: GridColumn, rhs: GridColumn) bool {
            return lhs.x < rhs.x;
        }
    }.asc));
    // and rows' Y are in ascending order
    std.debug.assert(std.sort.isSorted(GridRow, rows.constSlice(), {}, struct {
        fn asc(_: void, lhs: GridRow, rhs: GridRow) bool {
            return lhs.y < rhs.y;
        }
    }.asc));

    // If no rows are explicitely defined, then they will be created implicitely by the grid layout.
    // Those are called "implicit rows"
    const add_implicit_rows = rows.len == 0;

    // This list contains for each row, a slice of booleans indicating whether a given spot is
    // taken.
    // For instance, if x is the column index and y is the row index, row_fill_tables.items[y][x]
    // indicates whether the (x,y) spot is filled. The slices are dynamically allocated as otherwise
    // this data structure would take MAX_COLUMNS * MAX_ROWS bytes at least, which can become quite
    // large.
    var row_fill_tables = std.BoundedArray([]bool, MAX_ROWS).init(0) catch unreachable;
    defer for (row_fill_tables.constSlice()) |slice| {
        capy.internal.allocator.free(slice);
    };
    for (0..rows.len) |_| {
        // Add the corresponding row fill table
        const slice = capy.internal.allocator.alloc(bool, columns.len) catch |err| switch (err) {
            error.OutOfMemory => return,
        };
        for (slice) |*filled| filled.* = false;
        // If we're here, we already know there is enough space in row_fill_tables as there
        // was enough in `rows`.
        row_fill_tables.appendAssumeCapacity(slice);
    }

    // 2. Place explicitely positioned elements
    // TODO

    // 3. Place implicitely positioned elements
    if (config.packing != .forward) {
        std.debug.panic("TODO: dense packing", .{});
    }
    var column_index: usize = 0;
    var row_index: usize = 0;
    var widget_index: usize = 0;
    blk: while (widget_index < widgets.len) {
        std.debug.assert(column_index < columns.len);
        if (row_index >= rows.len) {
            if (add_implicit_rows) {
                // For implicit rows, the height is the maximum of the minimum height of the
                // components that will be in the same row
                var row_height: f32 = 0;
                switch (config.auto_rows) {
                    .pixels => |px| row_height = @floatFromInt(px),
                    .fraction => std.debug.panic("TODO: fraction auto rows", .{}),
                    .auto => {
                        for (0..columns.len) |i| {
                            if (widget_index + i < widgets.len) {
                                const widget = widgets[widget_index + i];
                                const widget_size = if (peer.computingPreferredSize) widget.getPreferredSize(peer.availableSize.?) else widget.getPreferredSize(Size.init(0, 0));
                                row_height = @max(row_height, widget_size.height);
                            }
                        }
                    },
                }

                const row_y = blk2: {
                    if (rows.len >= 1) {
                        const last_row = rows.constSlice()[rows.len - 1];
                        break :blk2 last_row.y + last_row.height;
                    } else {
                        break :blk2 0;
                    }
                };
                rows.append(.{ .y = row_y, .height = row_height }) catch |err| switch (err) {
                    // Consider it as if add_implicit_rows was false
                    error.Overflow => break :blk,
                };

                // Add the corresponding row fill table
                const slice = capy.internal.allocator.alloc(bool, columns.len) catch |err| switch (err) {
                    error.OutOfMemory => break :blk,
                };
                for (slice) |*filled| filled.* = false;
                // If we're here, we already know there is enough space in row_fill_tables as there
                // was enough in `rows`.
                row_fill_tables.appendAssumeCapacity(slice);
            } else {
                // Ideally, all subsequent elements should be made as small as possible and put at the
                // end of the grid layout
                break;
            }
        }

        const filled = row_fill_tables.constSlice()[row_index][column_index];
        if (!filled) {
            const grid_column = columns.constSlice()[column_index];
            const grid_row = rows.constSlice()[row_index];
            const widget = widgets[widget_index];
            widget_index += 1;

            // TODO: change based on other properties like align and justify
            if (widget.peer) |widget_peer| {
                peer.moveResize(
                    peer.userdata,
                    widget_peer,
                    @intFromFloat(grid_column.x),
                    @intFromFloat(grid_row.y),
                    @intFromFloat(grid_column.width),
                    @intFromFloat(grid_row.height),
                );
            }
        }

        column_index += 1;
        if (column_index >= columns.len) {
            // Wrap over to the next row
            column_index = 0;
            row_index += 1;
        }
    }

    // For all remaining widgets, set a null size and put them at the bottom
    const widget_y = blk2: {
        if (rows.len >= 1) {
            const last_row = rows.constSlice()[rows.len - 1];
            break :blk2 last_row.y + last_row.height;
        } else {
            break :blk2 0;
        }
    };
    for (widget_index..widgets.len) |i| {
        const widget = widgets[i];
        if (widget.peer) |widget_peer| {
            peer.moveResize(peer.userdata, widget_peer, 0, @intFromFloat(widget_y), 1, 1);
        }
    }

    // 4. Set focus order
    var peers = std.ArrayList(backend.PeerType).initCapacity(global_allocator, widgets.len) catch return;
    defer peers.deinit();

    for (widgets) |widget| {
        if (widget.peer) |widget_peer| {
            peers.appendAssumeCapacity(widget_peer);
        }
    }

    // TODO: RTL support
    peer.setTabOrder(peer.userdata, peers.items);
}

pub const Container = struct {
    pub usingnamespace @import("internal.zig").All(Container);

    peer: ?backend.Container,
    widget_data: Container.WidgetData = .{},
    children: std.ArrayList(*Widget),
    expand: bool,
    relayouting: atomicValue(bool) = atomicValue(bool).init(false),
    layout: Layout,
    layoutConfig: [LAYOUT_CONFIG_SIZE]u8,

    /// The widget associated to this Container
    widget: ?*Widget = null,

    const LAYOUT_CONFIG_SIZE = 64;

    const atomicValue = if (@hasDecl(std.atomic, "Value")) std.atomic.Value else std.atomic.Atomic; // support zig 0.11 as well as current master
    pub fn init(children: std.ArrayList(*Widget), config: GridConfig, layout: Layout, layoutConfig: anytype) !Container {
        const LayoutConfig = @TypeOf(layoutConfig);
        comptime std.debug.assert(@sizeOf(LayoutConfig) <= LAYOUT_CONFIG_SIZE);
        var layoutConfigBytes: [LAYOUT_CONFIG_SIZE]u8 = undefined;
        if (@sizeOf(LayoutConfig) > 0) {
            layoutConfigBytes[0..@sizeOf(LayoutConfig)].* = std.mem.toBytes(layoutConfig);
        }

        var container = Container.init_events(Container{
            .peer = null,
            .children = std.ArrayList(*Widget).init(global_allocator),
            .expand = config.expand == .Fill,
            .layout = layout,
            .layoutConfig = layoutConfigBytes,
        });
        _ = container.setName(config.name);
        try container.addResizeHandler(&onResize);

        for (children.items) |child| {
            try container.add(child);
        }
        children.deinit();
        return container;
    }

    pub fn allocA(children: std.ArrayList(*Widget), config: GridConfig, layout: Layout, layoutConfig: anytype) !*Container {
        const instance = global_allocator.create(Container) catch @panic("out of memory");
        instance.* = try Container.init(children, config, layout, layoutConfig);
        instance.widget_data.widget = @import("internal.zig").genericWidgetFrom(instance);
        return instance;
    }

    pub fn onResize(self: *Container, size: Size) !void {
        _ = size;
        self.relayout();
    }

    /// Returns the *n*-th child of the container, starting from 0. If n is too big
    /// for the component, the function returns `error.OutOfBounds`.
    pub fn getChildAt(self: *Container, index: usize) !*Widget {
        if (index >= self.children.items.len) return error.OutOfBounds;
        return self.children.items[index];
    }

    test getChildAt {
        const c = capy.button(.{ .label = "C" });
        c.ref();
        defer c.unref();

        const container = try capy.row(.{}, .{
            capy.button(.{ .label = "A" }),
            capy.button(.{ .label = "B" }),
            c,
        });
        container.ref();
        defer container.unref();

        const child = container.getChildAt(2) catch unreachable;
        // Check that 'child' holds a pointer to capy.Button(.{ .label = "C" })
        std.debug.assert(child == c.asWidget());
    }

    /// Searches recursively for a component named `name` and returns the first one found.
    /// If no component is found, `null` is returned.
    pub fn getChild(self: *Container, name: []const u8) ?*Widget {
        // TODO: use hash map (maybe acting as cache?) for performance
        for (self.children.items) |widget| {
            if (widget.name.*.get()) |widgetName| {
                if (std.mem.eql(u8, name, widgetName)) {
                    return widget;
                }
            }

            if (widget.cast(Container)) |container| {
                //return container.getChild(name) orelse continue;

                // workaround a stage2 bug
                // TODO: reduce to a unit test and report to ziglang/zig
                const function = getChild;
                return function(container, name) orelse continue;
            } else if (widget.cast(@import("components/Alignment.zig").Alignment)) |component| {
                return component.getChild(name) orelse continue;
            }
        }
        return null;
    }

    test getChild {
        const check_box = capy.checkBox(.{ .name = "me" });
        check_box.ref();
        defer check_box.unref();

        const container = try capy.column(.{}, .{
            check_box,
        });
        container.ref();
        defer container.unref();

        // In Zig, '.?' is equivalent to 'orelse unreachable'
        const child = container.getChild("me").?;
        // Check that 'child' holds a pointer to capy.checkBox(.{ .name = "me" })
        std.debug.assert(child == check_box.asWidget());
    }

    /// This function is a shorthand that is equivalent to
    /// ```
    /// container.getChild(name).as(T)
    /// ```
    pub fn getChildAs(self: *Container, comptime T: type, name: []const u8) ?*T {
        if (self.getChild(name)) |widget| {
            return widget.as(T);
        } else {
            return null;
        }
    }

    pub fn getPreferredSize(self: *Container, available: Size) Size {
        var size: Size = Size{ .width = 0, .height = 0 };
        const callbacks = Callbacks{
            .userdata = @intFromPtr(&size),
            .moveResize = fakeResMove,
            .getSize = fakeSize,
            .computingPreferredSize = true,
            .availableSize = available,
            .layoutConfig = self.layoutConfig,
            .setTabOrder = fakeSetTabOrder,
        };
        self.layout(callbacks, self.children.items);
        return size;
    }

    pub fn show(self: *Container) !void {
        if (self.peer == null) {
            _ = try self.widget_data.atoms.animation_controller.addChangeListener(.{ .function = onAnimationControllerChange, .userdata = self });
            // Trigger the onAnimationControllerChange function now so that the current animation
            // controller propagates to children
            onAnimationControllerChange(self.widget_data.atoms.animation_controller.get(), self);

            var peer = try backend.Container.create();
            for (self.children.items) |widget| {
                try widget.show();
                peer.add(widget.peer.?);
            }
            self.peer = peer;
            try self.setupEvents();
            self.relayout();
        }
    }

    pub fn _showWidget(widget: *Widget, self: *Container) !void {
        self.widget = widget;
        for (self.children.items) |child| {
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
        const size = @as(*Size, @ptrFromInt(data));
        _ = widget;
        size.width = @max(size.width, @as(f32, @floatFromInt(x + w)));
        size.height = @max(size.height, @as(f32, @floatFromInt(y + h)));
    }

    fn fakeSetTabOrder(data: usize, widgets: []const backend.PeerType) void {
        _ = data;
        _ = widgets;
    }

    fn getSize(data: usize) Size {
        const peer = @as(*backend.Container, @ptrFromInt(data));
        return Size{ .width = @floatFromInt(peer.getWidth()), .height = @floatFromInt(peer.getHeight()) };
    }

    fn moveResize(data: usize, widget: backend.PeerType, x: u32, y: u32, w: u32, h: u32) void {
        @as(*backend.Container, @ptrFromInt(data)).move(widget, x, y);
        @as(*backend.Container, @ptrFromInt(data)).resize(widget, w, h);
    }

    fn setTabOrder(data: usize, widgets: []const backend.PeerType) void {
        @as(*backend.Container, @ptrFromInt(data)).setTabOrder(widgets);
    }

    /// Forces the container to re-layout: the layouter will be called and children will be
    /// repositioned and resized.
    /// It shouldn't need to be called as all functions that affect a child's position should also
    /// trigger a relayout. If it doesn't please [file an issue](https://github.com/capy-ui/capy/issues).
    pub fn relayout(self: *Container) void {
        if (self.relayouting.load(.seq_cst) == true) return;
        if (self.peer) |peer| {
            self.relayouting.store(true, .seq_cst);
            const callbacks = Callbacks{
                .userdata = @intFromPtr(&peer),
                .moveResize = moveResize,
                .getSize = getSize,
                .computingPreferredSize = false,
                .layoutConfig = self.layoutConfig,
                .setTabOrder = setTabOrder,
            };

            var tempItems = std.ArrayList(*Widget).init(self.children.allocator);
            defer tempItems.deinit();
            for (self.children.items) |child| {
                if (child.isDisplayed()) {
                    tempItems.append(child) catch return;
                } else {
                    peer.remove(child.peer.?);
                }
            }

            self.layout(callbacks, tempItems.items);
            self.relayouting.store(false, .seq_cst);
        }
    }

    pub fn autoAnimate(self: *Container, transitionFunc: *const fn (*Container) void) !void {
        _ = transitionFunc;
        const self_clone = try self.clone();
        _ = self_clone;
    }

    /// Adds the given component to the container.
    pub fn add(self: *Container, widget: anytype) !void {
        const ComponentType = @import("internal.zig").DereferencedType(@TypeOf(widget));
        _ = ComponentType;

        var genericWidget = @import("internal.zig").getWidgetFrom(widget);
        if (self.expand) {
            genericWidget.container_expanded = true;
        }

        genericWidget.parent = self.asWidget();
        genericWidget.animation_controller.set(self.widget_data.atoms.animation_controller.get());
        genericWidget.ref();
        try self.children.append(genericWidget);

        if (self.peer) |*peer| {
            try genericWidget.show();
            peer.add(genericWidget.peer.?);
        }

        self.relayout();
    }

    test add {
        const container = try capy.row(.{}, .{});
        container.ref();
        defer container.unref();

        try container.add(
            capy.button(.{ .label = "Hello, World!" }),
        );
    }

    /// Removes the component at the given index. In other words, removes the component that would
    /// have otherwise been returned by `getChildAt()`.
    pub fn removeByIndex(self: *Container, index: usize) void {
        const widget = self.children.orderedRemove(index);
        // Remove from the component
        if (self.peer) |*peer| {
            peer.remove(widget.peer.?);
        }
        widget.unref();
        // Relayout to apply changes
        self.relayout();
    }

    /// Removes all children from the container.
    pub fn removeAll(self: *Container) void {
        while (self.children.items.len > 0) {
            self.removeByIndex(0);
        }
    }

    pub fn _deinit(self: *Container) void {
        for (self.children.items) |child| {
            child.unref();
        }
        self.children.deinit();
    }

    fn onAnimationControllerChange(newValue: *AnimationController, userdata: ?*anyopaque) void {
        const self: *Container = @ptrCast(@alignCast(userdata));
        for (self.children.items) |child| {
            child.animation_controller.set(newValue);
        }
    }

    pub fn cloneImpl(self: *Container) !*Container {
        _ = self;
        // var children = std.ArrayList(Widget).init(global_allocator);
        // for (self.children.items) |child| {
        // const child_clone = try child.clone();
        // try children.append(child_clone);
        // }
        return undefined;

        // const clone = try Container.init(children, .{ .expand = if (self.expand) .Fill else .No }, self.layout, self.layoutConfig);
        // return try clone.asWidget();
    }
};

test Container {
    const container_row = try capy.row(.{}, .{
        capy.button(.{ .label = "hello!" }),
    });
    container_row.ref();
    defer container_row.unref();

    const container_column = try capy.column(.{}, .{
        capy.label(.{ .text = "hi!" }),
    });
    container_column.ref();
    defer container_column.unref();
}

const Expand = enum {
    /// Each child is given its minimum size.
    No,
    /// All children act like they're expanded, that is they take as much space as they can.
    Fill,
};

pub const GridConfig = struct {
    expand: Expand = .No,
    name: ?[]const u8 = null,
    /// How much spacing (in pixels) should be put between elements.
    spacing: u32 = 5,
    /// Should the Container wrap when there are too many elements?
    wrapping: bool = false,
};

/// Set the style of the child to expanded by creating and showing the widget early.
pub inline fn expanded(child: anytype) anyerror!*Widget {
    var widget = @import("internal.zig").getWidgetFrom(if (comptime isErrorUnion(@TypeOf(child)))
        try child
    else
        child);
    widget.container_expanded = true;
    return widget;
}

/// Creates a Container which uses `StackLayout` as layout.
pub inline fn stack(children: anytype) anyerror!*Container {
    return try Container.allocA(try convertTupleToWidgets(children), .{}, StackLayout, {});
}

/// Creates a Container which uses `RowLayout` as layout.
pub inline fn row(config: GridConfig, children: anytype) anyerror!*Container {
    return try Container.allocA(try convertTupleToWidgets(children), config, RowLayout, ColumnRowConfig{ .spacing = config.spacing, .wrapping = config.wrapping });
}

/// Creates a Container which uses `ColumnLayout` as layout.
/// `ColumnLayout` arranges items vertically.
pub inline fn column(config: GridConfig, children: anytype) anyerror!*Container {
    return try Container.allocA(try convertTupleToWidgets(children), config, ColumnLayout, ColumnRowConfig{ .spacing = config.spacing, .wrapping = config.wrapping });
}

/// Creates a Container which uses `MarginLayout` as layout, with the given margins.
pub inline fn margin(margin_rect: Rectangle, child: anytype) anyerror!*Container {
    return try Container.allocA(try convertTupleToWidgets(.{child}), .{}, MarginLayout, margin_rect);
}

pub fn grid(config: GridLayoutConfig, children: anytype) anyerror!*Container {
    return try Container.allocA(try convertTupleToWidgets(children), .{}, GridLayout, config);
}
