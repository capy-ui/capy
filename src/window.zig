const std = @import("std");
const backend = @import("backend.zig");
const internal = @import("internal.zig");
const Widget = @import("widget.zig").Widget;
const ImageData = @import("image.zig").ImageData;
const MenuBar_Impl = @import("menu.zig").MenuBar_Impl;
const Size = @import("data.zig").Size;

const Display = struct {
    resolution: Size,
    dpi: u32
};

const devices = std.ComptimeStringMap(Display, .{
    .{ "iphone-13-mini", .{ .resolution = Size.init(1080, 2340), .dpi = 476 }},
    .{ "iphone-13", .{ .resolution = Size.init(1170, 2532), .dpi = 460 }},
    .{ "pixel-6", .{ .resolution = Size.init(1080, 2400), .dpi = 411 }},
    .{ "pixel-6-pro", .{ .resolution = Size.init(1440, 3120), .dpi = 512 }},
});

pub const Window = struct {
    peer: backend.Window,
    _child: ?Widget = null,

    pub fn init() !Window {
        const peer = try backend.Window.create();
        var window = Window{ .peer = peer };
        window.setSourceDpi(96);
        window.resize(640, 480);
        return window;
    }

    pub fn show(self: *Window) void {
        return self.peer.show();
    }

    pub fn close(self: *Window) void {
        return self.peer.close();
    }

    fn isErrorUnion(comptime T: type) bool {
        return switch (@typeInfo(T)) {
            .ErrorUnion => true,
            else => false,
        };
    }

    /// wrappedContainer can be an error union, a pointer to the container or the container itself.
    pub inline fn set(self: *Window, wrappedContainer: anytype) anyerror!void {
        var container =
            if (comptime isErrorUnion(@TypeOf(wrappedContainer)))
            try wrappedContainer
        else
            wrappedContainer;
        const ComponentType = @import("internal.zig").DereferencedType(@TypeOf(container));

        self._child = try @import("internal.zig").genericWidgetFrom(container);
        if (ComponentType != Widget) {
            self._child.?.as(ComponentType).dataWrappers.widget = &self._child.?;
        }

        try self._child.?.show();

        self.peer.setChild(self._child.?.peer);
    }

    pub fn getChild(self: Window) ?Widget {
        return self._child;
    }

    var did_invalid_warning = false;

    pub fn resize(self: *Window, width: u32, height: u32) void {
        const EMULATOR_KEY = "ZGT_MOBILE_EMULATION";
        if (std.process.hasEnvVarConstant(EMULATOR_KEY)) {
            const id = std.process.getEnvVarOwned(
                internal.scratch_allocator, EMULATOR_KEY) catch unreachable;
            defer internal.scratch_allocator.free(id);
            if (devices.get(id)) |device| {
                self.peer.resize(@intCast(c_int, device.resolution.width),
                    @intCast(c_int, device.resolution.height));
                self.setSourceDpi(device.dpi);
                return;
            } else if (!did_invalid_warning) {
                std.log.warn("Invalid property \"" ++ EMULATOR_KEY ++ "={s}\"", .{ id });
                std.debug.print("Expected one of:\r\n", .{});
                for (devices.kvs) |entry| {
                    std.debug.print("    - {s}\r\n", .{ entry.key });
                }
                did_invalid_warning = true;
            }
        }
        self.peer.resize(@intCast(c_int, width), @intCast(c_int, height));
    }

    pub fn setTitle(self: *Window, title: [:0]const u8) void {
        self.peer.setTitle(title);
    }

    pub fn setIcon(self: *Window, icon: *ImageData) void {
        self.peer.setIcon(icon.data.peer);
    }

    pub fn setIconName(self: *Window, name: [:0]const u8) void {
        self.peer.setIconName(name);
    }

    pub fn setMenuBar(self: *Window, bar: MenuBar_Impl) void {
        self.peer.setMenuBar(bar);
    }

    /// Specify for which DPI the GUI was developed against.
    pub fn setSourceDpi(self: *Window, dpi: u32) void {
        self.peer.setSourceDpi(dpi);
    }

    pub fn deinit(self: *Window) void {
        if (self._child) |*child| {
            child.deinit();
        }
    }
};
