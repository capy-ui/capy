const std = @import("std");
const backend = @import("../backend.zig");
const Size = @import("../data.zig").Size;
const DataWrapper = @import("../data.zig").DataWrapper;
const Widget = @import("../widget.zig").Widget;

pub const Scrollable_Impl = struct {
    pub usingnamespace @import("../internal.zig").All(Scrollable_Impl);

    peer: ?backend.ScrollView = null,
    handlers: Scrollable_Impl.Handlers = undefined,
    dataWrappers: Scrollable_Impl.DataWrappers = .{},
    child: Widget,

    pub fn init(widget: Widget) Scrollable_Impl {
        return Scrollable_Impl.init_events(Scrollable_Impl{ .child = widget });
    }

    pub fn show(self: *Scrollable_Impl) !void {
        if (self.peer == null) {
            var peer = try backend.ScrollView.create();
            try self.child.show();
            peer.setChild(self.child.peer.?, &self.child);
            self.peer = peer;
            try self.show_events();
        }
    }

    pub fn getPreferredSize(self: *Scrollable_Impl, available: Size) Size {
        return self.child.getPreferredSize(available);
    }
};

pub fn Scrollable(element: anytype) anyerror!Scrollable_Impl {
    const child =
        if (comptime @import("../internal.zig").isErrorUnion(@TypeOf(element)))
        try element
    else
        element;
    const widget = try @import("../internal.zig").genericWidgetFrom(child);

    return Scrollable_Impl.init(widget);
}
