const AllImageFormats = @import("formats/all.zig");
const FormatInterface = @import("FormatInterface.zig");
const PixelFormat = @import("pixel_format.zig").PixelFormat;
const color = @import("color.zig");
const std = @import("std");
const utils = @import("utils.zig");

pub const Error = error{
    Unsupported,
};

pub const ReadError = Error ||
    std.mem.Allocator.Error ||
    utils.StructReadError ||
    std.io.StreamSource.SeekError ||
    std.io.StreamSource.GetSeekPosError ||
    error{ EndOfStream, StreamTooLong, InvalidData };

pub const WriteError = Error ||
    std.mem.Allocator.Error ||
    std.io.StreamSource.WriteError ||
    std.io.StreamSource.SeekError ||
    std.io.StreamSource.GetSeekPosError ||
    std.fs.File.OpenError ||
    error{ EndOfStream, InvalidData };

pub const Format = enum {
    bmp,
    gif,
    jpg,
    pbm,
    pcx,
    pgm,
    png,
    ppm,
    qoi,
    tga,
    pam,
};

pub const Stream = std.io.StreamSource;

pub const EncoderOptions = AllImageFormats.ImageEncoderOptions;

pub const AnimationLoopInfinite = -1;

pub const AnimationFrame = struct {
    pixels: color.PixelStorage,
    duration: f32,

    pub fn deinit(self: AnimationFrame, allocator: std.mem.Allocator) void {
        self.pixels.deinit(allocator);
    }
};

pub const Animation = struct {
    frames: FrameList = .{},
    loop_count: i32 = AnimationLoopInfinite,

    pub const FrameList = std.ArrayListUnmanaged(AnimationFrame);

    pub fn deinit(self: *Animation, allocator: std.mem.Allocator) void {
        // Animation share its first frame with the pixels in Image, we don't want to free it twice
        if (self.frames.items.len >= 2) {
            for (self.frames.items[1..]) |frame| {
                frame.pixels.deinit(allocator);
            }
        }

        self.frames.deinit(allocator);
    }
};

/// Format-independant image
allocator: std.mem.Allocator = undefined,
width: usize = 0,
height: usize = 0,
pixels: color.PixelStorage = .{ .invalid = void{} },
animation: Animation = .{},

const Image = @This();

const FormatInteraceFnType = *const fn () FormatInterface;
const all_interface_funcs = blk: {
    const allFormatDecls = std.meta.declarations(AllImageFormats);
    var result: [allFormatDecls.len]FormatInteraceFnType = undefined;
    var index: usize = 0;
    for (allFormatDecls) |decl| {
        const decl_value = @field(AllImageFormats, decl.name);
        const entry_type = @TypeOf(decl_value);
        if (entry_type == type) {
            const entryTypeInfo = @typeInfo(decl_value);
            if (entryTypeInfo == .Struct) {
                for (entryTypeInfo.Struct.decls) |structEntry| {
                    if (std.mem.eql(u8, structEntry.name, "formatInterface")) {
                        result[index] = @field(decl_value, structEntry.name);
                        index += 1;
                        break;
                    }
                }
            }
        }
    }

    break :blk result[0..index];
};

/// Init an empty image with no pixel data
pub fn init(allocator: std.mem.Allocator) Image {
    return Image{
        .allocator = allocator,
    };
}

/// Deinit the image
pub fn deinit(self: *Image) void {
    self.pixels.deinit(self.allocator);
    self.animation.deinit(self.allocator);
}

/// Load an image from a file path
pub fn fromFilePath(allocator: std.mem.Allocator, file_path: []const u8) !Image {
    var file = try std.fs.cwd().openFile(file_path, .{});
    defer file.close();

    return fromFile(allocator, &file);
}

/// Load an image from a standard library std.fs.File
pub fn fromFile(allocator: std.mem.Allocator, file: *std.fs.File) !Image {
    var stream_source = std.io.StreamSource{ .file = file.* };
    return internalRead(allocator, &stream_source);
}

/// Load an image from a memory buffer
pub fn fromMemory(allocator: std.mem.Allocator, buffer: []const u8) !Image {
    var stream_source = std.io.StreamSource{ .const_buffer = std.io.fixedBufferStream(buffer) };
    return internalRead(allocator, &stream_source);
}

/// Create a pixel surface from scratch
pub fn create(allocator: std.mem.Allocator, width: usize, height: usize, pixel_format: PixelFormat) !Image {
    const result = Image{
        .allocator = allocator,
        .width = width,
        .height = height,
        .pixels = try color.PixelStorage.init(allocator, pixel_format, width * height),
    };

    return result;
}

/// Return the pixel format of the image
pub fn pixelFormat(self: Image) PixelFormat {
    return std.meta.activeTag(self.pixels);
}

/// Return the pixel data as a const byte slice. In case of an animation, it return the pixel data of the first frame.
pub fn rawBytes(self: Image) []const u8 {
    return self.pixels.asBytes();
}

/// Return the byte size of a row in the image
pub fn rowByteSize(self: Image) usize {
    return self.imageByteSize() / self.height;
}

/// Return the byte size of the whole image
pub fn imageByteSize(self: Image) usize {
    return self.rawBytes().len;
}

/// Is this image is an animation?
pub fn isAnimation(self: Image) bool {
    return self.animation.frames.items.len > 0;
}

/// Write the image to an image format to the specified path
pub fn writeToFilePath(self: Image, file_path: []const u8, encoder_options: EncoderOptions) WriteError!void {
    var file = try std.fs.cwd().createFile(file_path, .{});
    defer file.close();

    try self.writeToFile(file, encoder_options);
}

/// Write the image to an image format to the specified std.fs.File
pub fn writeToFile(self: Image, file: std.fs.File, encoder_options: EncoderOptions) WriteError!void {
    var stream_source = std.io.StreamSource{ .file = file };

    try self.internalWrite(&stream_source, encoder_options);
}

/// Write the image to an image format in a memory buffer. The memory buffer is not grown
/// for you so make sure you pass a large enough buffer.
pub fn writeToMemory(self: Image, write_buffer: []u8, encoder_options: EncoderOptions) WriteError![]u8 {
    var stream_source = std.io.StreamSource{ .buffer = std.io.fixedBufferStream(write_buffer) };

    try self.internalWrite(&stream_source, encoder_options);

    return stream_source.buffer.getWritten();
}

/// Iterate the pixel in pixel-format agnostic way. In the case of an animation, it returns an iterator for the first frame. The iterator is read-only.
// FIXME: *const Image is a workaround for a stage2 bug because determining the pass a parameter by value or pointer depending of the size is not mature yet
// and fails. For now we are explictly requesting to access only a const pointer.
pub fn iterator(self: *const Image) color.PixelStorageIterator {
    return color.PixelStorageIterator.init(&self.pixels);
}

fn internalRead(allocator: std.mem.Allocator, stream: *Stream) !Image {
    const format_interface = try findImageInterfaceFromStream(stream);

    try stream.seekTo(0);

    return try format_interface.readImage(allocator, stream);
}

fn internalWrite(self: Image, stream: *Stream, encoder_options: EncoderOptions) WriteError!void {
    const image_format = std.meta.activeTag(encoder_options);

    var format_interface = try findImageInterfaceFromImageFormat(image_format);

    try format_interface.writeImage(self.allocator, stream, self, encoder_options);
}

fn findImageInterfaceFromStream(stream: *Stream) !FormatInterface {
    for (all_interface_funcs) |intefaceFn| {
        const formatInterface = intefaceFn();

        try stream.seekTo(0);
        const found = try formatInterface.formatDetect(stream);
        if (found) {
            return formatInterface;
        }
    }

    return Error.Unsupported;
}

fn findImageInterfaceFromImageFormat(image_format: Format) !FormatInterface {
    for (all_interface_funcs) |interface_fn| {
        const format_interface = interface_fn();

        if (format_interface.format() == image_format) {
            return format_interface;
        }
    }

    return Error.Unsupported;
}
