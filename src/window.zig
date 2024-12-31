const std = @import("std");
const backend = @import("backend.zig");
const internal = @import("internal.zig");
const listener = @import("listener.zig");
const Widget = @import("widget.zig").Widget;
// const ImageData = @import("image.zig").ImageData;
const MenuBar = @import("components/Menu.zig").MenuBar;
const Size = @import("data.zig").Size;
const Atom = @import("data.zig").Atom;
const EventSource = listener.EventSource;

const AnimationController = @import("AnimationController.zig");
const Monitor = @import("monitor.zig").Monitor;
const VideoMode = @import("monitor.zig").VideoMode;
const Display = struct { resolution: Size, dpi: u32 };

const isErrorUnion = @import("internal.zig").isErrorUnion;

const devices = std.StaticStringMap(Display).initComptime(.{
    .{ "iphone-13-mini", Display{ .resolution = Size.init(1080, 2340), .dpi = 476 } },
    .{ "iphone-13", Display{ .resolution = Size.init(1170, 2532), .dpi = 460 } },
    .{ "pixel-6", Display{ .resolution = Size.init(1080, 2400), .dpi = 411 } },
    .{ "pixel-6-pro", Display{ .resolution = Size.init(1440, 3120), .dpi = 512 } },
});

pub const Window = struct {
    peer: backend.Window,
    _child: ?*Widget = null,
    // TODO: make it call setPreferredSize, if resizing ended up doing a no-up then revert
    // 'size' to what it was before
    // TODO: maybe implement vetoable changes to make it work
    size: Atom(Size) = Atom(Size).of(Size.init(640, 480)),
    /// The maximum refresh rate of the screen the window is atleast partially in.
    /// For instance, if a window is on both screen A (60Hz) and B (144Hz) then the value of screenRefreshRate will be 144Hz.
    screenRefreshRate: Atom(f32) = Atom(f32).of(60),
    /// Event source called whenever a frame would be drawn.
    /// This can be used for synchronizing animations to the window's monitor's sync rate.
    on_frame: *EventSource,
    animation_controller: *AnimationController,
    visible: Atom(bool) = Atom(bool).of(false),

    pub const Feature = enum {
        Title,
        Icon,
        MenuBar,
    };

    pub fn init() !Window {
        const peer = try backend.Window.create();
        const on_frame = try EventSource.alloc(internal.lasting_allocator);
        var window = Window{
            .peer = peer,
            .on_frame = on_frame,
            .animation_controller = try AnimationController.init(
                internal.lasting_allocator,
                on_frame,
            ),
        };
        window.setSourceDpi(96);
        window.setPreferredSize(640, 480);
        try window.peer.setCallback(.Resize, sizeChanged);
        try window.peer.setCallback(.PropertyChange, propertyChanged);

        // TODO: call only when there is at least one listener on EventSource
        window.peer.registerTickCallback();

        return window;
    }

    pub fn show(self: *Window) void {
        self.peer.setUserData(self);
        self.peer.show();
        self.visible.set(true);
    }

    pub fn close(self: *Window) void {
        self.peer.close();
        self.visible.set(false);
    }

    /// wrappedContainer can be an error union, a pointer to the container or the container itself.
    pub inline fn set(self: *Window, wrappedContainer: anytype) anyerror!void {
        const container =
            if (comptime isErrorUnion(@TypeOf(wrappedContainer)))
            try wrappedContainer
        else
            wrappedContainer;
        self._child = internal.getWidgetFrom(container);
        self._child.?.ref();

        // Set the child's animation controller
        self._child.?.animation_controller.set(self.animation_controller);
        try self._child.?.show();
        self.peer.setChild(self._child.?.peer);
    }

    pub fn getChild(self: Window) ?*Widget {
        return self._child;
    }

    var did_invalid_warning = false;
    /// Attempt to resize the window to the given size.
    /// On certain platforms (e.g. mobile) or configurations (e.g. tiling window manager) this function might do nothing.
    pub fn setPreferredSize(self: *Window, width: u32, height: u32) void {
        const EMULATOR_KEY = "CAPY_MOBILE_EMULATED";
        if (std.process.hasEnvVar(internal.scratch_allocator, EMULATOR_KEY) catch return) {
            const id = std.process.getEnvVarOwned(internal.scratch_allocator, EMULATOR_KEY) catch unreachable;
            defer internal.scratch_allocator.free(id);
            if (devices.get(id)) |device| {
                self.peer.resize(@as(c_int, @intFromFloat(device.resolution.width)), @as(c_int, @intFromFloat(device.resolution.height)));
                self.setSourceDpi(device.dpi);
                return;
            } else if (!did_invalid_warning) {
                std.log.warn("Invalid property \"" ++ EMULATOR_KEY ++ "={s}\"", .{id});
                std.debug.print("Expected one of:\r\n", .{});
                for (devices.keys()) |key| {
                    std.debug.print("    - {s}\r\n", .{key});
                }
                did_invalid_warning = true;
            }
        }
        self.size.set(.{ .width = @floatFromInt(width), .height = @floatFromInt(height) });
        self.peer.setUserData(self);
        self.peer.resize(@as(c_int, @intCast(width)), @as(c_int, @intCast(height)));
    }

    fn sizeChanged(width: u32, height: u32, data: usize) void {
        const self = @as(*Window, @ptrFromInt(data));
        self.size.set(.{ .width = @floatFromInt(width), .height = @floatFromInt(height) });
    }

    fn propertyChanged(name: []const u8, value: *const anyopaque, data: usize) void {
        const self: *Window = @ptrFromInt(data);
        if (std.mem.eql(u8, name, "tick_id")) {
            self.on_frame.callListeners();
        } else if (std.mem.eql(u8, name, "visible")) {
            const bool_ptr: *const bool = @ptrCast(value);
            self.visible.set(bool_ptr.*);
        }
    }

    // TODO: minimumSize and maximumSize

    pub fn hasFeature(self: *Window, feature: Window.Feature) bool {
        _ = feature;
        _ = self;
        // TODO
        return true;
    }

    pub fn setTitle(self: *Window, title: [:0]const u8) void {
        self.peer.setTitle(title);
    }

    // pub fn setIcon(self: *Window, icon: *ImageData) void {
    //     self.peer.setIcon(icon.data.peer);
    // }

    pub fn setMenuBar(self: *Window, bar: MenuBar) void {
        self.peer.setMenuBar(bar);
    }

    pub const FullscreenMode = union(enum) {
        /// Unfullscreens the window if it was already fullscreened.
        none,
        /// Make the window fullscreen borderless on a given monitor, or on its current monitor if null.
        borderless: ?Monitor,
        /// Make the window exclusively fullscreen on a specific monitor and with a specific video mode.
        /// On systems where this is not supported, borderless fullscreen is used instead as a fallback.
        exclusive: struct { Monitor, VideoMode },
    };

    /// Set the fullscreen state of the window.
    pub fn setFullscreen(self: *Window, mode: FullscreenMode) void {
        switch (mode) {
            .none => self.peer.unfullscreen(),
            .borderless => |monitor| self.peer.setFullscreen(
                if (monitor) |mon| mon.peer else null,
                null,
            ),
            .exclusive => |tuple| self.peer.setFullscreen(tuple[0].peer, tuple[1]),
        }
    }

    /// Specify for which DPI the GUI was developed against.
    pub fn setSourceDpi(self: *Window, dpi: u32) void {
        self.peer.setSourceDpi(dpi);
    }

    pub fn deinit(self: *Window) void {
        if (self._child) |child| {
            child.unref();
        }
        self.animation_controller.deinit();
        self.on_frame.deinitAllListeners();
        internal.lasting_allocator.destroy(self.on_frame);
        self.peer.deinit();
    }
};
