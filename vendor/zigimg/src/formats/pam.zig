const std = @import("std");
const io = std.io;
const mem = std.mem;
const math = std.math;
const ascii = std.ascii;
const fmt = std.fmt;
const meta = std.meta;
const Allocator = std.mem.Allocator;
const buffered_stream_source = @import("../buffered_stream_source.zig");
const color = @import("../color.zig");
const FormatInterface = @import("../FormatInterface.zig");
const PixelStorage = color.PixelStorage;
const PixelFormat = @import("../pixel_format.zig").PixelFormat;
const Image = @import("../Image.zig");
const ImageError = Image.Error;
const ImageReadError = Image.ReadError;
const ImageWriteError = Image.WriteError;
const utils = @import("../utils.zig");

/// Represents all supported values for `TUPLTYPE`.
const TupleType = enum {
    mono,
    mono_a,
    gray,
    gray_a,
    rgb,
    rgb_a,

    /// Returns the `TupleType` corresponding to `string`, or
    /// `error.Unsupported` if it is unknown.
    fn fromString(string: []const u8) error{Unsupported}!TupleType {
        // zig fmt: off
        return if(mem.eql(u8, string, "BLACKANDWHITE")) .mono
        else if(mem.eql(u8, string, "BLACKANDWHITE_ALPHA")) .mono_a
        else if(mem.eql(u8, string, "GRAYSCALE")) .gray
        else if(mem.eql(u8, string, "GRAYSCALE_ALPHA")) .gray_a
        else if(mem.eql(u8, string, "RGB")) .rgb
        else if(mem.eql(u8, string, "RGB_ALPHA")) .rgb_a
        else error.Unsupported; // Unknown tuple type
        // zig fmt: on
    }

    /// Returns the `TUPLTYPE` string representation of `tuple_type`.
    fn toString(tuple_type: TupleType) []const u8 {
        return switch (tuple_type) {
            .mono => "BLACKANDWHITE",
            .mono_a => "BLACKANDWHITE_ALPHA",
            .gray => "GRAYSCALE",
            .gray_a => "GRAYSCALE_ALPHA",
            .rgb => "RGB",
            .rgb_a => "RGB_ALPHA",
        };
    }
};

/// Represents a PAM header.
const Header = struct {
    /// Number of pixels in a row.
    width: usize,
    /// Number of rows.
    height: usize,
    /// Number of components per pixels.
    depth: usize,
    /// Maximum value of a component.
    maxval: u16,
    /// Tuple type of the image.
    tuple_type: TupleType,
    /// Arbitrary text comments. Note that comment position inside the
    /// header is not preserved.
    comments: []const []const u8,

    /// Reads a header from `reader`, using `allocator` to allocate
    /// memory. Returns that header, `error.Unsupported` if the tuple
    /// type is not known to us, `error.OutOfMemory` if allocation
    /// fails, `error.InvalidData` if the header does not conform to
    /// the PAM specification, or another error specific to `reader`
    /// if reading fails.
    fn read(allocator: Allocator, reader: anytype) (error{ InvalidData, Unsupported, OutOfMemory, EndOfStream, StreamTooLong } || @TypeOf(reader).Error)!Header {
        var maybe_width: ?usize = null;
        var maybe_height: ?usize = null;
        var maybe_depth: ?usize = null;
        var maybe_maxval: ?u16 = null;
        var maybe_tuple_type: ?TupleType = null;
        var comments = std.ArrayListUnmanaged([]const u8){};
        defer {
            for (comments.items) |comment| allocator.free(comment);
            comments.deinit(allocator);
        }

        {
            var buf = try std.ArrayList(u8).initCapacity(allocator, 32);
            defer buf.deinit();

            while (true) {
                // we fail on EOS here because a valid pam header must end with ENDHDR
                try reader.readUntilDelimiterArrayList(&buf, '\n', math.maxInt(usize));
                const line = buf.items; // empty lines are meaningless
                if (line.len == 0) continue;
                if (line[0] == '#') { // comment
                    try comments.append(allocator, try allocator.dupe(u8, line[1..]));
                    continue;
                }

                var tok_iter = mem.tokenize(u8, line, &ascii.whitespace);
                const first_token = tok_iter.next() orelse continue; // lines with 0 tokens are meaningless

                if (first_token.len > 8) return error.InvalidData; // the first token must be at most 8 bytes

                if (mem.eql(u8, first_token, "ENDHDR")) break;

                if (mem.eql(u8, first_token, "TUPLTYPE")) {
                    maybe_tuple_type = try TupleType.fromString(tok_iter.rest());
                    continue;
                }

                const second_token = tok_iter.next() orelse return error.InvalidData; // bad token

                if (mem.eql(u8, first_token, "WIDTH")) {
                    maybe_width = fmt.parseUnsigned(usize, second_token, 10) catch return error.InvalidData; // bad width
                } else if (mem.eql(u8, first_token, "HEIGHT")) {
                    maybe_height = fmt.parseUnsigned(usize, second_token, 10) catch return error.InvalidData; // bad height
                } else if (mem.eql(u8, first_token, "DEPTH")) {
                    maybe_depth = fmt.parseUnsigned(usize, second_token, 10) catch return error.InvalidData; // bad depth
                } else if (mem.eql(u8, first_token, "MAXVAL")) {
                    maybe_maxval = fmt.parseUnsigned(u16, second_token, 10) catch return error.InvalidData; // bad maxval
                } else return error.InvalidData; // invalid first token
            }
        }

        if (maybe_height == null or maybe_width == null or maybe_maxval == null or maybe_depth == null) return error.InvalidData; // missing values
        if (maybe_height.? < 1 or maybe_width.? < 1 or maybe_maxval.? < 1) return error.InvalidData; // bad width, height, or maxval
        if (maybe_tuple_type == null) { // guess tuple type
            const depth = maybe_depth.?;
            const maxval = maybe_maxval.?;
            maybe_tuple_type = switch (depth) {
                1 => if (maxval == 1) TupleType.mono else TupleType.gray,
                2 => if (maxval == 1) TupleType.mono_a else TupleType.gray_a,
                3 => TupleType.rgb,
                4 => TupleType.rgb_a,
                else => return error.Unsupported, // can't guess tuple type
            };
        }

        const tuple_type_matches = if (maybe_depth) |depth| if (maybe_maxval) |maxval| switch (maybe_tuple_type.?) {
            .mono => depth == 1 and maxval == 1,
            .mono_a => depth == 2 and maxval == 1,
            .gray => depth == 1,
            .gray_a => depth == 2,
            .rgb => depth == 3,
            .rgb_a => depth == 4,
        } else unreachable else unreachable;

        if (!tuple_type_matches) return error.InvalidData; // tuple type does not match

        return Header{
            .width = maybe_width.?,
            .height = maybe_height.?,
            .maxval = maybe_maxval.?,
            .depth = maybe_depth.?,
            .tuple_type = maybe_tuple_type.?,
            .comments = try comments.toOwnedSlice(allocator),
        };
    }

    /// Writes the PAM representation of `header` to `writer`. If
    /// writing fails, returns an error specific to `writer`.
    fn write(header: Header, writer: anytype) @TypeOf(writer).Error!void {
        try writer.writeAll("P7\n");

        for (header.comments) |comment|
            try writer.print("#{s}\n", .{comment});

        const fmtstr =
            \\WIDTH {d}
            \\HEIGHT {d}
            \\DEPTH {d}
            \\MAXVAL {d}
            \\TUPLTYPE {s}
            \\ENDHDR
            \\
        ;
        try writer.print(fmtstr, .{ header.width, header.height, header.depth, header.maxval, header.tuple_type.toString() });
    }

    /// Invalidates `header` and frees all comments with `allocator`.
    fn deinit(header: *Header, allocator: Allocator) void {
        for (header.comments) |comment| {
            allocator.free(comment);
        }
        allocator.free(header.comments);
        header.* = undefined;
    }

    fn hasTwoBytesPerComponent(header: Header) bool {
        return header.maxval > math.maxInt(u8);
    }

    fn getPixelFormat(header: Header) PixelFormat {
        return switch (header.tuple_type) {
            .mono => .grayscale1,
            // TODO: is this conversion acceptable?
            .mono_a => .grayscale1,
            .gray => if (header.hasTwoBytesPerComponent()) .grayscale16 else .grayscale8,
            .gray_a => if (header.hasTwoBytesPerComponent()) .grayscale16Alpha else .grayscale8Alpha,
            .rgb => if (header.hasTwoBytesPerComponent()) .rgb48 else .rgb24,
            .rgb_a => if (header.hasTwoBytesPerComponent()) .rgba64 else .rgba32,
        };
    }

    /// Initializes an `Image` with the values that `header`
    /// contains. Returns `error.OutOfMemory` if allocation fails.
    fn initImage(header: Header, allocator: Allocator) error{OutOfMemory}!Image {
        var image = Image.init(allocator);
        image.width = header.width;
        image.height = header.height;
        image.pixels = try PixelStorage.init(allocator, header.getPixelFormat(), header.width * header.height);
        return image;
    }

    /// Initializes a `Header` from `image`. Returns
    /// `error.Unsupported` if the pixel format of `image` cannot be
    /// easily represented in PAM.
    fn fromImage(image: Image) error{Unsupported}!Header {
        var header: Header = undefined;
        switch (image.pixelFormat()) {
            .invalid,
            .indexed1,
            .indexed2,
            .indexed4,
            .indexed8,
            .indexed16,
            .float32,
            .rgb565,
            => return error.Unsupported, // unsupported pixel format

            .grayscale1 => {
                header.depth = 1;
                header.maxval = 1;
                header.tuple_type = .mono;
            },
            .grayscale2 => {
                header.depth = 1;
                header.maxval = math.maxInt(u2);
                header.tuple_type = .gray;
            },
            .grayscale4 => {
                header.depth = 1;
                header.maxval = math.maxInt(u4);
                header.tuple_type = .gray;
            },
            .grayscale8 => {
                header.depth = 1;
                header.maxval = math.maxInt(u8);
                header.tuple_type = .gray;
            },
            .grayscale8Alpha => {
                header.depth = 2;
                header.maxval = math.maxInt(u8);
                header.tuple_type = .gray_a;
            },
            .grayscale16 => {
                header.depth = 1;
                header.maxval = math.maxInt(u16);
                header.tuple_type = .gray;
            },
            .grayscale16Alpha => {
                header.depth = 2;
                header.maxval = math.maxInt(u16);
                header.tuple_type = .gray_a;
            },
            .rgb555, .bgr555 => {
                header.depth = 3;
                header.maxval = math.maxInt(u5);
                header.tuple_type = .rgb;
            },
            .rgb24, .bgr24 => {
                header.depth = 3;
                header.maxval = math.maxInt(u8);
                header.tuple_type = .rgb;
            },
            .rgba32, .bgra32 => {
                header.depth = 4;
                header.maxval = math.maxInt(u8);
                header.tuple_type = .rgb_a;
            },
            .rgb48 => {
                header.depth = 3;
                header.maxval = math.maxInt(u16);
                header.tuple_type = .rgb;
            },
            .rgba64 => {
                header.depth = 4;
                header.maxval = math.maxInt(u16);
                header.tuple_type = .rgb_a;
            },
        }
        header.comments = &.{};
        header.width = image.width;
        header.height = image.height;
        return header;
    }
};

pub const PAM = struct {
    //! Portable AnyMap
    //! currently, this only supports a subset of PAMs where:
    //! - the tuple type is official (see `man 5 pam`) or easily inferred (and
    //!   by extension, depth is 4 or less)
    //! - all images in a sequence have the same dimensions and maxval (it is
    //!   technically possible to support animations with different maxvals and
    //!   tuple types as each `AnimationFrame` has its own `PixelStorage`, however,
    //!   this is likely not expected by users of the library.
    //! supported input pixel formats: `grayscale{1, 8, 16}, `grayscale{1, 8, 16}Alpha`, `rgb555`, `{rgb, bgr}{24, 48}`, `{bgr, rgb}a{32, 64}`

    pub const EncoderOptions = struct {
        /// Free-form comments to be added to the header.
        comments: []const []const u8 = &.{},
        /// Whether to add the duration of each `Image.AnimationFrame`
        /// and the `loop_count` of `Image.Animation` to the written file as a comment.
        add_duration_as_comment: bool = false,
    };

    pub fn formatInterface() FormatInterface {
        return FormatInterface{
            .format = format,
            .formatDetect = formatDetect,
            .readImage = readImage,
            .writeImage = writeImage,
        };
    }

    pub fn format() Image.Format {
        return Image.Format.pam;
    }

    /// Returns `true` if the image will be able to be decoded, or a
    /// `stream`-specific error if reading fails.
    pub fn formatDetect(stream: *Image.Stream) ImageReadError!bool {
        const magic = try stream.reader().readBytesNoEof(3);
        return mem.eql(u8, &magic, "P7\n"); // no possibility of misdetecting xv thumbnails (magic "P7 332")
    }

    pub fn readImage(allocator: Allocator, stream: *Image.Stream) ImageReadError!Image {
        var buffered_stream = buffered_stream_source.bufferedStreamSourceReader(stream);
        const reader = buffered_stream.reader();
        var image: Image = try readFrame(allocator, reader) orelse return ImageReadError.InvalidData; // empty stream
        errdefer image.deinit();

        while (try readFrame(allocator, reader)) |frame| {
            if (frame.width != image.width or frame.height != image.height or meta.activeTag(frame.pixels) != meta.activeTag(image.pixels)) {
                return ImageReadError.Unsupported; // no obvious way to have multiple frames with different dimensions
            }
            try image.animation.frames.append(allocator, Image.AnimationFrame{ .pixels = frame.pixels, .duration = 0 });
        }
        return image;
    }

    /// Linearly maps `val` from [0..`src_maxval`] to
    /// [0..`dst_maxval`]. If `val` is greater than `src_maxval`,
    /// `error.OutOfBounds` is returned. If `val == src_maxval`,
    /// `dst_maxval` is returned.
    fn mapValue(comptime T: type, val: T, src_maxval: T, dst_maxval: T) error{InvalidData}!T {
        if (val > src_maxval) return error.InvalidData; // component value exceeded maxval

        if (src_maxval == dst_maxval) return val;

        const W = meta.Int(.unsigned, @bitSizeOf(T) * 2);
        return @intCast(@min(math.maxInt(T), @as(W, dst_maxval) * @as(W, val) / @as(W, src_maxval)));
    }

    fn readFrame(allocator: Allocator, reader: anytype) ImageReadError!?Image {
        // we don't use catch switch here because error.EndOfStream
        // might be the only possible error (and would thus trigger a
        // compile error because of an unreachable else prong)
        const magic = reader.readBytesNoEof(3) catch |e| return if (e == error.EndOfStream) null else e;
        const is_pam = mem.eql(u8, &magic, "P7\n");
        if (!is_pam) return ImageReadError.InvalidData; // invalid magic number or extraneous data at eof

        var header = try Header.read(allocator, reader);
        defer header.deinit(allocator);

        var image: Image = try header.initImage(allocator);
        errdefer image.deinit();

        for (0..image.height) |row| {
            const offset = row * image.width;
            for (0..image.width) |column| {
                switch (image.pixels) {
                    .grayscale1 => |g| g[offset + column].value = @intCast(if (header.tuple_type == .mono) try mapValue(u8, try reader.readByte(), 1, 1) else try mapValue(u8, try reader.readByte(), 1, 1) & try mapValue(u8, try reader.readByte(), 1, 1)),
                    .grayscale8 => |g| g[offset + column].value = try mapValue(u8, try reader.readByte(), @as(u8, @intCast(header.maxval)), math.maxInt(u8)),
                    .grayscale8Alpha => |g| g[offset + column] = .{
                        .value = try mapValue(u8, try reader.readByte(), @as(u8, @intCast(header.maxval)), math.maxInt(u8)),
                        .alpha = try mapValue(u8, try reader.readByte(), @as(u8, @intCast(header.maxval)), math.maxInt(u8)),
                    },
                    .grayscale16 => |g| g[offset + column].value = try mapValue(u16, try reader.readInt(u16, .little), header.maxval, math.maxInt(u16)),
                    .grayscale16Alpha => |g| g[offset + column] = .{
                        .value = try mapValue(u16, try reader.readInt(u16, .little), header.maxval, math.maxInt(u16)),
                        .alpha = try mapValue(u16, try reader.readInt(u16, .little), header.maxval, math.maxInt(u16)),
                    },
                    .rgb24 => |x| x[offset + column] = .{
                        .r = try mapValue(u8, try reader.readByte(), @as(u8, @intCast(header.maxval)), math.maxInt(u8)),
                        .g = try mapValue(u8, try reader.readByte(), @as(u8, @intCast(header.maxval)), math.maxInt(u8)),
                        .b = try mapValue(u8, try reader.readByte(), @as(u8, @intCast(header.maxval)), math.maxInt(u8)),
                    },
                    .rgba32 => |x| x[offset + column] = .{
                        .r = try mapValue(u8, try reader.readByte(), @as(u8, @intCast(header.maxval)), math.maxInt(u8)),
                        .g = try mapValue(u8, try reader.readByte(), @as(u8, @intCast(header.maxval)), math.maxInt(u8)),
                        .b = try mapValue(u8, try reader.readByte(), @as(u8, @intCast(header.maxval)), math.maxInt(u8)),
                        .a = try mapValue(u8, try reader.readByte(), @as(u8, @intCast(header.maxval)), math.maxInt(u8)),
                    },
                    .rgb48 => |x| x[offset + column] = .{
                        .r = try mapValue(u16, try reader.readInt(u16, .little), header.maxval, math.maxInt(u16)),
                        .g = try mapValue(u16, try reader.readInt(u16, .little), header.maxval, math.maxInt(u16)),
                        .b = try mapValue(u16, try reader.readInt(u16, .little), header.maxval, math.maxInt(u16)),
                    },
                    .rgba64 => |x| x[offset + column] = .{
                        .r = try mapValue(u16, try reader.readInt(u16, .little), header.maxval, math.maxInt(u16)),
                        .g = try mapValue(u16, try reader.readInt(u16, .little), header.maxval, math.maxInt(u16)),
                        .b = try mapValue(u16, try reader.readInt(u16, .little), header.maxval, math.maxInt(u16)),
                        .a = try mapValue(u16, try reader.readInt(u16, .little), header.maxval, math.maxInt(u16)),
                    },
                    else => unreachable,
                }
            }
        }
        return image;
    }

    pub fn writeImage(allocator: Allocator, stream: *Image.Stream, image: Image, encoder_options: Image.EncoderOptions) ImageWriteError!void {
        var buffered_stream = buffered_stream_source.bufferedStreamSourceWriter(stream);
        const writer = buffered_stream.writer();

        var comments = std.ArrayList([]const u8).init(allocator);
        defer comments.deinit();
        try comments.appendSlice(switch (encoder_options) {
            .pam => |p| p.comments,
            else => &.{},
        });

        var duration_buffer: [128]u8 = undefined;
        const add_duration_as_comment = switch (encoder_options) {
            .pam => |p| p.add_duration_as_comment,
            else => false,
        };

        {
            if (add_duration_as_comment and image.isAnimation()) {
                try comments.append(try fmt.bufPrint(&duration_buffer, "loop count: {d}", .{image.animation.loop_count}));
            }
            defer {
                if (add_duration_as_comment and image.isAnimation()) _ = comments.pop();
            }

            try writeFrame(writer, image, .{ .pam = .{ .comments = comments.items } });
        }

        for (image.animation.frames.items) |frame| {
            if (add_duration_as_comment)
                try comments.append(try fmt.bufPrint(&duration_buffer, "duration: {d}", .{frame.duration}));
            defer {
                if (add_duration_as_comment) _ = comments.pop();
            }

            const frame_img = Image{ .pixels = frame.pixels, .width = image.width, .height = image.height, .allocator = image.allocator };

            try writeFrame(writer, frame_img, .{ .pam = .{ .comments = comments.items } });
        }

        try buffered_stream.flush();
    }

    pub fn writeFrame(writer: anytype, frame: Image, encoder_options: Image.EncoderOptions) ImageWriteError!void {
        var header = try Header.fromImage(frame);
        header.comments = encoder_options.pam.comments;
        try header.write(writer);
        for (0..frame.height) |row| {
            const offset = row * frame.width;
            for (0..frame.width) |column| {
                switch (frame.pixels) {
                    .grayscale1 => |x| try writer.writeByte(x[offset + column].value),
                    .grayscale4 => |x| try writer.writeByte(x[offset + column].value),
                    .grayscale8 => |x| try writer.writeByte(x[offset + column].value),
                    .grayscale16 => |x| try writer.writeInt(u16, x[offset + column].value, .little),
                    .grayscale8Alpha => |x| {
                        try writer.writeByte(x[offset + column].value);
                        try writer.writeByte(x[offset + column].alpha);
                    },
                    .grayscale16Alpha => |x| {
                        try writer.writeInt(u16, x[offset + column].value, .little);
                        try writer.writeInt(u16, x[offset + column].alpha, .little);
                    },
                    .bgr555 => |x| {
                        try writer.writeByte(x[offset + column].r);
                        try writer.writeByte(x[offset + column].g);
                        try writer.writeByte(x[offset + column].b);
                    },
                    .rgb555 => |x| {
                        try writer.writeByte(x[offset + column].r);
                        try writer.writeByte(x[offset + column].g);
                        try writer.writeByte(x[offset + column].b);
                    },
                    .rgb24 => |x| {
                        try writer.writeByte(x[offset + column].r);
                        try writer.writeByte(x[offset + column].g);
                        try writer.writeByte(x[offset + column].b);
                    },
                    .rgba32 => |x| {
                        try writer.writeByte(x[offset + column].r);
                        try writer.writeByte(x[offset + column].g);
                        try writer.writeByte(x[offset + column].b);
                        try writer.writeByte(x[offset + column].a);
                    },
                    .bgr24 => |x| {
                        try writer.writeByte(x[offset + column].r);
                        try writer.writeByte(x[offset + column].g);
                        try writer.writeByte(x[offset + column].b);
                    },
                    .bgra32 => |x| {
                        try writer.writeByte(x[offset + column].r);
                        try writer.writeByte(x[offset + column].g);
                        try writer.writeByte(x[offset + column].b);
                        try writer.writeByte(x[offset + column].a);
                    },
                    .rgb48 => |x| {
                        try writer.writeInt(u16, x[offset + column].r, .little);
                        try writer.writeInt(u16, x[offset + column].g, .little);
                        try writer.writeInt(u16, x[offset + column].b, .little);
                    },
                    .rgba64 => |x| {
                        try writer.writeInt(u16, x[offset + column].r, .little);
                        try writer.writeInt(u16, x[offset + column].g, .little);
                        try writer.writeInt(u16, x[offset + column].b, .little);
                        try writer.writeInt(u16, x[offset + column].a, .little);
                    },
                    else => unreachable, // can't happen, already handled in fromImage
                }
            }
        }
    }
};
