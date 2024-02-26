//! Audio module with an high-level and low-level interface
// TODO: move to an external package? if possible with WASM and Android?
const std = @import("std");
const internal = @import("internal.zig");
const backend = @import("backend.zig");
pub const AudioWriteCallback = *const fn (generator: *const AudioGenerator, time: u64, n_frames: u32) void;

var generators = std.ArrayList(*AudioGenerator).init(internal.lasting_allocator);
var generatorsMutex = std.Thread.Mutex{};

pub const AudioGenerator = struct {
    write_callback: *const anyopaque, // due to a bug in zig compiler with false dependency loop
    /// Time in frames. Note that, by design, it overflows to 0 once the maximum is reached.
    time: u32 = 0,
    channels: u16,
    playing: bool = false,
    peer: backend.AudioGenerator,

    pub fn init(write_callback: AudioWriteCallback, channels: u16) !*AudioGenerator {
        const generator = internal.lasting_allocator.create(AudioGenerator) catch unreachable;
        const peer = try backend.AudioGenerator.create(44100.0);
        generator.* = .{ .write_callback = write_callback, .channels = channels, .peer = peer };
        return generator;
    }

    pub fn getBuffer(self: AudioGenerator, channel: u16) []f32 {
        return self.peer.getBuffer(channel);
    }

    pub fn register(self: *AudioGenerator) !void {
        // TODO: should it be registered automatically ?
        generatorsMutex.lock();
        defer generatorsMutex.unlock();

        try generators.append(self);
    }

    pub fn play(self: *AudioGenerator) void {
        self.playing = true;
    }

    pub fn stop(self: *AudioGenerator) void {
        self.playing = false;
    }

    pub fn onWriteRequested(self: *AudioGenerator, frames_requested: u32) void {
        const callback: AudioWriteCallback = @ptrCast(self.write_callback);
        callback(self, self.time, frames_requested);
        self.time += frames_requested;

        var channel: u16 = 0;
        while (channel < self.channels) : (channel += 1) {
            self.peer.copyBuffer(channel);
        }
        self.peer.doneWrite();
    }

    pub fn deinit(self: *AudioGenerator) void {
        self.stop();
        generatorsMutex.lock();
        generatorsMutex.unlock();

        if (std.mem.indexOfScalar(*AudioGenerator, generators.items, self)) |index| {
            generators.swapRemove(index);
        }
        self.peer.deinit();
        internal.lasting_allocator.destroy(self);
    }
};

pub const AudioPlayer = struct {
    source: []const u8,

    /// Stream and play the given audio file from the URL.
    pub fn play(self: AudioPlayer, source: []const u8) void {
        self.source = source;
        self.time = 0;
    }
};

/// Internal method.
pub fn backendUpdate() void {
    generatorsMutex.lock();
    defer generatorsMutex.unlock();
    for (generators.items) |generator| {
        generator.onWriteRequested(4410);
    }
}

pub fn deinit() void {
    generatorsMutex.lock();
    generators.deinit();
}
