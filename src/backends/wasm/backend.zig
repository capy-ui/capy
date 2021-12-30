const std = @import("std");
const shared = @import("../shared.zig");
const lib = @import("../../main.zig");
const js = @import("js.zig");
const lasting_allocator = lib.internal.lasting_allocator;

const EventType = shared.BackendEventType;

pub const GuiWidget = struct {
    userdata: usize = 0,
    object: usize = 0,

    element: js.ElementId = 0,
    /// Only works for buttons
    clickHandler: ?fn (data: usize) void = null,
    mouseButtonHandler: ?fn (button: MouseButton, pressed: bool, x: u32, y: u32, data: usize) void = null,
    keyTypeHandler: ?fn (str: []const u8, data: usize) void = null,
    scrollHandler: ?fn (dx: f32, dy: f32, data: usize) void = null,
    resizeHandler: ?fn (width: u32, height: u32, data: usize) void = null,
    /// Only works for canvas (althought technically it isn't required to)
    drawHandler: ?fn (ctx: Canvas.DrawContext, data: usize) void = null,
    changedTextHandler: ?fn (data: usize) void = null,

    processEventFn: fn (object: usize, event: js.EventId) void,

    pub fn init(comptime T: type, allocator: *std.mem.Allocator, name: []const u8) !*GuiWidget {
        const self = try allocator.create(GuiWidget);
        self.* = .{ .processEventFn = T.processEvent, .element = js.createElement(name) };
        return self;
    }
};

pub const MessageType = enum { Information, Warning, Error };

pub fn showNativeMessageDialog(msgType: MessageType, comptime fmt: []const u8, args: anytype) void {
    const msg = std.fmt.allocPrintZ(lib.internal.scratch_allocator, fmt, args) catch {
        std.log.err("Could not launch message dialog, original text: " ++ fmt, args);
        return;
    };
    defer lib.internal.scratch_allocator.free(msg);
    std.log.info("native message dialog (TODO): ({}) {s}", .{ msgType, msg });
}

pub const PeerType = *GuiWidget;
pub const MouseButton = enum { Left, Middle, Right };

pub fn init() !void {
    // TODO
}

var globalWindow: ?*Window = null;

pub const Window = struct {
    child: ?PeerType = null,

    pub fn create() !Window {
        return Window{};
    }

    pub fn show(self: *Window) void {
        // TODO: handle multiple windows
        if (globalWindow != null) {
            js.print("one window already showed!");
            return;
        }
        globalWindow = self;
    }

    pub fn resize(_: *Window, _: c_int, _: c_int) void {
        // TODO
    }

    pub fn setChild(self: *Window, peer: ?PeerType) void {
        if (peer) |p| {
            js.setRoot(p.element);
            self.child = peer;
        } else {
            // TODO: js.clearRoot();
        }
    }
};

pub fn Events(comptime T: type) type {
    return struct {
        const Self = @This();

        pub fn setupEvents() !void {}

        pub inline fn setUserData(self: *T, data: anytype) void {
            comptime {
                if (!std.meta.trait.isSingleItemPtr(@TypeOf(data))) {
                    @compileError(std.fmt.comptimePrint("Expected single item pointer, got {s}", .{@typeName(@TypeOf(data))}));
                }
            }

            self.peer.userdata = @ptrToInt(data);
            self.peer.object = @ptrToInt(self);
        }

        pub inline fn setCallback(self: *T, comptime eType: EventType, cb: anytype) !void {
            _ = cb;
            _ = self;
            //const data = getEventUserData(self.peer);
            switch (eType) {
                .Click => self.peer.clickHandler = cb,
                .Draw => self.peer.drawHandler = cb,
                .MouseButton => {},
                .Scroll => {},
                .TextChanged => self.peer.changedTextHandler = cb,
                .Resize => {
                    self.peer.resizeHandler = cb;
                    self.requestDraw() catch {};
                },
                .KeyType => {},
            }
        }

        pub fn setOpacity(self: *T, opacity: f64) void {
            _ = self;
            _ = opacity;
        }

        /// Requests a redraw
        pub fn requestDraw(self: *T) !void {
            _ = self;
            js.print("request draw");
            if (@hasDecl(T, "_requestDraw")) {
                try self._requestDraw();
            }
        }

        pub fn processEvent(object: usize, event: js.EventId) void {
            const self = @intToPtr(*T, object);

            if (js.getEventTarget(event) == self.peer.element) {
                // handle event
                switch (js.getEventType(event)) {
                    .OnClick => {
                        if (self.peer.clickHandler) |handler| {
                            handler(self.peer.userdata);
                        }
                    },
                    .TextChange => {
                        if (self.peer.changedTextHandler) |handler| {
                            handler(self.peer.userdata);
                        }
                    },
                    .Resize => unreachable,
                }
            } else if (T == Container) { // if we're a container, iterate over our children to propagate the event
                for (self.children.items) |child| {
                    child.processEventFn(child.object, event);
                }
            }
        }

        pub fn getWidth(self: *const T) c_int {
            return std.math.max(10, js.getWidth(self.peer.element));
        }

        pub fn getHeight(self: *const T) c_int {
            return std.math.max(10, js.getHeight(self.peer.element));
        }

        pub fn deinit(self: *const T) void {
            // TODO: actually remove the element
            _ = self;
            @panic("TODO");
        }
    };
}

pub const TextField = struct {
    peer: *GuiWidget,

    pub usingnamespace Events(TextField);

    pub fn create() !TextField {
        return TextField{ .peer = try GuiWidget.init(TextField, lasting_allocator, "input") };
    }

    pub fn setText(self: *TextField, text: []const u8) void {
        js.setText(self.peer.element, text.ptr, text.len);
    }

    pub fn getText(self: *TextField) [:0]const u8 {
        const len = js.getTextLen(self.peer.element);
        // TODO: fix the obvious memory leak
        const text = lasting_allocator.allocSentinel(u8, len, 0) catch unreachable;
        js.getText(self.peer.element, text.ptr);

        return text;
    }
};

pub const Label = struct {
    peer: *GuiWidget,

    pub usingnamespace Events(Label);

    pub fn create() !Label {
        return Label{ .peer = try GuiWidget.init(Label, lasting_allocator, "span") };
    }

    pub fn setAlignment(_: *Label, _: f32) void {}

    pub fn setText(self: *Label, text: [:0]const u8) void {
        js.setText(self.peer.element, text.ptr, text.len);
    }

    pub fn getText(_: *Label) [:0]const u8 {
        return undefined;
    }
};

pub const Button = struct {
    peer: *GuiWidget,

    pub usingnamespace Events(Button);

    pub fn create() !Button {
        return Button{ .peer = try GuiWidget.init(Button, lasting_allocator, "button") };
    }

    pub fn setLabel(self: *Button, label: [:0]const u8) void {
        js.setText(self.peer.element, label.ptr, label.len);
        _ = self;
        _ = label;
    }

    pub fn getLabel(_: *Button) [:0]const u8 {
        return undefined;
    }
};

pub const Canvas = struct {
    peer: *GuiWidget,

    pub usingnamespace Events(Canvas);

    pub const DrawContext = struct {
        ctx: js.CanvasContextId,

        pub fn setColor(self: *const DrawContext, r: f32, g: f32, b: f32) void {
            self.setColorRGBA(r, g, b, 1);
        }

        pub fn setColorRGBA(self: *const DrawContext, r: f32, g: f32, b: f32, a: f32) void {
            js.setColor(self.ctx, @floatToInt(u8, r * 255), @floatToInt(u8, g * 255), @floatToInt(u8, b * 255), @floatToInt(u8, a * 255));
        }

        pub fn rectangle(self: *const DrawContext, x: u32, y: u32, w: u32, h: u32) void {
            js.rectPath(self.ctx, x, y, w, h);
        }

        pub fn line(self: *const DrawContext, x1: u32, y1: u32, x2: u32, y2: u32) void {
            js.moveTo(self.ctx, x1, y1);
            js.lineTo(self.ctx, x2, y2);
            js.stroke(self.ctx);
        }

        pub fn ellipse(self: *const DrawContext, x: u32, y: u32, w: f32, h: f32) void {
            // TODO
            _ = self;
            _ = x;
            _ = y;
            _ = w;
            _ = h;
        }

        pub fn stroke(self: *const DrawContext) void {
            js.stroke(self.ctx);
        }

        pub fn fill(self: *const DrawContext) void {
            js.fill(self.ctx);
        }
    };

    pub fn create() !Canvas {
        return Canvas{ .peer = try GuiWidget.init(Canvas, lasting_allocator, "canvas") };
    }

    pub fn _requestDraw(self: *Canvas) !void {
        const ctxId = js.openContext(self.peer.element);
        const ctx = DrawContext{ .ctx = ctxId };
        if (self.peer.drawHandler) |handler| {
            handler(ctx, self.peer.userdata);
        }
    }
};

pub const Container = struct {
    peer: *GuiWidget,
    children: std.ArrayList(*GuiWidget),

    pub usingnamespace Events(Container);

    pub fn create() !Container {
        return Container{
            .peer = try GuiWidget.init(Container, lasting_allocator, "div"),
            .children = std.ArrayList(*GuiWidget).init(lasting_allocator),
        };
    }

    pub fn add(self: *Container, peer: PeerType) void {
        js.appendElement(self.peer.element, peer.element);
        self.children.append(peer) catch unreachable;
    }

    pub fn move(self: *const Container, peer: PeerType, x: u32, y: u32) void {
        _ = self;
        js.setPos(peer.element, x, y);
    }

    pub fn resize(self: *const Container, peer: PeerType, w: u32, h: u32) void {
        _ = self;
        js.setSize(peer.element, w, h);
        if (peer.resizeHandler) |handler| {
            handler(w, h, peer.userdata);
        }
    }
};

pub fn milliTimestamp() i64 {
    return @floatToInt(i64, @floor(js.now()));
}

fn executeMain() anyerror!void {
    try mainFn();
}

const mainFn = @import("root").main;
var frame: @Frame(executeMain) = undefined;
var result: anyerror!void = error.None;
var suspending: bool = false;

var resumePtr: anyframe = undefined;

pub const backendExport = struct {
    pub const os = struct {
        pub const system = struct {
            pub const E = enum(u8) {
                SUCCESS = 0,
                INVAL = 1,
                INTR = 2,
                FAULT = 3,
            };

            pub const timespec = struct { tv_sec: isize, tv_nsec: isize };

            pub fn getErrno(r: usize) E {
                if (r & ~@as(usize, 0xFF) == ~@as(usize, 0xFF)) {
                    return @intToEnum(E, r & 0xFF);
                } else {
                    return E.SUCCESS;
                }
            }

            pub fn nanosleep(req: *const timespec, rem: ?*timespec) usize {
                _ = rem;
                const ms = @intCast(u64, req.tv_sec) * 1000 + @intCast(u64, req.tv_nsec) / 1000;
                sleep(ms);
                return 0;
            }
        };
    };

    /// Precision DEFINITELY not guarenteed (can have up to 20ms delays)
    pub fn sleep(duration: u64) void {
        const start = milliTimestamp();

        while (milliTimestamp() < start + @intCast(i64, duration)) {
            suspending = true;
            suspend {
                resumePtr = @frame();
            }
        }
    }

    pub fn panic(msg: []const u8, _: ?*std.builtin.StackTrace) noreturn {
        js.print(msg);

        @breakpoint();
        while (true) {}
    }

    pub export fn _start() callconv(.C) void {
        _ = @asyncCall(&frame, &result, executeMain, .{});
    }

    pub export fn _zgtContinue() callconv(.C) void {
        if (suspending) {
            suspending = false;
            resume resumePtr;
        }
    }
};

pub fn runStep(step: shared.EventLoopStep) callconv(.Async) bool {
    _ = step;
    while (js.hasEvent()) {
        const eventId = js.popEvent();
        switch (js.getEventType(eventId)) {
            .Resize => {
                if (globalWindow) |window| {
                    if (window.child) |child| {
                        child.resizeHandler.?(0, 0, child.userdata);
                    }
                }
            },
            else => {
                if (globalWindow) |window| {
                    if (window.child) |child| {
                        child.processEventFn(child.object, eventId);
                    }
                }
            },
        }
    }
    suspending = true;
    suspend {
        resumePtr = @frame();
    }
    return true;
}
