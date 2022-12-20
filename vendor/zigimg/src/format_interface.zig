const std = @import("std");
const Image = @import("Image.zig");
const color = @import("color.zig");
const Allocator = std.mem.Allocator;
const ImageReadError = Image.ReadError;
const ImageWriteError = Image.WriteError;

// mlarouche: Because this is a interface, I use Zig function naming convention instead of the variable naming convention
pub const FormatInterface = struct {
    format: *const FormatFn,
    formatDetect: *const FormatDetectFn,
    readImage: *const ReadImageFn,
    writeImage: *const WriteImageFn,

    pub const FormatFn = fn () Image.Format;
    pub const FormatDetectFn = fn (stream: *Image.Stream) ImageReadError!bool;
    pub const ReadImageFn = fn (allocator: Allocator, stream: *Image.Stream) ImageReadError!Image;
    pub const WriteImageFn = fn (allocator: Allocator, write_stream: *Image.Stream, image: Image, encoder_options: Image.EncoderOptions) ImageWriteError!void;
};
