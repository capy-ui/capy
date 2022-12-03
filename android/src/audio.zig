const std = @import("std");
const build_options = @import("build_options");

const android = @import("c.zig");

const audio_log = std.log.scoped(.audio);

const Dummy = @import("dummy.zig").Dummy;

const OpenSL = if (build_options.enable_opensl) @import("opensl.zig").OpenSL else Dummy;
const AAudio = if (build_options.enable_aaudio) @import("aaudio.zig").AAudio else Dummy;

pub fn midiToFreq(note: usize) f64 {
    return std.math.pow(f64, 2, (@intToFloat(f64, note) - 49) / 12) * 440;
}

pub fn amplitudeTodB(amplitude: f64) f64 {
    return 20.0 * std.math.log10(amplitude);
}

pub fn dBToAmplitude(dB: f64) f64 {
    return std.math.pow(f64, 10.0, dB / 20.0);
}

pub const StreamLayout = struct {
    sample_rate: u32,
    channel_count: usize,
    buffer: union(enum) {
        Uint8: []u8,
        Int16: []i16,
        Float32: []f32,
    },
};

const StreamCallbackFn = *const fn (StreamLayout, *anyopaque) void;

pub const AudioManager = struct {};

pub const OutputStreamConfig = struct {
    // Leave null to use the the platforms native sampling rate
    sample_rate: ?u32 = null,
    sample_format: enum {
        Uint8,
        Int16,
        Float32,
    },
    buffer_size: ?usize = null,
    buffer_count: usize = 4,
    channel_count: usize = 1,
    callback: StreamCallbackFn,
    user_data: *anyopaque,
};

pub fn init() !void {
    if (build_options.enable_opensl) {
        try OpenSL.init();
    }
}

pub fn getOutputStream(allocator: std.mem.Allocator, config: OutputStreamConfig) !OutputStream {
    if (build_options.enable_aaudio) {
        return .{ .AAudio = try AAudio.getOutputStream(allocator, config) };
    }
    if (build_options.enable_opensl) {
        return .{ .OpenSL = try OpenSL.getOutputStream(allocator, config) };
    }
    return error.NoBackendsAvailable;
}

pub const OutputStream = union(enum) {
    OpenSL: *OpenSL.OutputStream,
    AAudio: *AAudio.OutputStream,

    pub fn stop(output_stream: @This()) void {
        switch (output_stream) {
            .OpenSL => |opensl| opensl.stop(),
            .AAudio => |aaudio| aaudio.stop(),
        }
    }

    pub fn deinit(output_stream: @This()) void {
        switch (output_stream) {
            .OpenSL => |opensl| opensl.deinit(),
            .AAudio => |aaudio| aaudio.deinit(),
        }
    }

    pub fn start(output_stream: @This()) !void {
        switch (output_stream) {
            .OpenSL => |opensl| try opensl.start(),
            .AAudio => |aaudio| try aaudio.start(),
        }
    }
};
