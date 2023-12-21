const std = @import("std");
const Image = @import("Image.zig");
const color = @import("color.zig");

// mlarouche: Because this is a interface, I use Zig function naming convention instead of the variable naming convention
format: *const FormatFn,
formatDetect: *const FormatDetectFn,
readImage: *const ReadImageFn,
writeImage: *const WriteImageFn,

pub const FormatFn = fn () Image.Format;
pub const FormatDetectFn = fn (stream: *Image.Stream) Image.ReadError!bool;
pub const ReadImageFn = fn (allocator: std.mem.Allocator, stream: *Image.Stream) Image.ReadError!Image;
pub const WriteImageFn = fn (allocator: std.mem.Allocator, write_stream: *Image.Stream, image: Image, encoder_options: Image.EncoderOptions) Image.WriteError!void;
