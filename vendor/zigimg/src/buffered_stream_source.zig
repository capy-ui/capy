const std = @import("std");

const DefaultBufferSize = 8 * 1024;

pub const DefaultBufferedStreamSourceReader = BufferedStreamSourceReader(DefaultBufferSize);
pub const DefaultBufferedStreamSourceWriter = BufferedStreamSourceWriter(DefaultBufferSize);

// An buffered stream that can read and seek StreamSource
pub fn BufferedStreamSourceReader(comptime BufferSize: usize) type {
    return struct {
        buffered_reader: std.io.BufferedReader(BufferSize, std.io.StreamSource.Reader),

        pub const ReadError = std.io.StreamSource.ReadError;
        pub const SeekError = std.io.StreamSource.SeekError;
        pub const GetSeekPosError = std.io.StreamSource.GetSeekPosError;

        const Self = @This();

        pub const Reader = std.io.Reader(*Self, ReadError, read);
        pub const SeekableStream = std.io.SeekableStream(
            *Self,
            SeekError,
            GetSeekPosError,
            seekTo,
            seekBy,
            getPos,
            getEndPos,
        );

        pub fn read(self: *Self, dest: []u8) ReadError!usize {
            return switch (self.buffered_reader.unbuffered_reader.context.*) {
                .buffer => |*actual_reader| actual_reader.read(dest),
                .const_buffer => |*actual_reader| actual_reader.read(dest),
                .file => self.buffered_reader.read(dest),
            };
        }

        pub fn seekTo(self: *Self, pos: u64) SeekError!void {
            switch (self.buffered_reader.unbuffered_reader.context.*) {
                .buffer => |*actual_reader| {
                    return actual_reader.seekTo(pos);
                },
                .const_buffer => |*actual_reader| {
                    return actual_reader.seekTo(pos);
                },
                .file => {
                    try self.buffered_reader.unbuffered_reader.context.seekTo(pos);
                    self.resetBufferedReader();
                },
            }
        }

        pub fn seekBy(self: *Self, amt: i64) SeekError!void {
            switch (self.buffered_reader.unbuffered_reader.context.*) {
                .buffer => |*actual_reader| {
                    return actual_reader.seekBy(amt);
                },
                .const_buffer => |*actual_reader| {
                    return actual_reader.seekBy(amt);
                },
                .file => {
                    const bytes_availables = self.buffered_reader.end - self.buffered_reader.start;
                    if (amt > 0) {
                        if (amt <= bytes_availables) {
                            self.buffered_reader.start += @intCast(amt);
                        } else {
                            try self.buffered_reader.unbuffered_reader.context.seekBy(amt - @as(i64, @intCast(bytes_availables)));
                            self.resetBufferedReader();
                        }
                    } else if (amt < 0) {
                        const absolute_amt = @abs(amt);
                        if (absolute_amt <= self.buffered_reader.start) {
                            self.buffered_reader.start -%= absolute_amt;
                        } else {
                            try self.buffered_reader.unbuffered_reader.context.seekBy(amt - @as(i64, @intCast(bytes_availables)));
                            self.resetBufferedReader();
                        }
                    }
                },
            }
        }

        pub fn getEndPos(self: *Self) GetSeekPosError!u64 {
            return self.buffered_reader.unbuffered_reader.context.getEndPos();
        }

        pub fn getPos(self: *Self) GetSeekPosError!u64 {
            switch (self.buffered_reader.unbuffered_reader.context.*) {
                .buffer => |*actual_reader| {
                    return actual_reader.getPos();
                },
                .const_buffer => |*actual_reader| {
                    return actual_reader.getPos();
                },
                .file => {
                    if (self.buffered_reader.unbuffered_reader.context.getPos()) |position| {
                        return position - (self.buffered_reader.end - self.buffered_reader.start);
                    } else |err| {
                        return err;
                    }
                },
            }
        }

        pub fn reader(self: *Self) Reader {
            return .{ .context = self };
        }

        pub fn seekableStream(self: *Self) SeekableStream {
            return .{ .context = self };
        }

        fn resetBufferedReader(self: *Self) void {
            self.buffered_reader.start = 0;
            self.buffered_reader.end = 0;
        }
    };
}

pub fn bufferedStreamSourceReader(stream: *std.io.StreamSource) BufferedStreamSourceReader(DefaultBufferSize) {
    return .{ .buffered_reader = .{ .unbuffered_reader = stream.reader() } };
}

pub fn bufferedStreamSourceReaderWithSize(comptime buffer_size: usize, stream: *std.io.StreamSource) BufferedStreamSourceReader(buffer_size) {
    return .{ .buffered_reader = .{ .unbuffered_reader = stream.reader() } };
}

// An buffered stream that can writer and seek StreamSource
pub fn BufferedStreamSourceWriter(comptime BufferSize: usize) type {
    return struct {
        buffered_writer: std.io.BufferedWriter(BufferSize, std.io.StreamSource.Writer),

        pub const WriteError = std.io.StreamSource.WriteError;
        pub const SeekError = std.io.StreamSource.SeekError;
        pub const GetSeekPosError = std.io.StreamSource.GetSeekPosError;

        const Self = @This();

        pub const Writer = std.io.Writer(*Self, WriteError, write);
        pub const SeekableStream = std.io.SeekableStream(
            *Self,
            SeekError,
            GetSeekPosError,
            seekTo,
            seekBy,
            getPos,
            getEndPos,
        );

        pub fn write(self: *Self, bytes: []const u8) WriteError!usize {
            return switch (self.buffered_writer.unbuffered_writer.context.*) {
                .buffer => |*actual_writer| actual_writer.write(bytes),
                .const_buffer => error.AccessDenied,
                .file => self.buffered_writer.write(bytes),
            };
        }

        pub fn seekTo(self: *Self, pos: u64) SeekError!void {
            switch (self.buffered_writer.unbuffered_writer.context.*) {
                .buffer => |*actual_writer| {
                    return actual_writer.seekTo(pos);
                },
                .const_buffer => |*actual_writer| {
                    return actual_writer.seekTo(pos);
                },
                .file => {
                    try self.buffered_writer.flush();
                    try self.buffered_writer.buffered_writer.context.seekTo(pos);
                },
            }
        }

        pub fn seekBy(self: *Self, amt: i64) SeekError!void {
            switch (self.buffered_writer.unbuffered_writer.context.*) {
                .buffer => |*actual_writer| {
                    return actual_writer.seekBy(amt);
                },
                .const_buffer => |*actual_writer| {
                    return actual_writer.seekBy(amt);
                },
                .file => {
                    if (amt < 0) {
                        const abs_amt = @abs(amt);
                        if (abs_amt <= self.buffered_writer.end) {
                            self.buffered_writer.end -= abs_amt;
                        } else {
                            self.buffered_writer.flush() catch {
                                return error.Unseekable;
                            };
                            try self.buffered_writer.unbuffered_writer.context.seekBy(amt);
                        }
                    } else {
                        const amt_usize: usize = @intCast(amt);

                        if (self.buffered_writer.end + amt_usize < self.buffered_writer.buf.len) {
                            self.buffered_writer.end += amt_usize;
                        } else {
                            self.buffered_writer.flush() catch {
                                return error.Unseekable;
                            };
                            try self.buffered_writer.unbuffered_writer.context.seekBy(amt);
                        }
                    }
                },
            }
        }

        pub fn getEndPos(self: *Self) GetSeekPosError!u64 {
            return self.buffered_writer.unbuffered_writer.context.getEndPos();
        }

        pub fn getPos(self: *Self) GetSeekPosError!u64 {
            switch (self.buffered_writer.unbuffered_writer.context.*) {
                .buffer => |*actual_writer| {
                    return actual_writer.getPos();
                },
                .const_buffer => |*actual_writer| {
                    return actual_writer.getPos();
                },
                .file => {
                    if (self.buffered_writer.unbuffered_writer.context.getPos()) |position| {
                        return position + self.buffered_writer.end;
                    } else |err| {
                        return err;
                    }
                },
            }
        }

        pub fn writer(self: *Self) Writer {
            return .{ .context = self };
        }

        pub fn seekableStream(self: *Self) SeekableStream {
            return .{ .context = self };
        }

        pub fn flush(self: *Self) WriteError!void {
            return switch (self.buffered_writer.unbuffered_writer.context.*) {
                .file => self.buffered_writer.flush(),
                else => {},
            };
        }
    };
}

pub fn bufferedStreamSourceWriter(stream: *std.io.StreamSource) BufferedStreamSourceWriter(DefaultBufferSize) {
    return .{ .buffered_writer = .{ .unbuffered_writer = stream.writer() } };
}

pub fn bufferedStreamSourceWriterWithSize(comptime buffer_size: usize, stream: *std.io.StreamSource) BufferedStreamSourceWriter(buffer_size) {
    return .{ .buffered_writer = .{ .unbuffered_writer = stream.writer() } };
}
