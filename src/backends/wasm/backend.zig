const std = @import("std");
const lib = @import("../../main.zig");
const js = @import("js.zig");
const lasting_allocator = lib.internal.lasting_allocator;

pub const GuiWidget = struct {
    userdata: usize = 0,
    element: js.ElementId = 0,
    /// Only works for buttons
    clickHandler: ?fn(data: usize) void = null,
    mouseButtonHandler: ?fn(button: MouseButton, pressed: bool, x: u32, y: u32, data: usize) void = null,
    keyTypeHandler: ?fn(str: []const u8, data: usize) void = null,
    scrollHandler: ?fn(dx: f32, dy: f32, data: usize) void = null,
    resizeHandler: ?fn(width: u32, height: u32, data: usize) void = null,
    /// Only works for canvas (althought technically it isn't required to)
    drawHandler: ?fn(ctx: Canvas.DrawContext, data: usize) void = null,
    changedTextHandler: ?fn(data: usize) void = null,

    pub fn init(allocator: *std.mem.Allocator, name: []const u8) !*GuiWidget {
        const self = try allocator.create(GuiWidget);
        self.element = js.createElement(name);
        return self;
    }
};

pub const MessageType = enum {
    Information,
    Warning,
    Error
};

pub fn showNativeMessageDialog(msgType: MessageType, comptime fmt: []const u8, args: anytype) void {
    const msg = std.fmt.allocPrintZ(lib.internal.scratch_allocator, fmt, args) catch {
        std.log.err("Could not launch message dialog, original text: " ++ fmt, args);
        return;
    };
    defer lib.internal.scratch_allocator.free(msg);
    std.log.info("native message dialog (TODO): ({}) {s}", .{msgType, msg});
}

pub const PeerType = *GuiWidget;
pub const MouseButton = enum {
    Left,
    Middle,
    Right
};

pub fn init() !void {
    // TODO
}

var globalWindow: ?*Window = null;

pub const Window = struct {
    child: ?PeerType = null,

    pub fn create() !Window {
        // TODO
        return Window { };
    }

    pub fn show(self: *Window) void {
        // TODO
        if (globalWindow != null) {
            js.print("one window already showed!");
            return;
        }
        globalWindow = self;
    }

    pub fn resize(_: *Window, _: c_int, _: c_int) void {
        // TODO
    }

    pub fn setChild(self: *Window, peer: PeerType) void {
        js.setRoot(peer.element);
        self.child = peer;
    }

};

pub const EventType = enum {
    Click,
    Draw,
    MouseButton,
    Scroll,
    TextChanged,
    Resize,
    KeyType
};

pub fn Events(comptime T: type) type {
    return struct {
        const Self = @This();

        pub fn setupEvents() !void {

        }

        pub fn setUserData(self: *T, data: anytype) callconv(.Inline) void {
            comptime {
                if (!std.meta.trait.isSingleItemPtr(@TypeOf(data))) {
                    @compileError(std.fmt.comptimePrint("Expected single item pointer, got {s}", .{@typeName(@TypeOf(data))}));
                }
            }

            self.peer.userdata = @ptrToInt(data);
        }

        pub fn setCallback(self: *T, comptime eType: EventType, cb: anytype) callconv(.Inline) !void {
            _ = cb;
            _ = self;
            //const data = getEventUserData(self.peer);
            switch (eType) {
                .Click       => {},
                .Draw        => {},
                .MouseButton => {},
                .Scroll      => {},
                .TextChanged => {},
                .Resize      => self.peer.resizeHandler = cb,
                .KeyType     => {}
            }
        }

        pub fn setOpacity(self: *T, opacity: f64) void {
            _ = self;
            _ = opacity;
        }

        /// Requests a redraw
        pub fn requestDraw(self: *T) !void {
            _ = self;
        }

        pub fn getWidth(self: *const T) c_int {
            return std.math.max(10, js.getWidth(self.peer.element));
        }

        pub fn getHeight(self: *const T) c_int {
            return std.math.max(10, js.getHeight(self.peer.element));
        }

    };
}

pub const TextField = struct {
    peer: *GuiWidget,

    pub usingnamespace Events(TextField);

    pub fn create() !TextField {
        return TextField {
            .peer = try GuiWidget.init(lasting_allocator, "input")
        };
    }

    pub fn setText(self: *TextField, text: []const u8) void {
        js.setText(self.peer.element, text.ptr, text.len);
    }

    pub fn getText(self: *TextField) [:0]const u8 {
        _ = self;
        return "";
    }

};


pub const Label = struct {
    peer: *GuiWidget,

    pub usingnamespace Events(Label);

    pub fn create() !Label {
        return Label {
            .peer = try GuiWidget.init(lasting_allocator, "span")
        };
    }

    pub fn setAlignment(_: *Label, _: f32) void {

    }

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
        return Button {
            .peer = try GuiWidget.init(lasting_allocator, "button")
        };
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

pub const Container = struct {
    peer: *GuiWidget,

    pub usingnamespace Events(Container);

    pub fn create() !Container {
        return Container {
            .peer = try GuiWidget.init(lasting_allocator, "div")
        };
    }

    pub fn add(self: *Container, peer: PeerType) void {
        js.appendElement(self.peer.element, peer.element);
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

fn executeMain() anyerror!void {
    try mainFn();
}

pub fn panic(msg: []const u8, _: ?*std.builtin.StackTrace) noreturn {
    js.print(msg);
    
    @breakpoint();
    while (true) {}
}

const mainFn = @import("root").main;
var frame: @Frame(executeMain) = undefined;
var result: anyerror!void = error.None;
var suspending: bool = false;

var resumePtr: anyframe = undefined;

pub export fn _start() callconv(.C) void {
    _ = @asyncCall(&frame, &result, executeMain, .{ });
}

pub export fn _zgtContinue() callconv(.C) void {
    if (suspending) {
        suspending = false;
        resume resumePtr;
    }
}

pub const Canvas = struct {
    pub const DrawContext = struct {};
};

pub fn runStep(step: lib.EventLoopStep) callconv(.Async) bool {
    _ = step;
    if (globalWindow) |window| {
        if (window.child) |child| {
            child.resizeHandler.?(0, 0, child.userdata);
        }
    }
    suspending = true;
    suspend {
        resumePtr = @frame();
    }
    return true;
}
