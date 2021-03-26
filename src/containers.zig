const std = @import("std");
const backend = @import("backend.zig");
const Widget = @import("widget.zig").Widget;
usingnamespace @import("internal.zig");

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

const Row_Impl = struct {
    peer: ?backend.Row,
    childrens: std.ArrayList(Widget),
    expand: bool,

    pub fn init(childrens: std.ArrayList(Widget), config: GridConfig) !Row_Impl {
        return Row_Impl {
            .peer = null,
            .childrens = childrens,
            .expand = config.expand == .Fill
        };
    }

    pub fn show(self: *Row_Impl) !void {
        if (self.peer == null) {
            var peer = try backend.Row.create();
            peer.expand = self.expand;
            for (self.childrens.items) |widget| {
                // TODO: use comptime vtable to show widgets
                peer.add(widget.peer, widget.container_expanded);
            }
            self.peer = peer;
        }
    }

    pub fn add(self: *Row_Impl, widget: anytype) !void {
        const allocator = self.childrens.allocator;
        const genericWidget = genericWidgetFrom(widget);

        if (self.peer) |*peer| {
            peer.add(genericWidget.peer, genericWidget.container_expanded);
        }

        try self.childrens.append(genericWidget);
    }
};

const Column_Impl = struct {
    peer: ?backend.Column,
    childrens: std.ArrayList(Widget),
    expand: bool,

    pub fn init(childrens: std.ArrayList(Widget), config: GridConfig) !Column_Impl {
        return Column_Impl {
            .peer = null,
            .childrens = childrens,
            .expand = config.expand == .Fill
        };
    }

    pub fn show(self: *Column_Impl) !void {
        if (self.peer == null) {
            var peer = try backend.Column.create();
            peer.expand = self.expand;
            for (self.childrens.items) |widget| {
                // TODO: use comptime vtable to show widgets
                peer.add(widget.peer, widget.container_expanded);
            }
            self.peer = peer;
        }
    }

    pub fn add(self: *Column_Impl, widget: anytype) !void {
        const allocator = self.childrens.allocator;
        const genericWidget = genericWidgetFrom(widget);

        if (self.peer) |*peer| {
            peer.add(genericWidget.peer, genericWidget.container_expanded);
        }

        try self.childrens.append(genericWidget);
    }
};

/// Create a generic Widget struct from the given component.
fn genericWidgetFrom(component: anytype) !Widget {
    const componentType = @TypeOf(component);
    if (componentType == Widget) return component;

    var cp = if (comptime std.meta.trait.isSingleItemPtr(componentType)) component else blk: {
        var copy = try lasting_allocator.create(componentType);
        copy.* = component;
        break :blk copy;
    };
    try cp.show();

    return Widget { .data = @ptrToInt(cp), .peer = cp.peer.?.peer };
}

fn isErrorUnion(comptime T: type) bool {
    return switch (@typeInfo(T)) {
        .ErrorUnion => true,
        else => false
    };
}

fn abstractContainerConstructor(comptime T: type, childrens: anytype, config: anytype) anyerror!T {
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

    return try T.init(list, config);
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

pub fn Row(config: GridConfig, childrens: anytype) callconv(.Inline) anyerror!Row_Impl {
    return try abstractContainerConstructor(Row_Impl, childrens, config);
}

pub fn Column(config: GridConfig, childrens: anytype) callconv(.Inline) anyerror!Column_Impl {
    return try abstractContainerConstructor(Column_Impl, childrens, config);
}
