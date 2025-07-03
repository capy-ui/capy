const std = @import("std");
const backend = @import("../backend.zig");
const Size = @import("../data.zig").Size;
const Atom = @import("../data.zig").Atom;
const Widget = @import("../widget.zig").Widget;
const isErrorUnion = @import("../internal.zig").isErrorUnion;

pub const Tabs = struct {
    pub usingnamespace @import("../internal.zig").All(Tabs);

    peer: ?backend.TabContainer = null,
    widget_data: Tabs.WidgetData = .{},
    tabs: Atom(std.ArrayList(Tab)),

    /// The widget associated to this Tabs
    widget: ?*Widget = null,

    pub fn init(config: Tabs.Config) Tabs {
        return Tabs.init_events(Tabs{ .tabs = Atom(std.ArrayList(Tab)).of(config.tabs) });
    }

    pub fn show(self: *Tabs) !void {
        if (self.peer == null) {
            var peer = try backend.TabContainer.create();
            for (self.tabs.get().items) |*tab_ptr| {
                try tab_ptr.widget.show();
                const tabPosition = peer.insert(peer.getTabsNumber(), tab_ptr.widget.peer.?);
                peer.setLabel(tabPosition, tab_ptr.label);
            }
            self.peer = peer;
            try self.setupEvents();
        }
    }

    pub fn getPreferredSize(self: *Tabs, available: Size) Size {
        _ = self;
        return available; // TODO
    }

    pub fn _showWidget(widget: *Widget, self: *Tabs) !void {
        self.widget = widget;
        for (self.tabs.get().items) |*child| {
            child.widget.parent = widget;
        }
    }

    pub fn add(self: *Tabs, widget: anytype) !void {
        var genericWidget = @import("../internal.zig").getWidgetFrom(widget);
        genericWidget.ref();
        if (self.widget) |parent| {
            genericWidget.parent = parent;
        }

        const slot = try self.tab.addOne();
        slot.* = .{ .label = "Untitled Tab", .widget = genericWidget };

        if (self.peer) |*peer| {
            try slot.show();
            peer.insert(peer.getTabsNumber(), slot.peer.?);
        }
    }

    pub fn _deinit(self: *Tabs) void {
        for (self.tabs.get().items) |*tab_ptr| {
            tab_ptr.widget.unref();
        }
        self.tabs.get().deinit();
    }
};

pub inline fn tabs(children: anytype) anyerror!*Tabs {
    const fields = std.meta.fields(@TypeOf(children));
    var list = std.ArrayList(Tab).init(@import("../internal.zig").allocator);
    inline for (fields) |field| {
        const element = @field(children, field.name);
        const tab1 =
            if (comptime isErrorUnion(@TypeOf(element))) // if it is an error union, unwrap it
                try element
            else
                element;
        tab1.widget.ref();
        const slot = try list.addOne();
        slot.* = tab1;
    }

    const instance = @import("../internal.zig").allocator.create(Tabs) catch @panic("out of memory");
    instance.* = Tabs.init(.{ .tabs = list });
    instance.widget_data.widget = @import("../internal.zig").genericWidgetFrom(instance);
    return instance;
}

pub const Tab = struct {
    label: [:0]const u8,
    widget: *Widget,
};

pub const TabConfig = struct {
    label: [:0]const u8 = "",
};

pub inline fn tab(config: TabConfig, child: anytype) anyerror!Tab {
    const widget = @import("../internal.zig").getWidgetFrom(if (comptime isErrorUnion(@TypeOf(child)))
        try child
    else
        child);
    return Tab{
        .label = config.label,
        .widget = widget,
    };
}
