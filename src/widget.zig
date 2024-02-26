const std = @import("std");
const backend = @import("backend.zig");
const data = @import("data.zig");

const Allocator = std.mem.Allocator;

/// A class is a constant list of methods that can be called using Widget.
// Note: it is called Class instead of VTable as it was made before allocgate
pub const Class = struct {
    typeName: []const u8,

    showFn: *const fn (widget: *Widget) anyerror!void,
    deinitFn: *const fn (widget: *Widget) void,
    preferredSizeFn: *const fn (widget: *const Widget, available: data.Size) data.Size,
    /// Normally, each widget is paired to a component and each showed component is
    /// paired to a widget. However, in order to pair them you need to be able to edit
    /// the dataWrappers.widget field, which is impossible if the component type is
    /// unknown. This function is thus called internally to pair the widget.
    getParentFn: *const fn (widget: *const Widget) ?*Widget,
    isDisplayedFn: *const fn (widget: *const Widget) bool,

    unref_fn: *const fn (*anyopaque) void,
    ref_fn: *const fn (*anyopaque) void,
    // offset into a list of updater optional pointers
    //updaters: []const usize,
};

/// A widget is a unique representation and constant size of any view.
pub const Widget = struct {
    /// Similarly to std.mem.Allocator, this is a pointer to the actual component class that
    /// its class methods use.
    data: *anyopaque,
    class: *const Class,
    peer: ?backend.PeerType = null,
    container_expanded: bool = false,
    /// A widget MUST only be parented by a Container
    parent: ?*Widget = null,

    // TODO: store @offsetOf these fields in the Class instead of having the cost of 3 pointers
    name: *data.Atom(?[]const u8),

    pub fn show(self: *Widget) anyerror!void {
        try self.class.showFn(self);
    }

    /// Get the preferred size for the given available space.
    /// With this system, minimum size is widget.getPreferredSize(Size { .width = 0, .height = 0 }),
    /// and maximum size is widget.getPreferredSize(Size { .width = std.math.maxInt(u32), .height = std.math.maxInt(u32) })
    pub fn getPreferredSize(self: *const Widget, available: data.Size) data.Size {
        return self.class.preferredSizeFn(self, available);
    }

    pub fn getParent(self: *const Widget) ?*Widget {
        return self.class.getParentFn(self);
    }

    pub fn isDisplayed(self: *const Widget) bool {
        return self.class.isDisplayedFn(self);
    }

    /// Asserts widget data is of type T
    pub fn as(self: *const Widget, comptime T: type) *T {
        // TODO: use @fieldParentPtr when it is guarenteed that Widget are inside components
        if (std.debug.runtime_safety) {
            if (!self.is(T)) {
                std.debug.panic("Tried to cast widget to " ++ @typeName(T) ++ " but type is {s}", .{self.class.typeName});
            }
        }
        return @ptrCast(@alignCast(self.data));
    }

    /// Returns if the class of the widget corresponds to T
    pub fn is(self: *const Widget, comptime T: type) bool {
        return self.class == &T.WidgetClass;
    }

    /// If widget is an instance of T, returns widget.as(T), otherwise return null
    pub fn cast(self: *const Widget, comptime T: type) ?*T {
        if (self.is(T)) {
            return self.as(T);
        } else {
            return null;
        }
    }

    pub fn unref(self: *const Widget) void {
        self.class.unref_fn(self.data);
    }

    pub fn ref(self: *const Widget) void {
        self.class.ref_fn(self.data);
    }

    pub fn deinit(self: *Widget) void {
        self.class.deinitFn(self);
    }
};

const expect = std.testing.expect;
const expectEqual = std.testing.expectEqual;

const TestType = struct {
    randomData: u16 = 0x1234,

    pub const WidgetClass = Class{
        .typeName = "TestType",
        .showFn = undefined,
        .deinitFn = undefined,
        .preferredSizeFn = undefined,
        .getParentFn = undefined,
        .isDisplayedFn = undefined,
        // .cloneFn = undefined,
        .ref_fn = undefined,
        .unref_fn = undefined,
    };
};

test "widget basics" {
    var testWidget: TestType = .{};
    const widget = Widget{
        .data = &testWidget,
        .class = &TestType.WidgetClass,

        .name = undefined,
    };

    try expect(widget.is(TestType));

    const cast = widget.cast(TestType);
    try expect(cast != null);
    if (cast) |value| {
        try expectEqual(&testWidget, value);
        try expectEqual(@as(u16, 0x1234), value.randomData);
    }
}
