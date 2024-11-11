const std = @import("std");
const shared = @import("../shared.zig");
const js = @import("js.zig");
const trait = @import("../../trait.zig");
const lib = @import("../../capy.zig");

const EventType = shared.BackendEventType;
const EventFunctions = shared.EventFunctions(@This());
const MouseButton = shared.MouseButton;
const Container = @import("Container.zig");

pub const GuiWidget = struct {
    user: EventFunctions = .{},
    class: EventFunctions = .{},
    userdata: usize = 0,
    classUserdata: usize = 0,

    /// Pointer to the component (of type T)
    object: ?*anyopaque = null,
    element: js.ElementId = 0,

    processEventFn: *const fn (object: ?*anyopaque, event: js.EventId) void,
    children: std.ArrayList(*GuiWidget),

    pub fn init(comptime T: type, allocator: std.mem.Allocator, name: []const u8, typeName: []const u8) !*GuiWidget {
        const self = try allocator.create(GuiWidget);
        self.* = .{
            .processEventFn = T.processEvent,
            .element = js.createElement(name, typeName),
            .children = std.ArrayList(*GuiWidget).init(allocator),
        };
        return self;
    }
};

pub fn Events(comptime T: type) type {
    return struct {
        const Self = @This();

        pub fn setupEvents() !void {}

        pub inline fn setUserData(self: *T, data: anytype) void {
            comptime {
                if (!trait.isSingleItemPtr(@TypeOf(data))) {
                    @compileError(std.fmt.comptimePrint("Expected single item pointer, got {s}", .{@typeName(@TypeOf(data))}));
                }
            }

            self.peer.userdata = @intFromPtr(data);
            self.peer.object = self;
        }

        pub inline fn setCallback(self: *T, comptime eType: EventType, cb: anytype) !void {
            self.peer.object = self;
            switch (eType) {
                .Click => self.peer.user.clickHandler = cb,
                .Draw => self.peer.user.drawHandler = cb,
                .MouseButton => self.peer.user.mouseButtonHandler = cb,
                .MouseMotion => self.peer.user.mouseMotionHandler = cb,
                .Scroll => self.peer.user.scrollHandler = cb,
                .TextChanged => self.peer.user.changedTextHandler = cb,
                .Resize => {
                    self.peer.user.resizeHandler = cb;
                    self.requestDraw() catch {};
                },
                .KeyType => self.peer.user.keyTypeHandler = cb,
                .KeyPress => self.peer.user.keyPressHandler = cb,
                .PropertyChange => self.peer.user.propertyChangeHandler = cb,
            }
        }

        pub fn setOpacity(self: *T, opacity: f64) void {
            _ = self;
            _ = opacity;
        }

        /// Requests a redraw
        pub fn requestDraw(self: *T) !void {
            if (@hasDecl(T, "_requestDraw")) {
                self._requestDraw();
            }
        }

        pub fn processEvent(object: ?*anyopaque, event: js.EventId) void {
            const self = @as(*T, @ptrCast(@alignCast(object.?)));

            // This is a global event, so calling getEventTarget on it would fail.
            if (js.getEventType(event) == .WindowTick) {
                if (@hasDecl(T, "_onWindowTick")) {
                    self._onWindowTick();
                }
                if (T == Container) {
                    for (self.peer.children.items) |child| {
                        child.processEventFn(child.object, event);
                    }
                }
                return;
            }
            if (js.getEventTarget(event) == self.peer.element) {
                // handle event
                switch (js.getEventType(event)) {
                    .OnClick => {
                        if (self.peer.user.clickHandler) |handler| {
                            handler(self.peer.userdata);
                        }
                    },
                    .TextChange => {
                        if (self.peer.user.changedTextHandler) |handler| {
                            handler(self.peer.userdata);
                        }
                    },
                    .Resize => {
                        if (self.peer.user.resizeHandler) |handler| {
                            handler(@as(u32, @intCast(self.getWidth())), @as(u32, @intCast(self.getHeight())), self.peer.userdata);
                        }
                        self.requestDraw() catch unreachable;
                    },
                    .MouseButton => {
                        if (self.peer.user.mouseButtonHandler) |handler| {
                            const button = @as(MouseButton, @enumFromInt(js.getEventArg(event, 0)));
                            const pressed = js.getEventArg(event, 1) != 0;
                            const x = @as(i32, @bitCast(js.getEventArg(event, 2)));
                            const y = @as(i32, @bitCast(js.getEventArg(event, 3)));
                            handler(button, pressed, x, y, self.peer.userdata);
                        }
                    },
                    .MouseMotion => {
                        if (self.peer.user.mouseMotionHandler) |handler| {
                            const x = @as(i32, @bitCast(js.getEventArg(event, 0)));
                            const y = @as(i32, @bitCast(js.getEventArg(event, 1)));
                            handler(x, y, self.peer.userdata);
                        }
                    },
                    .MouseScroll => {
                        if (self.peer.user.scrollHandler) |handler| {
                            const dx = @as(f32, @floatFromInt(@as(i32, @bitCast(js.getEventArg(event, 0)))));
                            const dy = @as(f32, @floatFromInt(@as(i32, @bitCast(js.getEventArg(event, 1)))));
                            handler(dx, dy, self.peer.userdata);
                        }
                    },
                    .UpdateAudio, .WindowTick => unreachable,
                    .PropertyChange => {
                        if (self.peer.user.propertyChangeHandler) |handler| {
                            const value_f32 = js.getValue(self.peer.element);
                            handler("value", &value_f32, self.peer.userdata);
                        }
                    },
                }
            } else if (T == Container) { // if we're a container, iterate over our children to propagate the event
                for (self.peer.children.items) |child| {
                    child.processEventFn(child.object, event);
                }
            }
        }

        pub fn getWidth(self: *const T) c_int {
            return @max(10, js.getWidth(self.peer.element));
        }

        pub fn getHeight(self: *const T) c_int {
            return @max(10, js.getHeight(self.peer.element));
        }

        pub fn getPreferredSize(self: *const T) lib.Size {
            // TODO
            _ = self;
            return lib.Size.init(100, 100);
        }

        pub fn deinit(self: *const T) void {
            // TODO: actually remove the element
            _ = self;
            @panic("TODO");
        }
    };
}
