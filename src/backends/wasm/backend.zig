const std = @import("std");
const shared = @import("../shared.zig");
const lib = @import("../../capy.zig");
const js = @import("js.zig");
const trait = @import("../../trait.zig");

const lasting_allocator = lib.internal.lasting_allocator;

const EventType = shared.BackendEventType;
const EventFunctions = shared.EventFunctions(@This());
const MouseButton = shared.MouseButton;

// What the backend exports
pub const PeerType = *@import("common.zig").GuiWidget;

const Events = @import("common.zig").Events;

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

pub const Monitor = @import("Monitor.zig");
pub const Window = @import("Window.zig");
pub const Container = @import("Container.zig");
pub const TextField = @import("TextField.zig");
pub const Label = @import("Label.zig");
pub const Button = @import("Button.zig");
pub const Slider = @import("Slider.zig");
pub const Canvas = @import("Canvas.zig");
pub const Dropdown = @import("Dropdown.zig");
pub const ImageData = @import("ImageData.zig");

pub const AudioGenerator = struct {
    source: js.AudioSourceId,
    buffers: [][]f32,

    pub fn create(sampleRate: f32) !AudioGenerator {
        const allocator = lib.internal.lasting_allocator;
        const channels = 2;
        const channelDatas = try allocator.alloc([]f32, channels);
        for (channelDatas) |*buffer| {
            buffer.* = try allocator.alloc(f32, 4410); // 0.1 seconds of buffer
            @memset(buffer.*, 0);
        }
        return AudioGenerator{
            .source = js.createSource(sampleRate, 0.1),
            .buffers = channelDatas,
        };
    }

    pub fn getBuffer(self: AudioGenerator, channel: u16) []f32 {
        return self.buffers[channel];
    }

    pub fn copyBuffer(self: AudioGenerator, channel: u16) void {
        js.audioCopyToChannel(
            self.source,
            self.buffers[channel].ptr,
            self.buffers[channel].len * @sizeOf(f32),
            channel,
        );
    }

    pub fn doneWrite(self: AudioGenerator) void {
        js.uploadAudio(self.source);
    }

    pub fn deinit(self: AudioGenerator) void {
        for (self.buffers) |buffer| {
            lib.internal.lasting_allocator.free(buffer);
        }
        lib.internal.lasting_allocator.free(self.buffers);
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

var stopExecution = false;

// Temporary execution until async is added back in Zig
pub fn runStep(step: shared.EventLoopStep) bool {
    _ = step;
    js.yield();
    while (js.hasEvent()) {
        const eventId = js.popEvent();
        switch (js.getEventType(eventId)) {
            .UpdateAudio => {
                lib.audio.backendUpdate();
            },
            .WindowTick => {
                if (@import("Window.zig").globalWindow) |window| {
                    if (window.peer.user.propertyChangeHandler) |handler| {
                        const value: u64 = 0;
                        handler("tick_id", &value, window.peer.userdata);
                    }
                    if (window.child) |child| {
                        child.processEventFn(child.object, eventId);
                    }
                }
            },
            else => {
                if (@import("Window.zig").globalWindow) |window| {
                    if (window.child) |child| {
                        child.processEventFn(child.object, eventId);
                    }
                }
            },
        }
    }
    return !stopExecution;
}

fn executeMain() void {
    const mainFn = @import("root").main;
    const ReturnType = @typeInfo(@TypeOf(mainFn)).@"fn".return_type.?;
    if (ReturnType == void) {
        mainFn();
    } else {
        mainFn() catch |err| @panic(@errorName(err));
    }
    js.stopExecution();
    stopExecution = true;
}

// Execution

// The following WASI Preview 1 functions are implemented on JS's side:
// - environ_sizes_get
// - environ_get
// - clock_time_get
// - clock_res_get
// - poll_oneoff (only for CLOCK pollables!)
// - path_open
// - fd_write (FOR STANDARD OUTPUT AND STANDARD ERROR ONLY!)
// - fd_read
// - fd_seek

pub const backendExport = struct {
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
        @setRuntimeSafety(false);
        js.print(msg);

        //@breakpoint();
        js.stopExecution();
        stopExecution = true;
        while (true) {}
    }

    pub export fn _start() callconv(.C) void {
        executeMain();
    }
};
