const std = @import("std");
const backend = @import("../backend.zig");
const internal = @import("../internal.zig");
const Size = @import("../data.zig").Size;
const Atom = @import("../data.zig").Atom;
const Widget = @import("../widget.zig").Widget;

pub const Alignment = struct {
    pub usingnamespace @import("../internal.zig").All(Alignment);

    peer: ?backend.Container = null,
    widget_data: Alignment.WidgetData = .{},

    child: *Widget,
    relayouting: std.atomic.Value(bool) = std.atomic.Value(bool).init(false),
    x: Atom(f32) = Atom(f32).of(0.5),
    y: Atom(f32) = Atom(f32).of(0.5),

    pub fn init(config: Alignment.Config, widget: *Widget) !Alignment {
        var component = Alignment.init_events(Alignment{ .child = widget });
        internal.applyConfigStruct(&component, config);
        try component.addResizeHandler(&onResize);
        widget.ref();

        return component;
    }

    fn onResize(self: *Alignment, _: Size) !void {
        self.relayout();
    }

    pub fn getChild(self: *Alignment, name: []const u8) ?*Widget {
        if (self.child.name.*.get()) |child_name| {
            if (std.mem.eql(u8, child_name, name)) {
                return self.child;
            }
        }
        return null;
    }

    /// When alignX or alignY is changed, this will trigger a parent relayout
    fn alignChanged(_: f32, userdata: ?*anyopaque) void {
        const self: *Alignment = @ptrCast(@alignCast(userdata));
        self.relayout();
    }

    pub fn _showWidget(widget: *Widget, self: *Alignment) !void {
        self.child.parent = widget;
    }

    pub fn show(self: *Alignment) !void {
        if (self.peer == null) {
            var peer = try backend.Container.create();
            self.peer = peer;

            _ = try self.x.addChangeListener(.{ .function = alignChanged, .userdata = self });
            _ = try self.y.addChangeListener(.{ .function = alignChanged, .userdata = self });

            try self.child.show();
            peer.add(self.child.peer.?);

            try self.setupEvents();
        }
    }

    pub fn relayout(self: *Alignment) void {
        if (self.relayouting.load(.SeqCst) == true) return;
        if (self.peer) |peer| {
            self.relayouting.store(true, .SeqCst);
            defer self.relayouting.store(false, .SeqCst);

            const available = Size{ .width = @as(u32, @intCast(peer.getWidth())), .height = @as(u32, @intCast(peer.getHeight())) };

            const alignX = self.x.get();
            const alignY = self.y.get();

            if (self.child.peer) |widgetPeer| {
                const preferredSize = self.child.getPreferredSize(available);
                const finalSize = Size.intersect(preferredSize, available);

                const x = @as(u32, @intFromFloat(alignX * @as(f32, @floatFromInt(available.width -| finalSize.width))));
                const y = @as(u32, @intFromFloat(alignY * @as(f32, @floatFromInt(available.height -| finalSize.height))));

                peer.move(widgetPeer, x, y);
                peer.resize(widgetPeer, finalSize.width, finalSize.height);
            }
        }
    }

    pub fn getPreferredSize(self: *Alignment, available: Size) Size {
        return self.child.getPreferredSize(available);
    }

    pub fn cloneImpl(self: *Alignment) !*Alignment {
        const widget_clone = try self.child.clone();
        const ptr = try internal.lasting_allocator.create(Alignment);
        const component = try Alignment.init(.{ .x = self.x.get(), .y = self.y.get() }, widget_clone);
        ptr.* = component;
        return ptr;
    }

    pub fn _deinit(self: *Alignment) void {
        self.child.unref();
    }
};

pub fn alignment(opts: Alignment.Config, child: anytype) anyerror!*Alignment {
    const element =
        if (comptime internal.isErrorUnion(@TypeOf(child)))
        try child
    else
        child;

    const widget = internal.getWidgetFrom(element);
    const instance = internal.lasting_allocator.create(Alignment) catch @panic("out of memory");
    instance.* = try Alignment.init(opts, widget);
    instance.widget_data.widget = internal.genericWidgetFrom(instance);
    return instance;
}
