const std = @import("std");
const backend = @import("backend.zig");
const Size = @import("data.zig").Size;
const DataWrapper = @import("data.zig").DataWrapper;
const Widget = @import("widget.zig").Widget;

pub const Tabs_Impl = struct {
    pub usingnamespace @import("internal.zig").All(Tabs_Impl);

    peer: ?backend.TabContainer = null,
    handlers: Tabs_Impl.Handlers = undefined,
    dataWrappers: Tabs_Impl.DataWrappers = .{},
    childrens: std.ArrayList(Widget),
	
    /// The widget associated to this Tabs_Impl
    widget: ?*Widget = null,

    pub fn init(widget: Widget) Tabs_Impl {
        return Tabs_Impl.init_events(Tabs_Impl{});
    }

    pub fn show(self: *Tabs_Impl) !void {
        if (self.peer == null) {
            var peer = try backend.TabContainer.create();
            for (self.childrens.items) |*widget| {
                try widget.show();
                peer.add(widget.peer.?);
            }
            self.peer = peer;
            try self.show_events();
        }
    }

    pub fn getPreferredSize(self: *Tabs_Impl, available: Size) Size {
        return Size.init(0, 0); // TODO
    }

	pub fn add(self: *Tabs_Impl, widget: anytype) !void {
        const ComponentType = @import("internal.zig").DereferencedType(@TypeOf(widget));

        var genericWidget = try @import("internal.zig").genericWidgetFrom(widget);
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
            peer.insert(peer.getTabsNumber(), slot.peer.?);
        }
    }


    pub fn _deinit(self: *Tabs_Impl, _: *Widget) void {
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

pub fn Tabs(element: anytype) anyerror!Tabs_Impl {
    const child =
            if (comptime isErrorUnion(@TypeOf(element)))
            try element
        else
            element;
    const widget = try @import("internal.zig").genericWidgetFrom(child);

    return Tabs_Impl.init(widget);
}
