const std = @import("std");

const c = @import("c.zig");

const OutputStreamConfig = @import("audio.zig").OutputStreamConfig;
const StreamLayout = @import("audio.zig").StreamLayout;

const audio_log = std.log.scoped(.audio);

pub const AAudio = struct {
    pub const OutputStream = struct {
        config: OutputStreamConfig,
        stream: ?*c.AAudioStream,

        pub fn start(output_stream: *@This()) !void {
            try checkResult(c.AAudioStream_requestStart(output_stream.stream));
        }

        pub fn stop(output_stream: *@This()) void {
            checkResult(c.AAudioStream_requestStop(output_stream.stream)) catch |e| {
                audio_log.err("Error stopping stream {s}", .{@errorName(e)});
            };
        }

        pub fn deinit(output_stream: *@This()) void {
            checkResult(c.AAudioStream_close(output_stream.stream)) catch |e| {
                audio_log.err("Error deiniting stream {s}", .{@errorName(e)});
            };
        }
    };

    fn dataCallback(
        stream: ?*c.AAudioStream,
        user_data: ?*anyopaque,
        audio_data: ?*anyopaque,
        num_frames: i32,
    ) callconv(.C) c.aaudio_data_callback_result_t {
        _ = stream;
        const output_stream = @as(*OutputStream, @ptrCast(@alignCast(@alignOf(OutputStream), user_data.?)));
        // TODO:
        // const audio_slice = @ptrCast([*]f32, @alignCast(@alignOf(f32), audio_data.?))[0..@intCast(usize, num_frames)];
        const audio_slice = @as([*]i16, @ptrCast(@alignCast(@alignOf(i16), audio_data.?)))[0..@as(usize, @intCast(num_frames))];

        for (audio_slice) |*frame| {
            frame.* = 0;
        }

        var stream_layout = StreamLayout{
            .sample_rate = output_stream.config.sample_rate.?,
            .channel_count = @as(usize, @intCast(output_stream.config.channel_count)),
            .buffer = .{ .Int16 = audio_slice },
        };

        output_stream.config.callback(stream_layout, output_stream.config.user_data);

        return c.AAUDIO_CALLBACK_RESULT_CONTINUE;
    }

    fn errorCallback(
        stream: ?*c.AAudioStream,
        user_data: ?*anyopaque,
        err: c.aaudio_result_t,
    ) callconv(.C) void {
        _ = stream;
        audio_log.err("AAudio Stream error! {}", .{err});
        if (err == c.AAUDIO_ERROR_DISCONNECTED) {
            const output_stream = @as(*OutputStream, @ptrCast(@alignCast(@alignOf(OutputStream), user_data.?)));
            _ = std.Thread.spawn(.{}, OutputStream.deinit, .{output_stream}) catch @panic("Error starting thread for AAudioOutputStream");
        }
    }

    pub fn getOutputStream(allocator: std.mem.Allocator, config: OutputStreamConfig) !*OutputStream {
        errdefer audio_log.err("Encountered an error with getting output stream", .{});
        // Create a stream builder
        var stream_builder: ?*c.AAudioStreamBuilder = null;
        checkResult(c.AAudio_createStreamBuilder(&stream_builder)) catch |e| {
            audio_log.err("Couldn't create audio stream builder: {s}", .{@errorName(e)});
            return e;
        };
        defer checkResult(c.AAudioStreamBuilder_delete(stream_builder)) catch |e| {
            // TODO
            audio_log.err("Issue with deleting stream builder: {s}", .{@errorName(e)});
        };

        var output_stream = try allocator.create(OutputStream);
        output_stream.* = OutputStream{
            .config = config,
            .stream = undefined,
        };

        // Configure the stream
        c.AAudioStreamBuilder_setFormat(stream_builder, switch (config.sample_format) {
            .Uint8 => return error.Unsupported,
            .Int16 => c.AAUDIO_FORMAT_PCM_I16,
            .Float32 => c.AAUDIO_FORMAT_PCM_FLOAT,
        });
        c.AAudioStreamBuilder_setChannelCount(stream_builder, @as(i32, @intCast(config.channel_count)));
        c.AAudioStreamBuilder_setPerformanceMode(stream_builder, c.AAUDIO_PERFORMANCE_MODE_LOW_LATENCY);
        c.AAudioStreamBuilder_setDataCallback(stream_builder, dataCallback, output_stream);
        c.AAudioStreamBuilder_setErrorCallback(stream_builder, errorCallback, output_stream);

        if (config.sample_rate) |rate| c.AAudioStreamBuilder_setSampleRate(stream_builder, @as(i32, @intCast(rate)));
        if (config.buffer_size) |size| c.AAudioStreamBuilder_setFramesPerDataCallback(stream_builder, @as(i32, @intCast(size)));

        // Open the stream
        checkResult(c.AAudioStreamBuilder_openStream(stream_builder, &output_stream.stream)) catch |e| {
            audio_log.err("Issue with opening stream: {s}", .{@errorName(e)});
            return e;
        };

        // Save the details of the stream
        output_stream.config.sample_rate = @as(u32, @intCast(c.AAudioStream_getSampleRate(output_stream.stream)));
        output_stream.config.buffer_size = @as(usize, @intCast(c.AAudioStream_getFramesPerBurst(output_stream.stream)));

        var res = c.AAudioStream_setBufferSizeInFrames(output_stream.stream, @as(i32, @intCast(output_stream.config.buffer_count * output_stream.config.buffer_size.?)));
        if (res < 0) {
            checkResult(res) catch |e| {
                audio_log.err("Issue with setting buffer size in frames stream: {s}", .{@errorName(e)});
                return e;
            };
        } else {
            // TODO: store buffer size somewhere
            // output_stream.config.
        }

        audio_log.info("Got AAudio OutputStream", .{});

        return output_stream;
    }

    pub const AAudioError = error{
        Base,
        Disconnected,
        IllegalArgument,
        Internal,
        InvalidState,
        InvalidHandle,
        Unimplemented,
        Unavailable,
        NoFreeHandles,
        NoMemory,
        Null,
        Timeout,
        WouldBlock,
        InvalidFormat,
        OutOfRange,
        NoService,
        InvalidRate,
        Unknown,
    };

    pub fn checkResult(result: c.aaudio_result_t) AAudioError!void {
        return switch (result) {
            c.AAUDIO_OK => {},
            c.AAUDIO_ERROR_BASE => error.Base,
            c.AAUDIO_ERROR_DISCONNECTED => error.Disconnected,
            c.AAUDIO_ERROR_ILLEGAL_ARGUMENT => error.IllegalArgument,
            c.AAUDIO_ERROR_INTERNAL => error.Internal,
            c.AAUDIO_ERROR_INVALID_STATE => error.InvalidState,
            c.AAUDIO_ERROR_INVALID_HANDLE => error.InvalidHandle,
            c.AAUDIO_ERROR_UNIMPLEMENTED => error.Unimplemented,
            c.AAUDIO_ERROR_UNAVAILABLE => error.Unavailable,
            c.AAUDIO_ERROR_NO_FREE_HANDLES => error.NoFreeHandles,
            c.AAUDIO_ERROR_NO_MEMORY => error.NoMemory,
            c.AAUDIO_ERROR_NULL => error.Null,
            c.AAUDIO_ERROR_TIMEOUT => error.Timeout,
            c.AAUDIO_ERROR_WOULD_BLOCK => error.WouldBlock,
            c.AAUDIO_ERROR_INVALID_FORMAT => error.InvalidFormat,
            c.AAUDIO_ERROR_OUT_OF_RANGE => error.OutOfRange,
            c.AAUDIO_ERROR_NO_SERVICE => error.NoService,
            c.AAUDIO_ERROR_INVALID_RATE => error.InvalidRate,
            else => error.Unknown,
        };
    }
};
