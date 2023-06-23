// TODO: rename to foreach?
const std = @import("std");
const backend = @import("backend.zig");
const Widget = @import("widget.zig").Widget;
const lasting_allocator = @import("internal.zig").lasting_allocator;
const Size = @import("data.zig").Size;
const Rectangle = @import("data.zig").Rectangle;
const containers = @import("containers.zig");
const Atom = @import("data.zig").Atom;

pub const GenericListModel = struct {
    size: *Atom(usize),
    getComponent: *const fn (self: *anyopaque, index: usize) Widget,
    userdata: *anyopaque,
};

pub const List_Impl = struct {
    pub usingnamespace @import("internal.zig").All(List_Impl);

    peer: ?backend.ScrollView = null,
    widget_data: List_Impl.WidgetData = .{},
    child: Widget,
    model: GenericListModel,

    /// The child 'widget' must be the widget of a container.
    pub fn init(widget: Widget, model: GenericListModel) List_Impl {
        return List_Impl.init_events(List_Impl{ .child = widget, .model = model });
    }

    fn modelSizeChanged(newSize: usize, userdata: usize) void {
        const self = @ptrFromInt(*List_Impl, userdata);
        const container = self.child.as(containers.Container_Impl);

        // TODO: cache widgets!
        container.removeAll();
        {
            var i: usize = 0;
            while (i < newSize) : (i += 1) {
                const widget = self.model.getComponent(self.model.userdata, i);
                container.add(widget) catch {};
            }
        }
    }

    pub fn show(self: *List_Impl) !void {
        if (self.peer == null) {
            var peer = try backend.ScrollView.create();
            try self.child.show();
            peer.setChild(self.child.peer.?, &self.child);
            self.peer = peer;
            try self.show_events();

            _ = try self.model.size.addChangeListener(.{ .function = modelSizeChanged, .userdata = @intFromPtr(self) });
        }
    }

    pub fn getPreferredSize(self: *List_Impl, available: Size) Size {
        return self.child.getPreferredSize(available);
    }
};

pub inline fn ColumnList(config: containers.GridConfig, model: anytype) anyerror!List_Impl {
    if (comptime !std.meta.trait.isPtrTo(.Struct)(@TypeOf(model))) {
        @compileError("Expected a mutable pointer to the list model");
    }
    var row = try containers.Column(config, .{});
    const ModelType = @import("internal.zig").DereferencedType(@TypeOf(model)); // The type of the list model
    var genericModel = GenericListModel{
        .size = &model.size,
        .userdata = model,
        .getComponent = struct {
            fn getComponent(self: *anyopaque, index: usize) Widget {
                const component = ModelType.getComponent(@ptrCast(*ModelType, @alignCast(@alignOf(ModelType), self)), index);
                // Convert the component (Label, Button..) to a widget
                const widget = @import("internal.zig").genericWidgetFrom(component) catch unreachable; // TODO: handle error
                return widget;
            }
        }.getComponent,
    };

    const size = model.size.get();
    var i: usize = 0;
    while (i < size) : (i += 1) {
        const component = model.getComponent(i);
        try row.add(component);
    }

    const widget = try @import("internal.zig").genericWidgetFrom(row);
    var list = List_Impl.init(widget, genericModel);

    return list;
}
