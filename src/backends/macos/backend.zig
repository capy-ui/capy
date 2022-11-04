const std = @import("std");
const shared = @import("../shared.zig");
const lib = @import("../../main.zig");
const objc = @import("objc.zig");

const EventFunctions = shared.EventFunctions(@This());
const EventType = shared.BackendEventType;
const BackendError = shared.BackendError;
const MouseButton = shared.MouseButton;
//pub const PeerType = *c.GtkWidget;
pub const PeerType = *opaque {};

var activeWindows = std.atomic.Atomic(usize).init(0);
var hasInit: bool = false;

pub fn init() BackendError!void {
    if (!hasInit) {
        hasInit = true;
    }
}

pub fn showNativeMessageDialog(msgType: shared.MessageType, comptime fmt: []const u8, args: anytype) void {
    const msg = std.fmt.allocPrintZ(lib.internal.scratch_allocator, fmt, args) catch {
        std.log.err("Could not launch message dialog, original text: " ++ fmt, args);
        return;
    };
    defer lib.internal.scratch_allocator.free(msg);
    _ = msgType;
    @panic("TODO: message dialogs on macOS");
}

/// user data used for handling events
pub const EventUserData = struct {
    user: EventFunctions = .{},
    class: EventFunctions = .{},
    userdata: usize = 0,
    classUserdata: usize = 0,
    peer: PeerType,
    focusOnClick: bool = false,
};

pub inline fn getEventUserData(peer: PeerType) *EventUserData {
    _ = peer;
    //return @ptrCast(*EventUserData, @alignCast(@alignOf(EventUserData), c.g_object_get_data(@ptrCast(*c.GObject, peer), "eventUserData").?));
}

pub fn Events(comptime T: type) type {
    _ = T;
    return struct {};
}

pub const Window = struct {
    source_dpi: u32 = 96,
    scale: f32 = 1.0,
    peer: objc.id,

    pub usingnamespace Events(Window);

    pub fn create() BackendError!Window {
        const NSWindow = objc.getClass("NSWindow") catch return BackendError.InitializationError;
        const rect = objc.NSRectMake(0, 0, 100, 100);
        const style: c_ulong = 1; // titled
        const backing: c_ulong = 2; // NSBackingStoreBuffered
        const flag: c_int = @boolToInt(false);

        return Window{
            .peer = objc.msgSendByName(objc.id, NSWindow, "initWithContentRect:styleMask:backing:defer:", .{ rect, style, backing, flag }) catch return BackendError.UnknownError,
        };
    }

    pub fn resize(self: *Window, width: c_int, height: c_int) void {
        _ = self;
        _ = width;
        _ = height;
    }

    pub fn setTitle(self: *Window, title: [*:0]const u8) void {
        _ = self;
        _ = title;
    }

    pub fn setChild(self: *Window, peer: ?PeerType) void {
        _ = self;
        _ = peer;
    }

    pub fn setSourceDpi(self: *Window, dpi: u32) void {
        self.source_dpi = 96;
        // TODO
        const resolution = @as(f32, 96.0);
        self.scale = resolution / @intToFloat(f32, dpi);
    }

    pub fn show(self: *Window) void {
        std.log.info("show window", .{});
        objc.msgSendByName(void, self.peer, "makeKeyAndOrderFront", .{ @as(objc.id, undefined) }) catch unreachable;
        std.log.info("showed window", .{});
        _ = activeWindows.fetchAdd(1, .Release);
    }

    pub fn close(self: *Window) void {
        _ = self;
        @panic("TODO: close window");
    }
};

pub fn postEmptyEvent() void {
    @panic("TODO: postEmptyEvent");
}

pub fn runStep(step: shared.EventLoopStep) bool {
    _ = step;
    return activeWindows.load(.Acquire) != 0;
}
