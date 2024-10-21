//! Stub.

const std = @import("std");
const c = @import("gtk.zig");
const lib = @import("../../capy.zig");
const common = @import("common.zig");

const AudioGenerator = @This();

pub fn create(sampleRate: f32) !AudioGenerator {
    _ = sampleRate;
    return AudioGenerator{};
}

pub fn getBuffer(self: AudioGenerator, channel: u16) []f32 {
    _ = channel;
    _ = self;
    return &([0]f32{});
}

pub fn copyBuffer(self: AudioGenerator, channel: u16) void {
    _ = channel;
    _ = self;
}

pub fn doneWrite(self: AudioGenerator) void {
    _ = self;
}

pub fn deinit(self: AudioGenerator) void {
    _ = self;
}
