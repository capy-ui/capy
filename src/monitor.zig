const std = @import("std");
const internal = @import("internal.zig");
const backend = @import("backend.zig");
const ListAtom = @import("data.zig").ListAtom;

// TODO: when a monitor is removed, monitor.peer.deinit should be called
pub const Monitors = struct {
    /// List of all monitors that are connected
    pub var list: ListAtom(Monitor) = undefined;
    /// Lock used to ensure the backend is initialized only once (at least in debug mode)
    var initialized: std.debug.SafetyLock = .{};

    /// Init the subsystem by filling the monitor list and by listening to events indicating
    /// that a monitor is being added or removed.
    /// This function is called by `capy.init()`, so it doesn't need to be called manually.
    pub fn init() void {
        initialized.lock();
        Monitors.list = ListAtom(Monitor).init(internal.lasting_allocator);
        const peer_list = backend.Monitor.getList();
        for (peer_list) |*monitor_peer| {
            list.append(Monitor.init(monitor_peer)) catch @panic("OOM");
        }
    }

    pub fn getPrimary() Monitor {
        // TODO: correctly find the primary monitor based on the attributes given to capy by the backend
        return Monitors.list.get(0);
    }

    /// This function is called by `capy.deinit()`, so it doesn't need to be called manually.
    pub fn deinit() void {
        initialized.unlock();
        {
            var iterator = Monitors.list.iterate();
            defer iterator.deinit();
            while (iterator.next()) |monitor| {
                monitor.deinit();
            }
        }
        Monitors.list.deinit();
        backend.Monitor.deinitAllPeers();
    }
};

test "Monitors" {
    // NOTE: You don't need to initialize the API in user code. This is only for the testing environment.
    Monitors.init();
    defer Monitors.deinit();

    {
        var iterator = Monitors.list.iterate();
        defer iterator.deinit();

        std.log.info("Monitor(s):", .{});
        while (iterator.next()) |monitor| {
            std.log.info("  - Name: {s}", .{monitor.getName()});
        }
    }
}

pub const Monitor = struct {
    peer: *backend.Monitor,
    video_modes: []const VideoMode,

    fn init(peer: *backend.Monitor) Monitor {
        const video_modes = blk: {
            const n = peer.getNumberOfVideoModes();
            const modes = internal.lasting_allocator.alloc(VideoMode, n) catch @panic("OOM");
            for (0..n) |i| {
                const video_mode = peer.getVideoMode(i);
                modes[i] = video_mode;
            }
            break :blk modes;
        };

        return .{ .peer = peer, .video_modes = video_modes };
    }

    fn deinit(self: Monitor) void {
        internal.lasting_allocator.free(self.video_modes);
    }

    /// Returns a human-readable name for the monitor.
    pub fn getName(self: Monitor) []const u8 {
        return self.peer.getName();
    }

    /// Returns a unique name for this monitor and that is guarenteed to be the same
    /// even across different sessions / connections.
    pub fn getInternalName(self: Monitor) []const u8 {
        return self.peer.getInternalName();
    }

    /// Returns a floating point approximation of the monitor's refresh rate, in Hertz.
    pub fn getRefreshRate(self: Monitor) f32 {
        return @as(f32, @floatFromInt(self.getRefreshRateMillihertz())) / 1000.0;
    }

    /// Returns the exact value of the monitor's refresh rate, in milliHertz.
    /// For instance, for a  60 Hz screen, getRefreshRateMillihertz() returns 60000
    pub fn getRefreshRateMillihertz(self: Monitor) u32 {
        return self.peer.getRefreshRateMillihertz();
    }

    /// Returns a simulated DPI based on display scale that the application should use, it might not
    /// actually represent the number of dots per inch.
    /// Note: this includes OS-level zoom, so if the monitor's DPI is 96, and the zoom level is 125%,
    /// then the returned DPI will be 120.
    pub fn getDpi(self: Monitor) u32 {
        return self.peer.getDpi();
    }

    /// Returns the monitor's width expressed in device pixels.
    pub fn getWidth(self: Monitor) u32 {
        return self.peer.getWidth();
    }

    /// Returns the monitor's width expressed in device pixels.
    pub fn getHeight(self: Monitor) u32 {
        return self.peer.getHeight();
    }

    /// Returns the monitor's size expressed in device pixels.
    pub fn getSize(self: Monitor) struct { u32, u32 } {
        return .{ self.getWidth(), self.getHeight() };
    }

    test getSize {
        // NOTE: You don't need to initialize the API in user code. This is only for the testing environment.
        Monitors.init();
        defer Monitors.deinit();

        const monitor = Monitors.list.get(0);
        const width, const height = monitor.getSize();
        std.log.info("Monitor pixels: {d} px x {d} px", .{ width, height });
    }
};

pub const VideoMode = struct {
    /// The video mode's width expressed in device pixels
    width: u32,
    /// The video mode's height expressed in device pixels
    height: u32,
    /// The video mode's refresh rate expressed in millihertz.
    refresh_rate_millihertz: u32,
    /// The bit depth, in bits
    bit_depth: u8,
};
