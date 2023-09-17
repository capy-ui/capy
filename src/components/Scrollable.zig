const std = @import("std");
const backend = @import("../backend.zig");
const Size = @import("../data.zig").Size;
const DataWrapper = @import("../data.zig").DataWrapper;
const Widget = @import("../widget.zig").Widget;

pub const Scrollable = struct {
    pub usingnamespace @import("../internal.zig").All(Scrollable);

    peer: ?backend.ScrollView = null,
    widget_data: Scrollable.WidgetData = .{},
    child: Widget,

    pub fn init(widget: Widget) Scrollable {
        return Scrollable.init_events(Scrollable{ .child = widget });
    }

    pub fn show(self: *Scrollable) !void {
        if (self.peer == null) {
            var peer = try backend.ScrollView.create();
            try self.child.show();
            peer.setChild(self.child.peer.?, &self.child);
            self.peer = peer;
            try self.show_events();
        }
    }

    pub fn getPreferredSize(self: *Scrollable, available: Size) Size {
        return self.child.getPreferredSize(available);
    }
};

pub fn scrollable(element: anytype) anyerror!Scrollable {
    const child =
        if (comptime @import("../internal.zig").isErrorUnion(@TypeOf(element)))
        try element
    else
        element;
    const widget = try @import("../internal.zig").genericWidgetFrom(child);

    return Scrollable.init(widget);
}
