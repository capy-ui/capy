const std = @import("std");

const c = @import("c.zig");

const OutputStreamConfig = @import("audio.zig").OutputStreamConfig;
const StreamLayout = @import("audio.zig").StreamLayout;

const audio_log = std.log.scoped(.audio);

// OpenSLES support
pub const OpenSL = struct {
    // Global variables
    var init_sl_counter: usize = 0;
    var engine_object: c.SLObjectItf = undefined;
    var engine: c.SLEngineItf = undefined;

    var output_mix: c.SLObjectItf = undefined;
    var output_mix_itf: c.SLOutputMixItf = undefined;

    pub const OutputStream = struct {
        config: OutputStreamConfig,
        player: c.SLObjectItf,
        play_itf: c.SLPlayItf,
        buffer_queue_itf: c.SLAndroidSimpleBufferQueueItf,
        state: c.SLAndroidSimpleBufferQueueState,

        audio_sink: c.SLDataSink,
        locator_outputmix: c.SLDataLocator_OutputMix,

        audio_source: c.SLDataSource,
        buffer_queue: c.SLDataLocator_BufferQueue,
        pcm: c.SLDataFormat_PCM,

        buffer: []i16,
        buffer_index: usize,
        mutex: std.Thread.Mutex,
        allocator: std.mem.Allocator,

        // Must be initialized using OpenSL.getOutputStream

        pub fn stop(output_stream: *OutputStream) void {
            checkResult(output_stream.play_itf.*.*.SetPlayState.?(output_stream.play_itf, c.SL_PLAYSTATE_STOPPED)) catch |e| {
                audio_log.err("Error stopping stream {s}", .{@errorName(e)});
            };
        }

        pub fn deinit(output_stream: *OutputStream) void {
            output_stream.player.*.*.Destroy.?(output_stream.player);
            output_stream.allocator.free(output_stream.buffer);
        }

        pub fn start(output_stream: *OutputStream) !void {
            // Get player interface
            try checkResult(output_stream.player.*.*.GetInterface.?(
                output_stream.player,
                c.SL_IID_PLAY,
                @ptrCast(*anyopaque, &output_stream.play_itf),
            ));

            // Get buffer queue interface
            try checkResult(output_stream.player.*.*.GetInterface.?(
                output_stream.player,
                c.SL_IID_ANDROIDSIMPLEBUFFERQUEUE,
                @ptrCast(*anyopaque, &output_stream.buffer_queue_itf),
            ));

            // Register callback
            try checkResult(output_stream.buffer_queue_itf.*.*.RegisterCallback.?(
                output_stream.buffer_queue_itf,
                bufferQueueCallback,
                @ptrCast(*anyopaque, output_stream),
            ));

            // Enqueue a few buffers to get the ball rollng
            var i: usize = 0;
            while (i < output_stream.config.buffer_count) : (i += 1) {
                try checkResult(output_stream.buffer_queue_itf.*.*.Enqueue.?(
                    output_stream.buffer_queue_itf,
                    &output_stream.buffer[output_stream.buffer_index],
                    @intCast(u32, output_stream.config.buffer_size.? * (output_stream.pcm.containerSize / 8)),
                ));
                output_stream.buffer_index += output_stream.config.buffer_size.?;
            }

            output_stream.buffer_index = (output_stream.buffer_index + output_stream.config.buffer_size.?) % output_stream.buffer.len;

            // Start playing queued audio buffers
            try checkResult(output_stream.play_itf.*.*.SetPlayState.?(output_stream.play_itf, c.SL_PLAYSTATE_PLAYING));

            audio_log.info("started opensl output stream", .{});
        }
    };

    pub fn bufferQueueCallback(queue_itf: c.SLAndroidSimpleBufferQueueItf, user_data: ?*anyopaque) callconv(.C) void {
        var output_stream = @ptrCast(*OutputStream, @alignCast(@alignOf(OutputStream), user_data));

        // Lock the mutex to prevent race conditions
        output_stream.mutex.lock();
        defer output_stream.mutex.unlock();

        var buffer = output_stream.buffer[output_stream.buffer_index .. output_stream.buffer_index + output_stream.config.buffer_size.?];

        for (buffer) |*frame| {
            frame.* = 0;
        }

        var stream_layout = StreamLayout{
            .sample_rate = output_stream.pcm.samplesPerSec / 1000,
            .channel_count = output_stream.pcm.numChannels,
            .buffer = .{ .Int16 = buffer },
        };

        output_stream.config.callback(stream_layout, output_stream.config.user_data);

        checkResult(queue_itf.*.*.Enqueue.?(
            queue_itf,
            @ptrCast(*anyopaque, buffer.ptr),
            @intCast(c.SLuint32, (output_stream.pcm.containerSize / 8) * buffer.len),
        )) catch |e| {
            audio_log.err("Error enqueueing buffer! {s}", .{@errorName(e)});
        };

        output_stream.buffer_index = (output_stream.buffer_index + output_stream.config.buffer_size.?) % output_stream.buffer.len;
    }

    pub fn init() SLError!void {
        init_sl_counter += 1;
        if (init_sl_counter == 1) {
            try printInterfaces();
            errdefer init_sl_counter -= 1; // decrement counter on failure

            // Get engine object
            try checkResult(c.slCreateEngine(&engine_object, 0, null, 0, null, null));

            // Initialize engine object
            try checkResult(engine_object.*.*.Realize.?(engine_object, c.SL_BOOLEAN_FALSE));
            errdefer engine_object.*.*.Destroy.?(engine_object);

            // Get engine interface
            try checkResult(engine_object.*.*.GetInterface.?(engine_object, c.SL_IID_ENGINE, @ptrCast(*anyopaque, &engine)));
            try printEngineInterfaces();
            try printEngineExtensions();

            // Get OutputMix object
            try checkResult(engine.*.*.CreateOutputMix.?(engine, &output_mix, 0, null, null));
            try checkResult(output_mix.*.*.Realize.?(output_mix, c.SL_BOOLEAN_FALSE));
            errdefer output_mix.*.*.Destroy.?(output_mix);

            // Get OutputMix interface
            try checkResult(output_mix.*.*.GetInterface.?(output_mix, c.SL_IID_OUTPUTMIX, @ptrCast(*anyopaque, &output_mix_itf)));
        }
    }

    pub fn deinit() void {
        std.debug.assert(init_sl_counter > 0);

        // spinlock lock
        {
            init_sl_counter -= 1;
            if (init_sl_counter == 0) {
                output_mix.*.*.Destroy.?(output_mix);
                engine_object.*.*.Destroy.?(engine_object);
            }
        }
        // spinlock unlock
    }

    pub fn getOutputStream(allocator: std.mem.Allocator, conf: OutputStreamConfig) !*OutputStream {
        // TODO: support multiple formats
        std.debug.assert(conf.sample_format == .Int16);

        var config = conf;
        config.buffer_size = config.buffer_size orelse 256;
        config.sample_rate = config.sample_rate orelse 44100;

        // Allocate memory for audio buffer
        // TODO: support other formats
        var buffers = try allocator.alloc(i16, config.buffer_size.? * config.buffer_count);
        errdefer allocator.free(buffers);

        for (buffers) |*sample| {
            sample.* = 0;
        }

        // Initialize the context for Buffer queue callbacks
        var output_stream = try allocator.create(OutputStream);
        output_stream.* = OutputStream{
            // We don't have these values yet
            .player = undefined,
            .play_itf = undefined,
            .state = undefined,
            .buffer_queue_itf = undefined,

            // Store user defined callback information
            .config = config,

            // Store pointer to audio buffer
            .buffer = buffers,
            .buffer_index = 0,

            // Setup the format of the content in the buffer queue
            .buffer_queue = .{
                .locatorType = c.SL_DATALOCATOR_BUFFERQUEUE,
                .numBuffers = @intCast(u32, config.buffer_count),
            },
            .pcm = .{
                .formatType = c.SL_DATAFORMAT_PCM,
                .numChannels = @intCast(u32, config.channel_count),
                .samplesPerSec = config.sample_rate.? * 1000, // OpenSL ES uses milliHz instead of Hz, for some reason
                .bitsPerSample = switch (config.sample_format) {
                    .Uint8 => c.SL_PCMSAMPLEFORMAT_FIXED_8,
                    .Int16 => c.SL_PCMSAMPLEFORMAT_FIXED_16,
                    .Float32 => c.SL_PCMSAMPLEFORMAT_FIXED_32,
                },
                .containerSize = switch (config.sample_format) {
                    .Uint8 => 8,
                    .Int16 => 16,
                    .Float32 => 32,
                },
                .channelMask = c.SL_SPEAKER_FRONT_CENTER, // TODO
                .endianness = c.SL_BYTEORDER_LITTLEENDIAN, // TODO

            },

            // Configure audio source
            .audio_source = .{
                .pFormat = @ptrCast(*anyopaque, &output_stream.pcm),
                .pLocator = @ptrCast(*anyopaque, &output_stream.buffer_queue),
            },
            .locator_outputmix = .{
                .locatorType = c.SL_DATALOCATOR_OUTPUTMIX,
                .outputMix = output_mix,
            },
            // Configure audio output
            .audio_sink = .{
                .pLocator = @ptrCast(*anyopaque, &output_stream.locator_outputmix),
                .pFormat = null,
            },

            // Thread safety
            .mutex = std.Thread.Mutex{},

            .allocator = allocator,
        };

        // Create the music player
        try checkResult(engine.*.*.CreateAudioPlayer.?(
            engine,
            &output_stream.player,
            &output_stream.audio_source,
            &output_stream.audio_sink,
            1,
            &[_]c.SLInterfaceID{c.SL_IID_BUFFERQUEUE},
            &[_]c.SLboolean{c.SL_BOOLEAN_TRUE},
        ));

        // Realize the player interface
        try checkResult(output_stream.player.*.*.Realize.?(output_stream.player, c.SL_BOOLEAN_FALSE));

        // Return to user for them to start
        return output_stream;
    }

    const Result = enum(u32) {
        Success = c.SL_RESULT_SUCCESS,
        PreconditionsViolated = c.SL_RESULT_PRECONDITIONS_VIOLATED,
        ParameterInvalid = c.SL_RESULT_PARAMETER_INVALID,
        MemoryFailure = c.SL_RESULT_MEMORY_FAILURE,
        ResourceError = c.SL_RESULT_RESOURCE_ERROR,
        ResourceLost = c.SL_RESULT_RESOURCE_LOST,
        IoError = c.SL_RESULT_IO_ERROR,
        BufferInsufficient = c.SL_RESULT_BUFFER_INSUFFICIENT,
        ContentCorrupted = c.SL_RESULT_CONTENT_CORRUPTED,
        ContentUnsupported = c.SL_RESULT_CONTENT_UNSUPPORTED,
        ContentNotFound = c.SL_RESULT_CONTENT_NOT_FOUND,
        PermissionDenied = c.SL_RESULT_PERMISSION_DENIED,
        FeatureUnsupported = c.SL_RESULT_FEATURE_UNSUPPORTED,
        InternalError = c.SL_RESULT_INTERNAL_ERROR,
        UnknownError = c.SL_RESULT_UNKNOWN_ERROR,
        OperationAborted = c.SL_RESULT_OPERATION_ABORTED,
        ControlLost = c.SL_RESULT_CONTROL_LOST,
        _,
    };

    const SLError = error{
        PreconditionsViolated,
        ParameterInvalid,
        MemoryFailure,
        ResourceError,
        ResourceLost,
        IoError,
        BufferInsufficient,
        ContentCorrupted,
        ContentUnsupported,
        ContentNotFound,
        PermissionDenied,
        FeatureUnsupported,
        InternalError,
        UnknownError,
        OperationAborted,
        ControlLost,
    };

    pub fn checkResult(result: u32) SLError!void {
        const tag = std.meta.intToEnum(Result, result) catch return error.UnknownError;
        return switch (tag) {
            .Success => {},
            .PreconditionsViolated => error.PreconditionsViolated,
            .ParameterInvalid => error.ParameterInvalid,
            .MemoryFailure => error.MemoryFailure,
            .ResourceError => error.ResourceError,
            .ResourceLost => error.ResourceLost,
            .IoError => error.IoError,
            .BufferInsufficient => error.BufferInsufficient,
            .ContentCorrupted => error.ContentCorrupted,
            .ContentUnsupported => error.ContentUnsupported,
            .ContentNotFound => error.ContentNotFound,
            .PermissionDenied => error.PermissionDenied,
            .FeatureUnsupported => error.FeatureUnsupported,
            .InternalError => error.InternalError,
            .UnknownError => error.UnknownError,
            .OperationAborted => error.OperationAborted,
            .ControlLost => error.ControlLost,
            else => error.UnknownError,
        };
    }

    fn printInterfaces() !void {
        var interface_count: c.SLuint32 = undefined;
        try checkResult(c.slQueryNumSupportedEngineInterfaces(&interface_count));
        {
            var i: c.SLuint32 = 0;
            while (i < interface_count) : (i += 1) {
                var interface_id: c.SLInterfaceID = undefined;
                try checkResult(c.slQuerySupportedEngineInterfaces(i, &interface_id));
                const interface_tag = InterfaceID.fromIid(interface_id);
                if (interface_tag) |tag| {
                    audio_log.info("OpenSL engine interface id: {s}", .{@tagName(tag)});
                }
            }
        }
    }

    fn printEngineExtensions() !void {
        var extension_count: c.SLuint32 = undefined;
        try checkResult(engine.*.*.QueryNumSupportedExtensions.?(engine, &extension_count));
        {
            var i: c.SLuint32 = 0;
            while (i < extension_count) : (i += 1) {
                var extension_ptr: [4096]u8 = undefined;
                var extension_size: c.SLint16 = 4096;
                try checkResult(engine.*.*.QuerySupportedExtension.?(engine, i, &extension_ptr, &extension_size));
                var extension_name = extension_ptr[0..@intCast(usize, extension_size)];
                audio_log.info("OpenSL engine extension {}: {s}", .{ i, extension_name });
            }
        }
    }

    fn printEngineInterfaces() !void {
        var interface_count: c.SLuint32 = undefined;
        try checkResult(engine.*.*.QueryNumSupportedInterfaces.?(engine, c.SL_OBJECTID_ENGINE, &interface_count));
        {
            var i: c.SLuint32 = 0;
            while (i < interface_count) : (i += 1) {
                var interface_id: c.SLInterfaceID = undefined;
                try checkResult(engine.*.*.QuerySupportedInterfaces.?(engine, c.SL_OBJECTID_ENGINE, i, &interface_id));
                const interface_tag = InterfaceID.fromIid(interface_id);
                if (interface_tag) |tag| {
                    audio_log.info("OpenSL engine interface id: {s}", .{@tagName(tag)});
                } else {
                    audio_log.info("Unknown engine interface id: {}", .{interface_id.*});
                }
            }
        }
    }

    fn iidEq(iid1: c.SLInterfaceID, iid2: c.SLInterfaceID) bool {
        return iid1.*.time_low == iid2.*.time_low and
            iid1.*.time_mid == iid2.*.time_mid and
            iid1.*.time_hi_and_version == iid2.*.time_hi_and_version and
            iid1.*.clock_seq == iid2.*.clock_seq and
            iid1.*.time_mid == iid2.*.time_mid and
            std.mem.eql(u8, &iid1.*.node, &iid2.*.node);
    }

    const InterfaceID = enum {
        AudioIODeviceCapabilities,
        Led,
        Vibra,
        MetadataExtraction,
        MetadataTraversal,
        DynamicSource,
        OutputMix,
        Play,
        PrefetchStatus,
        PlaybackRate,
        Seek,
        Record,
        Equalizer,
        Volume,
        DeviceVolume,
        Object,
        BufferQueue,
        PresetReverb,
        EnvironmentalReverb,
        EffectSend,
        _3DGrouping,
        _3DCommit,
        _3DLocation,
        _3DDoppler,
        _3DSource,
        _3DMacroscopic,
        MuteSolo,
        DynamicInterfaceManagement,
        MidiMessage,
        MidiTempo,
        MidiMuteSolo,
        MidiTime,
        AudioDecoderCapabilities,
        AudioEncoder,
        AudioEncoderCapabilities,
        BassBoost,
        Pitch,
        RatePitch,
        Virtualizer,
        Visualization,
        Engine,
        EngineCapabilities,
        ThreadSync,
        AndroidEffect,
        AndroidEffectSend,
        AndroidEffectCapabilities,
        AndroidConfiguration,
        AndroidSimpleBufferQueue,
        AndroidBufferQueueSource,
        AndroidAcousticEchoCancellation,
        AndroidAutomaticGainControl,
        AndroidNoiseSuppresssion,
        fn fromIid(iid: c.SLInterfaceID) ?InterfaceID {
            if (iidEq(iid, c.SL_IID_NULL)) return null;
            if (iidEq(iid, c.SL_IID_AUDIOIODEVICECAPABILITIES)) return .AudioIODeviceCapabilities;
            if (iidEq(iid, c.SL_IID_LED)) return .Led;
            if (iidEq(iid, c.SL_IID_VIBRA)) return .Vibra;
            if (iidEq(iid, c.SL_IID_METADATAEXTRACTION)) return .MetadataExtraction;
            if (iidEq(iid, c.SL_IID_METADATATRAVERSAL)) return .MetadataTraversal;
            if (iidEq(iid, c.SL_IID_DYNAMICSOURCE)) return .DynamicSource;
            if (iidEq(iid, c.SL_IID_OUTPUTMIX)) return .OutputMix;
            if (iidEq(iid, c.SL_IID_PLAY)) return .Play;
            if (iidEq(iid, c.SL_IID_PREFETCHSTATUS)) return .PrefetchStatus;
            if (iidEq(iid, c.SL_IID_PLAYBACKRATE)) return .PlaybackRate;
            if (iidEq(iid, c.SL_IID_SEEK)) return .Seek;
            if (iidEq(iid, c.SL_IID_RECORD)) return .Record;
            if (iidEq(iid, c.SL_IID_EQUALIZER)) return .Equalizer;
            if (iidEq(iid, c.SL_IID_VOLUME)) return .Volume;
            if (iidEq(iid, c.SL_IID_DEVICEVOLUME)) return .DeviceVolume;
            if (iidEq(iid, c.SL_IID_OBJECT)) return .Object;
            if (iidEq(iid, c.SL_IID_BUFFERQUEUE)) return .BufferQueue;
            if (iidEq(iid, c.SL_IID_PRESETREVERB)) return .PresetReverb;
            if (iidEq(iid, c.SL_IID_ENVIRONMENTALREVERB)) return .EnvironmentalReverb;
            if (iidEq(iid, c.SL_IID_EFFECTSEND)) return .EffectSend;
            if (iidEq(iid, c.SL_IID_3DGROUPING)) return ._3DGrouping;
            if (iidEq(iid, c.SL_IID_3DCOMMIT)) return ._3DCommit;
            if (iidEq(iid, c.SL_IID_3DLOCATION)) return ._3DLocation;
            if (iidEq(iid, c.SL_IID_3DDOPPLER)) return ._3DDoppler;
            if (iidEq(iid, c.SL_IID_3DSOURCE)) return ._3DSource;
            if (iidEq(iid, c.SL_IID_3DMACROSCOPIC)) return ._3DMacroscopic;
            if (iidEq(iid, c.SL_IID_MUTESOLO)) return .MuteSolo;
            if (iidEq(iid, c.SL_IID_DYNAMICINTERFACEMANAGEMENT)) return .DynamicInterfaceManagement;
            if (iidEq(iid, c.SL_IID_MIDIMESSAGE)) return .MidiMessage;
            if (iidEq(iid, c.SL_IID_MIDITEMPO)) return .MidiTempo;
            if (iidEq(iid, c.SL_IID_MIDIMUTESOLO)) return .MidiMuteSolo;
            if (iidEq(iid, c.SL_IID_MIDITIME)) return .MidiTime;
            if (iidEq(iid, c.SL_IID_AUDIODECODERCAPABILITIES)) return .AudioDecoderCapabilities;
            if (iidEq(iid, c.SL_IID_AUDIOENCODER)) return .AudioEncoder;
            if (iidEq(iid, c.SL_IID_AUDIOENCODERCAPABILITIES)) return .AudioEncoderCapabilities;
            if (iidEq(iid, c.SL_IID_BASSBOOST)) return .BassBoost;
            if (iidEq(iid, c.SL_IID_PITCH)) return .Pitch;
            if (iidEq(iid, c.SL_IID_RATEPITCH)) return .RatePitch;
            if (iidEq(iid, c.SL_IID_VIRTUALIZER)) return .Virtualizer;
            if (iidEq(iid, c.SL_IID_VISUALIZATION)) return .Visualization;
            if (iidEq(iid, c.SL_IID_ENGINE)) return .Engine;
            if (iidEq(iid, c.SL_IID_ENGINECAPABILITIES)) return .EngineCapabilities;
            if (iidEq(iid, c.SL_IID_THREADSYNC)) return .ThreadSync;
            if (iidEq(iid, c.SL_IID_ANDROIDEFFECT)) return .AndroidEffect;
            if (iidEq(iid, c.SL_IID_ANDROIDEFFECTSEND)) return .AndroidEffectSend;
            if (iidEq(iid, c.SL_IID_ANDROIDEFFECTCAPABILITIES)) return .AndroidEffectCapabilities;
            if (iidEq(iid, c.SL_IID_ANDROIDCONFIGURATION)) return .AndroidConfiguration;
            if (iidEq(iid, c.SL_IID_ANDROIDSIMPLEBUFFERQUEUE)) return .AndroidSimpleBufferQueue;
            if (iidEq(iid, c.SL_IID_ANDROIDBUFFERQUEUESOURCE)) return .AndroidBufferQueueSource;
            if (iidEq(iid, c.SL_IID_ANDROIDACOUSTICECHOCANCELLATION)) return .AndroidAcousticEchoCancellation;
            if (iidEq(iid, c.SL_IID_ANDROIDAUTOMATICGAINCONTROL)) return .AndroidAutomaticGainControl;
            if (iidEq(iid, c.SL_IID_ANDROIDNOISESUPPRESSION)) return .AndroidNoiseSuppresssion;
            return null;
        }
    };
};
