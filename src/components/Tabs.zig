const std = @import("std");
const backend = @import("../backend.zig");
const Size = @import("../data.zig").Size;
const Atom = @import("../data.zig").Atom;
const Widget = @import("../widget.zig").Widget;

pub const Tabs = struct {
    pub usingnamespace @import("../internal.zig").All(Tabs);

    peer: ?backend.TabContainer = null,
    widget_data: Tabs.WidgetData = .{},
    tabs: std.ArrayList(Tab),

    /// The widget associated to this Tabs
    widget: ?*Widget = null,

    pub fn init(tabs_list: std.ArrayList(Tab)) Tabs {
        return Tabs.init_events(Tabs{ .tabs = tabs_list });
    }

    pub fn show(self: *Tabs) !void {
        if (self.peer == null) {
            var peer = try backend.TabContainer.create();
            for (self.tabs.items) |*tab_ptr| {
                try tab_ptr.widget.show();
                const tabPosition = peer.insert(peer.getTabsNumber(), tab_ptr.widget.peer.?);
                peer.setLabel(tabPosition, tab_ptr.label);
            }
            self.peer = peer;
            try self.show_events();
        }
    }

    pub fn getPreferredSize(self: *Tabs, available: Size) Size {
        _ = self;
        return available; // TODO
    }

    pub fn _showWidget(widget: *Widget, self: *Tabs) !void {
        self.widget = widget;
        for (self.tabs.items) |*child| {
            child.widget.parent = widget;
        }
    }

    pub fn add(self: *Tabs, widget: anytype) !void {
        const ComponentType = @import("../internal.zig").DereferencedType(@TypeOf(widget));

        var genericWidget = try @import("../internal.zig").genericWidgetFrom(widget);
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

    pub fn _deinit(self: *Tabs) void {
        for (self.tabs.items) |*tab_ptr| {
            tab_ptr.widget.deinit();
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

pub inline fn tabs(children: anytype) anyerror!Tabs {
    const fields = std.meta.fields(@TypeOf(children));
    var list = std.ArrayList(Tab).init(@import("../internal.zig").lasting_allocator);
    inline for (fields) |field| {
        const element = @field(children, field.name);
        const tab1 =
            if (comptime isErrorUnion(@TypeOf(element))) // if it is an error union, unwrap it
            try element
        else
            element;
        const slot = try list.addOne();
        slot.* = tab1;
        slot.*.widget.class.setWidgetFn(&slot.*.widget);
    }
    return Tabs.init(list);
}

pub const Tab = struct {
    label: [:0]const u8,
    widget: Widget,
};

pub const TabConfig = struct {
    label: [:0]const u8 = "",
};

pub inline fn tab(config: TabConfig, child: anytype) anyerror!Tab {
    const widget = try @import("../internal.zig").genericWidgetFrom(if (comptime isErrorUnion(@TypeOf(child)))
        try child
    else
        child);
    return Tab{
        .label = config.label,
        .widget = widget,
    };
}
