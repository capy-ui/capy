const std = @import("std");
const backend = @import("../backend.zig");
const Size = @import("../data.zig").Size;
const Atom = @import("../data.zig").Atom;
const Widget = @import("../widget.zig").Widget;

pub const Scrollable = struct {
    pub usingnamespace @import("../internal.zig").All(Scrollable);

    peer: ?backend.ScrollView = null,
    widget_data: Scrollable.WidgetData = .{},
    child: Atom(*Widget),

    pub fn init(config: Scrollable.Config) Scrollable {
        var component = Scrollable.init_events(Scrollable{ .child = Atom(*Widget).of(config.child) });
        @import("../internal.zig").applyConfigStruct(&component, config);
        return component;
    }

    // TODO: handle child change

    pub fn show(self: *Scrollable) !void {
        if (self.peer == null) {
            var peer = try backend.ScrollView.create();
            try self.child.get().show();
            peer.setChild(self.child.get().peer.?, self.child.get());
            self.peer = peer;
            try self.setupEvents();
        }
    }

    pub fn getPreferredSize(self: *Scrollable, available: Size) Size {
        return self.child.get().getPreferredSize(available);
    }

    pub fn _deinit(self: *Scrollable) void {
        self.child.get().unref();
    }
};

pub fn scrollable(element: anytype) anyerror!*Scrollable {
    const child =
        if (comptime @import("../internal.zig").isErrorUnion(@TypeOf(element)))
            try element
        else
            element;
    const widget = @import("../internal.zig").getWidgetFrom(child);
    return Scrollable.alloc(.{ .child = widget });
}
