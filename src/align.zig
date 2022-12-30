const std = @import("std");
const backend = @import("backend.zig");
const internal = @import("internal.zig");
const Size = @import("data.zig").Size;
const DataWrapper = @import("data.zig").DataWrapper;
const Widget = @import("widget.zig").Widget;

pub const Align_Impl = struct {
    pub usingnamespace @import("internal.zig").All(Align_Impl);

    peer: ?backend.Container = null,
    handlers: Align_Impl.Handlers = undefined,
    dataWrappers: Align_Impl.DataWrappers = .{},

    child: Widget,
	relayouting: std.atomic.Atomic(bool) = std.atomic.Atomic(bool).init(false),
	x: DataWrapper(f32) = DataWrapper(f32).of(0.5),
	y: DataWrapper(f32) = DataWrapper(f32).of(0.5),

    pub fn init(config: Align_Impl.Config, widget: Widget) !Align_Impl {
        var component = Align_Impl.init_events(Align_Impl{ .child = widget });
		component.x.set(config.x);
		component.y.set(config.y);
        try component.addResizeHandler(&onResize);

		return component;
    }

	pub fn onResize(self: *Align_Impl, _: Size) !void {
        self.relayout();
    }

    pub fn _showWidget(widget: *Widget, self: *Align_Impl) !void {
        self.child.parent = widget.parent;
        self.child.class.setWidgetFn(&self.child);
    }

    pub fn show(self: *Align_Impl) !void {
        if (self.peer == null) {
            var peer = try backend.Container.create();
            self.peer = peer;

            self.child.class.setWidgetFn(&self.child);
            try self.child.show();
			peer.add(self.child.peer.?);

            try self.show_events();
        }
    }

    pub fn relayout(self: *Align_Impl) void {
        if (self.relayouting.load(.SeqCst) == true) return;
        if (self.peer) |peer| {
            self.relayouting.store(true, .SeqCst);
            defer self.relayouting.store(false, .SeqCst);

        	const available = Size{ .width = @intCast(u32, peer.getWidth()), .height = @intCast(u32, peer.getHeight()) };
			
			const alignX = self.x.get();
			const alignY = self.y.get();

			if (self.child.peer) |widgetPeer| {
				const preferredSize = self.child.getPreferredSize(available);
				const finalSize = Size.intersect(preferredSize, available);

				const x = @floatToInt(u32, alignX * @intToFloat(f32, available.width -| finalSize.width));
				const y = @floatToInt(u32, alignY * @intToFloat(f32, available.height -| finalSize.height));

				peer.move(widgetPeer, x, y);
				peer.resize(widgetPeer, finalSize.width, finalSize.height);
			}
        }
    }

    pub fn getPreferredSize(self: *Align_Impl, available: Size) Size {
        return self.child.getPreferredSize(available);
    }

    pub fn _deinit(self: *Align_Impl) void {
		self.child.deinit();
    }
};

pub fn Align(opts: Align_Impl.Config, child: anytype) anyerror!Align_Impl {
	const element =
		if (comptime internal.isErrorUnion(@TypeOf(child)))
		try child
	else
		child;

    const widget = try internal.genericWidgetFrom(element);
	return try Align_Impl.init(opts, widget);
}
