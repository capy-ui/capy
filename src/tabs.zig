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
    tabs: std.ArrayList(Tab_Impl),

    /// The widget associated to this Tabs_Impl
    widget: ?*Widget = null,

    pub fn init(tabs: std.ArrayList(Tab_Impl)) Tabs_Impl {
        return Tabs_Impl.init_events(Tabs_Impl{ .tabs = tabs });
    }

    pub fn show(self: *Tabs_Impl) !void {
        if (self.peer == null) {
            var peer = try backend.TabContainer.create();
            for (self.tabs.items) |*tab| {
                try tab.widget.show();
                const tabPosition = peer.insert(peer.getTabsNumber(), tab.widget.peer.?);
                peer.setLabel(tabPosition, tab.label);
            }
            self.peer = peer;
            try self.show_events();
        }
    }

    pub fn getPreferredSize(self: *Tabs_Impl, available: Size) Size {
        _ = self;
        _ = available;
        return Size.init(0, 0); // TODO
    }

    pub fn _showWidget(widget: *Widget, self: *Tabs_Impl) !void {
        self.widget = widget;
        for (self.tabs.items) |*child| {
            child.widget.parent = widget;
        }
    }

    pub fn add(self: *Tabs_Impl, widget: anytype) !void {
        const ComponentType = @import("internal.zig").DereferencedType(@TypeOf(widget));

        var genericWidget = try @import("internal.zig").genericWidgetFrom(widget);
        if (self.widget) |parent| {
            genericWidget.parent = parent;
        }

        const slot = try self.tab.addOne();
        slot.* = .{ .label = "Untitled Tab", .widget = genericWidget };
        if (@hasField(ComponentType, "dataWrappers")) {
            genericWidget.as(ComponentType).dataWrappers.widget = slot;
        }

        if (self.peer) |*peer| {
            try slot.show();
            peer.insert(peer.getTabsNumber(), slot.peer.?);
        }
    }

    pub fn _deinit(self: *Tabs_Impl, _: *Widget) void {
        for (self.tabs.items) |*tab| {
            tab.widget.deinit();
        }
        self.tabs.deinit();
    }
};

fn isErrorUnion(comptime T: type) bool {
    return switch (@typeInfo(T)) {
        .ErrorUnion => true,
        else => false,
    };
}

pub inline fn Tabs(children: anytype) anyerror!Tabs_Impl {
    const fields = std.meta.fields(@TypeOf(children));
    var list = std.ArrayList(Tab_Impl).init(@import("internal.zig").lasting_allocator);
    inline for (fields) |field| {
        const element = @field(children, field.name);
        const tab =
            if (comptime isErrorUnion(@TypeOf(element))) // if it is an error union, unwrap it
            try element
        else
            element;
        const slot = try list.addOne();
        slot.* = tab;
        slot.*.widget.class.setWidgetFn(&slot.*.widget);
    }
    return Tabs_Impl.init(list);
}

pub const Tab_Impl = struct {
    label: [:0]const u8,
    widget: Widget,
};

pub const TabConfig = struct {
    label: [:0]const u8 = "",
};

pub inline fn Tab(config: TabConfig, child: anytype) anyerror!Tab_Impl {
    const widget = try @import("internal.zig").genericWidgetFrom(if (comptime isErrorUnion(@TypeOf(child)))
        try child
    else
        child);
    return Tab_Impl{
        .label = config.label,
        .widget = widget,
    };
}
