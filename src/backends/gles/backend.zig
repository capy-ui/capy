const std = @import("std");
const lib = @import("../../main.zig");
const c = @cImport({
    @cDefine("GLFW_INCLUDE_ES3", {});
    @cInclude("GLFW/glfw3.h");
});
const gl = c;
const lasting_allocator = lib.internal.lasting_allocator;

var activeWindows = std.ArrayList(*c.GLFWwindow).init(lasting_allocator);

pub const GuiWidget = struct {
    userdata: usize = 0,
    width: u32 = 0,
    height: u32 = 0,

    pub fn init(allocator: *std.mem.Allocator) !*GuiWidget {
        const self = try allocator.create(GuiWidget);
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
    if (c.glfwInit() != 1) {
        return error.InitializationError;
    }
}

pub fn compileShader(shader: c.GLuint) !void {
    c.glCompileShader(shader);
    var result: c.GLint = undefined;
    var infoLogLen: c_int = 0;

    c.glGetShaderiv(shader, c.GL_COMPILE_STATUS, &result);
    c.glGetShaderiv(shader, c.GL_INFO_LOG_LENGTH, &infoLogLen);
    if (infoLogLen > 0) {
        std.log.crit("info ?", .{});
        return error.ShaderError;
    }
}

pub const Window = struct {
    window: *c.GLFWwindow,

    pub fn create() !Window {
        c.glfwWindowHint(c.GLFW_CLIENT_API, c.GLFW_OPENGL_ES_API);
        const window = c.glfwCreateWindow(640, 400, "", null, null) orelse return error.InitializationError;
        c.glfwMakeContextCurrent(window);
        c.glfwSwapInterval(1);

        var vao: c.GLuint = undefined;
        c.glGenVertexArrays(1, &vao);
        c.glBindVertexArray(vao);
        const bufferData = [_]f32 {
            -1.0, -1.0,
             1.0, -1.0,
             0.0,  1.0,
        };
        var vbo: c.GLuint = undefined;
        c.glGenBuffers(1, &vbo);
        c.glBindBuffer(c.GL_ARRAY_BUFFER, vbo);
        c.glBufferData(c.GL_ARRAY_BUFFER, @sizeOf(@TypeOf(bufferData)), &bufferData, c.GL_STATIC_DRAW);

        c.glEnableVertexAttribArray(0);
        c.glBindBuffer(c.GL_ARRAY_BUFFER, vbo);
        c.glVertexAttribPointer(0, 2, c.GL_FLOAT, c.GL_FALSE, 0, null);

        std.log.info("vbo: {d}", .{vbo});

        const vertex = c.glCreateShader(c.GL_VERTEX_SHADER);
        c.glShaderSource(vertex, 1, &[_][*c]const u8 {@embedFile("shaders/vertex.glsl")}, null);
        try compileShader(vertex);

        const fragment = c.glCreateShader(c.GL_FRAGMENT_SHADER);
        c.glShaderSource(fragment, 1, &[_][*c]const u8 {@embedFile("shaders/fragment.glsl")}, null);
        try compileShader(fragment);

        const program = c.glCreateProgram();
        c.glAttachShader(program, vertex);
        c.glAttachShader(program, fragment);
        c.glLinkProgram(program);
        c.glUseProgram(program);
        std.log.info("program: {d}", .{program});

        try activeWindows.append(window);
        return Window {
            .window = window
        };
    }

    pub fn show(self: *Window) void {
        _ = self;
    }

    pub fn resize(self: *Window, width: c_int, height: c_int) void {
        _ = self;
        _ = width;
        _ = height;
    }

    pub fn setChild(self: *Window, peer: PeerType) void {
        _ = self;
        _ = peer;
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
                .Resize      => {},
                .KeyType     => {}
            }
        }

        /// Requests a redraw
        pub fn requestDraw(self: *T) !void {
            _ = self;
            // TODO
        }

        pub fn getWidth(self: *const T) c_int {
            _ = self;
            //return c.gtk_widget_get_allocated_width(self.peer);
            return 0;
        }

        pub fn getHeight(self: *const T) c_int {
            _ = self;
            //return c.gtk_widget_get_allocated_height(self.peer);
            return 0;
        }

    };
}

pub const TextField = struct {
    peer: *GuiWidget,

    pub usingnamespace Events(TextField);

    pub fn create() !TextField {
        return TextField {
            .peer = try GuiWidget.init(lasting_allocator)
        };
    }

    pub fn setText(self: *TextField, text: []const u8) void {
        _ = self;
        _ = text;
    }

    pub fn getText(self: *TextField) [:0]const u8 {
        _ = self;
        return "";
    }

};

pub const Button = struct {
    peer: *GuiWidget,

    pub usingnamespace Events(Button);

    pub fn create() !Button {
        return Button {
            .peer = try GuiWidget.init(lasting_allocator)
        };
    }

    pub fn setLabel(self: *Button, label: [:0]const u8) void {
        _ = self;
        _ = label;
    }

};

pub const Container = struct {
    peer: *GuiWidget,

    pub usingnamespace Events(Container);

    pub fn create() !Container {
        return Container {
            .peer = try GuiWidget.init(lasting_allocator)
        };
    }

    pub fn add(self: *Container, peer: PeerType) void {
        _ = self;
        _ = peer;
    }

    pub fn move(self: *const Container, peer: PeerType, x: u32, y: u32) void {
        _ = self;
        _ = peer;
        _ = x; _ = y;
    }

    pub fn resize(self: *const Container, peer: PeerType, w: u32, h: u32) void {
        _ = w; _ = h;
        _ = peer;
        _ = self;
    }

};

pub const Canvas = struct {
    pub const DrawContext = struct {};
};

pub fn runStep(step: lib.EventLoopStep) bool {
    _ = step;
    for (activeWindows.items) |window| {
        c.glfwMakeContextCurrent(window);
        if (c.glfwWindowShouldClose(window) != 0) {
            // TODO: remove window from list
            c.glfwDestroyWindow(window);
            return false;
        } else {
            var width: c_int = undefined;
            var height: c_int = undefined;
            c.glfwGetFramebufferSize(window, &width, &height);

            c.glViewport(0, 0, width, height);
            c.glClear(c.GL_COLOR_BUFFER_BIT | c.GL_DEPTH_BUFFER_BIT);

            c.glUseProgram(0);
            c.glEnableVertexAttribArray(0);
            c.glVertexAttribPointer(0, 2, c.GL_FLOAT, c.GL_FALSE, 0, null);
            c.glBindBuffer(c.GL_ARRAY_BUFFER, 1);
            c.glDrawArrays(c.GL_TRIANGLES, 0, 3);

            c.glfwSwapBuffers(window);
            c.glfwPollEvents();
        }
    }
    return activeWindows.items.len > 0;
}
