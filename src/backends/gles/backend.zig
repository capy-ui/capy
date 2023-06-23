const std = @import("std");
const shared = @import("../shared.zig");
const lib = @import("../../main.zig");
const c = @cImport({
    @cDefine("GLFW_INCLUDE_ES3", {});
    @cInclude("GLFW/glfw3.h");
});
const gl = c;
const lasting_allocator = lib.internal.lasting_allocator;

const EventType = shared.BackendEventType;

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
    if (c.glfwInit() != 1) {
        return error.InitializationError;
    }
}

pub fn unexpectedGlError() !void {
    switch (c.glGetError()) {
        c.GL_INVALID_OPERATION => {
            return error.InvalidOperation;
        },
        c.GL_INVALID_ENUM => {
            return error.InvalidEnum;
        },
        else => |id| {
            std.log.warn("Unknown GL error: {d}", .{id});
            return error.Unexpected;
        },
    }
}

const Shader = struct {
    id: c.GLuint,

    pub fn create(shaderType: c.GLenum, source: [:0]const u8) !Shader {
        const id = c.glCreateShader(shaderType);
        if (id == 0) {
            try unexpectedGlError();
        }

        c.glShaderSource(id, 1, &[_][*c]const u8{source}, null);
        return Shader{ .id = id };
    }

    pub fn compile(self: Shader) !void {
        c.glCompileShader(self.id);
        var result: c.GLint = undefined;
        var infoLogLen: c_int = 0;

        c.glGetShaderiv(self.id, c.GL_COMPILE_STATUS, &result);
        c.glGetShaderiv(self.id, c.GL_INFO_LOG_LENGTH, &infoLogLen);
        if (infoLogLen > 0) {
            const infoLog = try lib.internal.scratch_allocator.allocSentinel(u8, @intCast(usize, infoLogLen), 0);
            defer lib.internal.scratch_allocator.free(infoLog);
            c.glGetShaderInfoLog(self.id, infoLogLen, null, infoLog.ptr);
            std.log.crit("shader compile error:\n{s}", .{infoLog});
            return error.ShaderError;
        }
    }
};

pub const Window = struct {
    window: *c.GLFWwindow,

    pub fn create() !Window {
        c.glfwWindowHint(c.GLFW_CLIENT_API, c.GLFW_OPENGL_ES_API);
        c.glfwWindowHint(c.GLFW_CONTEXT_VERSION_MAJOR, 3);
        c.glfwWindowHint(c.GLFW_CONTEXT_VERSION_MINOR, 0);
        c.glfwWindowHint(c.GLFW_OPENGL_PROFILE, c.GLFW_OPENGL_ANY_PROFILE);
        c.glfwWindowHint(c.GLFW_VISIBLE, c.GLFW_FALSE);
        //c.glfwWindowHint(c.GLFW_CONTEXT_ROBUSTNESS, c.GLFW_LOSE_CONTEXT_ON_RESET);
        const window = c.glfwCreateWindow(640, 400, "", null, null) orelse return error.InitializationError;
        c.glfwMakeContextCurrent(window);
        c.glfwSwapInterval(0);
        _ = c.glfwSetWindowRefreshCallback(window, drawWindow);

        var vao: c.GLuint = undefined;
        c.glGenVertexArrays(1, &vao);
        c.glBindVertexArray(vao);
        const bufferData = [_]f32{
            -1.0, -1.0,
            1.0,  -1.0,
            -1.0, 1.0,
        };
        var vbo: c.GLuint = undefined;
        c.glGenBuffers(1, &vbo);
        c.glBindBuffer(c.GL_ARRAY_BUFFER, vbo);
        c.glBufferData(c.GL_ARRAY_BUFFER, @sizeOf(@TypeOf(bufferData)), &bufferData, c.GL_STATIC_DRAW);

        c.glEnableVertexAttribArray(0);
        c.glBindBuffer(c.GL_ARRAY_BUFFER, vbo);
        c.glVertexAttribPointer(0, 2, c.GL_FLOAT, c.GL_FALSE, 0, null);

        std.log.info("vbo: {d}", .{vbo});

        const vertex = try Shader.create(c.GL_VERTEX_SHADER, @embedFile("shaders/vertex.glsl"));
        try vertex.compile();

        const fragment = try Shader.create(c.GL_FRAGMENT_SHADER, @embedFile("shaders/fragment.glsl"));
        try fragment.compile();

        const program = c.glCreateProgram();
        c.glAttachShader(program, vertex.id);
        c.glAttachShader(program, fragment.id);
        c.glLinkProgram(program);
        c.glUseProgram(program);
        std.log.info("program: {d}", .{program});

        try activeWindows.append(window);
        return Window{ .window = window };
    }

    pub fn show(self: *Window) void {
        c.glfwShowWindow(self.window);
    }

    pub fn resize(self: *Window, width: c_int, height: c_int) void {
        c.glfwSetWindowSize(self.window, width, height);
    }

    pub fn setChild(self: *Window, peer: PeerType) void {
        _ = self;
        _ = peer;
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

            self.peer.userdata = @intFromPtr(data);
        }

        pub inline fn setCallback(self: *T, comptime eType: EventType, cb: anytype) !void {
            _ = cb;
            _ = self;
            //const data = getEventUserData(self.peer);
            switch (eType) {
                .Click => {},
                .Draw => {},
                .MouseButton => {},
                .Scroll => {},
                .TextChanged => {},
                .Resize => {},
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
        return TextField{ .peer = try GuiWidget.init(lasting_allocator) };
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
        return Button{ .peer = try GuiWidget.init(lasting_allocator) };
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
        return Container{ .peer = try GuiWidget.init(lasting_allocator) };
    }

    pub fn add(self: *Container, peer: PeerType) void {
        _ = self;
        _ = peer;
    }

    pub fn move(self: *const Container, peer: PeerType, x: u32, y: u32) void {
        _ = self;
        _ = peer;
        _ = x;
        _ = y;
    }

    pub fn resize(self: *const Container, peer: PeerType, w: u32, h: u32) void {
        _ = w;
        _ = h;
        _ = peer;
        _ = self;
    }
};

pub const Canvas = struct {
    pub const DrawContext = struct {};
};

fn drawWindow(cWindow: ?*c.GLFWwindow) callconv(.C) void {
    const window = cWindow.?;

    var width: c_int = undefined;
    var height: c_int = undefined;
    c.glfwGetFramebufferSize(window, &width, &height);

    c.glViewport(0, 0, width, height);
    c.glClear(c.GL_COLOR_BUFFER_BIT | c.GL_DEPTH_BUFFER_BIT);

    c.glUseProgram(3);
    c.glEnableVertexAttribArray(0);
    c.glVertexAttribPointer(0, 2, c.GL_FLOAT, c.GL_FALSE, 0, null);
    c.glBindBuffer(c.GL_ARRAY_BUFFER, 1);
    c.glDrawArrays(c.GL_TRIANGLES, 0, 3);

    c.glfwSwapBuffers(window);
}

pub fn runStep(step: shared.EventLoopStep) bool {
    for (activeWindows.items) |window| {
        c.glfwMakeContextCurrent(window);
        if (c.glfwWindowShouldClose(window) != 0) {
            // TODO: remove window from list
            c.glfwDestroyWindow(window);
            return false;
        } else {
            switch (step) {
                .Asynchronous => c.glfwPollEvents(),
                .Blocking => c.glfwWaitEvents(),
            }
            // TODO: check if something changed before drawing
            drawWindow(window);
        }
    }
    return activeWindows.items.len > 0;
}
