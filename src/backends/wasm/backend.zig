const std = @import("std");
const shared = @import("../shared.zig");
const lib = @import("../../main.zig");
const js = @import("js.zig");
const lasting_allocator = lib.internal.lasting_allocator;

const EventType = shared.BackendEventType;
const EventFunctions = shared.EventFunctions(@This());
const MouseButton = shared.MouseButton;

// What the backend exports
pub const PeerType = *GuiWidget;

const GuiWidget = struct {
    user: EventFunctions = .{},
    class: EventFunctions = .{},
    userdata: usize = 0,
    classUserdata: usize = 0,

    /// Pointer to the component (of type T)
    object: ?*anyopaque = null,
    element: js.ElementId = 0,

    processEventFn: *const fn (object: ?*anyopaque, event: js.EventId) void,

    pub fn init(comptime T: type, allocator: std.mem.Allocator, name: []const u8, typeName: []const u8) !*GuiWidget {
        const self = try allocator.create(GuiWidget);
        self.* = .{ .processEventFn = T.processEvent, .element = js.createElement(name, typeName) };
        return self;
    }
};

pub fn showNativeMessageDialog(msgType: shared.MessageType, comptime fmt: []const u8, args: anytype) void {
    const msg = std.fmt.allocPrintZ(lib.internal.scratch_allocator, fmt, args) catch {
        std.log.err("Could not launch message dialog, original text: " ++ fmt, args);
        return;
    };
    defer lib.internal.scratch_allocator.free(msg);
    std.log.info("native message dialog (TODO): ({}) {s}", .{ msgType, msg });
}

pub fn init() !void {
    // no initialization to do
}

var globalWindow: ?*Window = null;

pub const Window = struct {
    child: ?PeerType = null,
    scale: f32 = 1.0,

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
        // Not implemented.
    }

    pub fn setChild(self: *Window, peer: ?PeerType) void {
        if (peer) |p| {
            js.setRoot(p.element);
            self.child = peer;
        } else {
            // TODO: js.clearRoot();
        }
    }

    pub fn setTitle(self: *Window, title: [*:0]const u8) void {
        // TODO. This should be configured in the javascript
        _ = self;
        _ = title;
    }

    pub fn setSourceDpi(self: *Window, dpi: u32) void {
        // CSS pixels are somewhat undefined given they're based on the confortableness of the reader
        const resolution = @intToFloat(f32, dpi);
        self.scale = resolution / 96.0;
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
            self.peer.object = self;
        }

        pub inline fn setCallback(self: *T, comptime eType: EventType, cb: anytype) !void {
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
            }
        }

        pub fn setOpacity(self: *T, opacity: f64) void {
            _ = self;
            _ = opacity;
        }

        /// Requests a redraw
        pub fn requestDraw(self: *T) !void {
            if (@hasDecl(T, "_requestDraw")) {
                try self._requestDraw();
            }
        }

        pub fn processEvent(object: ?*anyopaque, event: js.EventId) void {
            const self = @ptrCast(*T, @alignCast(@alignOf(T), object.?));

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
                            handler(@intCast(u32, self.getWidth()), @intCast(u32, self.getHeight()), self.peer.userdata);
                        }
                        self.requestDraw() catch unreachable;
                    },
                    .MouseButton => {
                        if (self.peer.user.mouseButtonHandler) |handler| {
                            const button = @intToEnum(MouseButton, js.getEventArg(event, 0));
                            const pressed = js.getEventArg(event, 1) != 0;
                            const x = @bitCast(i32, js.getEventArg(event, 2));
                            const y = @bitCast(i32, js.getEventArg(event, 3));
                            handler(button, pressed, x, y, self.peer.userdata);
                        }
                    },
                    .MouseMotion => {
                        if (self.peer.user.mouseMotionHandler) |handler| {
                            const x = @bitCast(i32, js.getEventArg(event, 0));
                            const y = @bitCast(i32, js.getEventArg(event, 1));
                            handler(x, y, self.peer.userdata);
                        }
                    },
                    .MouseScroll => {
                        if (self.peer.user.scrollHandler) |handler| {
                            const dx = @intToFloat(f32, @bitCast(i32, js.getEventArg(event, 0)));
                            const dy = @intToFloat(f32, @bitCast(i32, js.getEventArg(event, 1)));
                            handler(dx, dy, self.peer.userdata);
                        }
                    },
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

pub const TextField = struct {
    peer: *GuiWidget,

    pub usingnamespace Events(TextField);

    pub fn create() !TextField {
        return TextField{ .peer = try GuiWidget.init(TextField, lasting_allocator, "input", "textfield") };
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

    pub fn setReadOnly(self: *TextField, readOnly: bool) void {
        _ = self;
        _ = readOnly;
        // TODO: set read only
    }
};

pub const Label = struct {
    peer: *GuiWidget,
    /// The text returned by getText(), it's invalidated everytime setText is called
    temp_text: ?[:0]const u8 = null,

    pub usingnamespace Events(Label);

    pub fn create() !Label {
        return Label{ .peer = try GuiWidget.init(Label, lasting_allocator, "span", "label") };
    }

    pub fn setAlignment(_: *Label, _: f32) void {}

    pub fn setText(self: *Label, text: [:0]const u8) void {
        js.setText(self.peer.element, text.ptr, text.len);
        if (self.temp_text) |slice| {
            lasting_allocator.free(slice);
            self.temp_text = null;
        }
    }

    pub fn getText(self: *Label) [:0]const u8 {
        if (self.temp_text) |text| {
            return text;
        } else {
            const len = js.getTextLen(self.peer.element);
            const text = lasting_allocator.allocSentinel(u8, len, 0) catch unreachable;
            js.getText(self.peer.element, text.ptr);
            self.temp_text = text;

            return text;
        }
    }
};

pub const Button = struct {
    peer: *GuiWidget,
    /// The label returned by getLabel(), it's invalidated everytime setLabel is called
    temp_label: ?[:0]const u8 = null,

    pub usingnamespace Events(Button);

    pub fn create() !Button {
        return Button{ .peer = try GuiWidget.init(Button, lasting_allocator, "button", "button") };
    }

    pub fn setLabel(self: *Button, label: [:0]const u8) void {
        js.setText(self.peer.element, label.ptr, label.len);
        if (self.temp_label) |slice| {
            lasting_allocator.free(slice);
            self.temp_label = null;
        }
    }

    pub fn getLabel(self: *const Button) [:0]const u8 {
        if (self.temp_label) |text| {
            return text;
        } else {
            const len = js.getTextLen(self.peer.element);
            const text = lasting_allocator.allocSentinel(u8, len, 0) catch unreachable;
            js.getText(self.peer.element, text.ptr);
            self.temp_label = text;

            return text;
        }
    }

    pub fn setEnabled(self: *const Button, enabled: bool) void {
        _ = self;
        _ = enabled;
        // TODO: enabled property
    }
};

pub const Canvas = struct {
    peer: *GuiWidget,

    pub usingnamespace Events(Canvas);

    pub const DrawContext = struct {
        ctx: js.CanvasContextId,

        pub const Font = struct {
            face: [:0]const u8,
            size: f64,
        };

        pub const TextSize = struct { width: u32, height: u32 };

        pub const TextLayout = struct {
            wrap: ?f64 = null,

            pub fn setFont(self: *TextLayout, font: Font) void {
                // TODO
                _ = self;
                _ = font;
            }

            pub fn deinit(self: *TextLayout) void {
                // TODO
                _ = self;
            }

            pub fn getTextSize(self: *TextLayout, str: []const u8) TextSize {
                // TODO
                _ = self;
                _ = str;
                return TextSize{ .width = 0, .height = 0 };
            }

            pub fn init() TextLayout {
                return TextLayout{};
            }
        };

        pub fn setColorByte(self: *DrawContext, color: lib.Color) void {
            js.setColor(self.ctx, color.red, color.green, color.blue, color.alpha);
        }

        pub fn setColor(self: *DrawContext, r: f32, g: f32, b: f32) void {
            self.setColorRGBA(r, g, b, 1);
        }

        pub fn setColorRGBA(self: *DrawContext, r: f32, g: f32, b: f32, a: f32) void {
            const color = lib.Color{
                .red = @floatToInt(u8, std.math.clamp(r, 0, 1) * 255),
                .green = @floatToInt(u8, std.math.clamp(g, 0, 1) * 255),
                .blue = @floatToInt(u8, std.math.clamp(b, 0, 1) * 255),
                .alpha = @floatToInt(u8, std.math.clamp(a, 0, 1) * 255),
            };
            self.setColorByte(color);
        }

        pub fn rectangle(self: *DrawContext, x: i32, y: i32, w: u32, h: u32) void {
            js.rectPath(self.ctx, x, y, w, h);
        }

        pub fn text(self: *DrawContext, x: i32, y: i32, layout: TextLayout, str: []const u8) void {
            // TODO: layout
            _ = layout;
            js.fillText(self.ctx, str.ptr, str.len, x, y);
        }

        pub fn image(self: *DrawContext, x: i32, y: i32, w: u32, h: u32, data: lib.ImageData) void {
            _ = w;
            _ = h; // TODO: scaling
            js.fillImage(self.ctx, data.peer.id, x, y);
        }

        pub fn line(self: *DrawContext, x1: i32, y1: i32, x2: i32, y2: i32) void {
            js.moveTo(self.ctx, x1, y1);
            js.lineTo(self.ctx, x2, y2);
            js.stroke(self.ctx);
        }

        pub fn ellipse(self: *DrawContext, x: i32, y: i32, w: u32, h: u32) void {
            // TODO
            _ = self;
            _ = x;
            _ = y;
            _ = w;
            _ = h;
        }

        pub fn clear(self: *DrawContext, x: u32, y: u32, w: u32, h: u32) void {
            // TODO
            _ = self;
            _ = x;
            _ = y;
            _ = w;
            _ = h;
        }

        pub fn stroke(self: *DrawContext) void {
            js.stroke(self.ctx);
        }

        pub fn fill(self: *DrawContext) void {
            js.fill(self.ctx);
        }
    };

    pub fn create() !Canvas {
        return Canvas{ .peer = try GuiWidget.init(Canvas, lasting_allocator, "canvas", "canvas") };
    }

    pub fn _requestDraw(self: *Canvas) !void {
        const ctxId = js.openContext(self.peer.element);
        var ctx = DrawContext{ .ctx = ctxId };
        if (self.peer.class.drawHandler) |handler| {
            handler(&ctx, self.peer.classUserdata);
        }
        if (self.peer.user.drawHandler) |handler| {
            handler(&ctx, self.peer.userdata);
        }
    }
};

pub const ImageData = struct {
    // TODO
    id: js.ResourceId,

    pub fn from(width: usize, height: usize, stride: usize, cs: lib.Colorspace, bytes: []const u8) !ImageData {
        return ImageData{ .id = js.uploadImage(width, height, stride, cs == .RGB, bytes.ptr) };
    }
};

pub const Container = struct {
    peer: *GuiWidget,
    children: std.ArrayList(*GuiWidget),

    pub usingnamespace Events(Container);

    pub fn create() !Container {
        return Container{
            .peer = try GuiWidget.init(Container, lasting_allocator, "div", "container"),
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
        if (peer.user.resizeHandler) |handler| {
            handler(w, h, peer.userdata);
        }
    }
};

// Misc
pub const Http = struct {
    pub fn send(url: []const u8) HttpResponse {
        return HttpResponse{ .id = js.fetchHttp(url.ptr, url.len) };
    }
};

pub const HttpResponse = struct {
    id: js.NetworkRequestId,

    pub fn isReady(self: HttpResponse) bool {
        return js.isRequestReady(self.id) != 0;
    }

    pub fn read(self: HttpResponse, buf: []u8) usize {
        return js.readRequest(self.id, buf.ptr, buf.len);
    }
};

// Execution

fn executeMain() callconv(.Async) void {
    const mainFn = @import("root").main;
    const ReturnType = @typeInfo(@TypeOf(mainFn)).Fn.return_type.?;
    if (ReturnType == void) {
        mainFn();
    } else {
        mainFn() catch |err| @panic(@errorName(err));
    }
    js.stopExecution();
}

var frame: @Frame(executeMain) = undefined;
var result: void = {};
var suspending: bool = false;

var resumePtr: anyframe = undefined;

fn milliTimestamp() i64 {
    return @floatToInt(i64, js.now());
}

pub const backendExport = struct {
    pub const os = struct {
        pub const system = struct {
            pub const E = std.os.linux.E;
            fn errno(e: E) usize {
                const signed_r = @as(isize, 0) - @enumToInt(e);
                return @bitCast(usize, signed_r);
            }

            pub fn getErrno(r: usize) E {
                const signed_r = @bitCast(isize, r);
                const int = if (signed_r > -4096 and signed_r < 0) -signed_r else 0;
                return @intToEnum(E, int);
            }

            // Time
            pub const CLOCK = std.os.linux.CLOCK;
            pub const timespec = std.os.linux.timespec;

            pub fn clock_gettime(clk_id: i32, tp: *timespec) usize {
                _ = clk_id;

                // Time in milliseconds
                const millis = milliTimestamp();
                tp.tv_sec = @intCast(isize, @divTrunc(millis, std.time.ms_per_s));
                tp.tv_nsec = @intCast(isize, @rem(millis, std.time.ms_per_s) * std.time.ns_per_ms);
                return 0;
            }

            /// Precision DEFINITELY not guarenteed (can have up to 20ms delays)
            pub fn nanosleep(req: *const timespec, rem: ?*timespec) usize {
                _ = rem;
                // Duration in milliseconds
                const duration = @intCast(u64, req.tv_sec) * 1000 + @intCast(u64, req.tv_nsec) / 1000;

                const start = milliTimestamp();
                while (milliTimestamp() < start + @intCast(i64, duration)) {
                    suspending = true;
                    suspend {
                        resumePtr = @frame();
                    }
                }
                return 0;
            }

            // I/O
            pub const fd_t = u32;
            pub const STDOUT_FILENO = 1;
            pub const STDERR_FILENO = 1;

            pub fn write(fd: fd_t, buf: [*]const u8, size: usize) usize {
                if (fd == STDOUT_FILENO or fd == STDERR_FILENO) {
                    // TODO: buffer and write for each new line
                    js.print(buf[0..size]);
                    return size;
                } else {
                    return errno(E.BADF);
                }
            }
        };
    };

    pub fn log(
        comptime message_level: std.log.Level,
        comptime scope: @Type(.EnumLiteral),
        comptime format: []const u8,
        args: anytype,
    ) void {
        const level_txt = comptime message_level.asText();
        const prefix2 = if (scope == .default) ": " else "(" ++ @tagName(scope) ++ "): ";
        const text = std.fmt.allocPrint(lib.internal.scratch_allocator, level_txt ++ prefix2 ++ format ++ "\n", args) catch return;
        defer lib.internal.scratch_allocator.free(text);

        js.print(text);
    }

    pub fn panic(msg: []const u8, _: ?*std.builtin.StackTrace, _: ?usize) noreturn {
        js.print(msg);

        //@breakpoint();
        js.stopExecution();
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
