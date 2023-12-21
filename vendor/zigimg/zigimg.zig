pub const AllFormats = @import("src/formats/all.zig");
pub const bmp = @import("src/formats/bmp.zig");
pub const color = @import("src/color.zig");
pub const FormatInterface = @import("src/FormatInterface.zig");
pub const Image = @import("src/Image.zig");
pub const gif = @import("src/formats/gif.zig");
pub const netpbm = @import("src/formats/netpbm.zig");
pub const OctTreeQuantizer = @import("src/octree_quantizer.zig").OctTreeQuantizer;
pub const pcx = @import("src/formats/pcx.zig");
pub const PixelFormat = @import("src/pixel_format.zig").PixelFormat;
pub const jpeg = @import("src/formats/jpeg.zig");
pub const png = @import("src/formats/png.zig");
pub const qoi = @import("src/formats/qoi.zig");
pub const tga = @import("src/formats/tga.zig");
pub const pam = @import("src/formats/pam.zig");

test {
    const std = @import("std");
    std.testing.refAllDecls(@This());

    inline for (.{
        @import("src/compressions/lzw.zig"),
        @import("src/formats/png/reader.zig"),
        @import("tests/buffered_stream_source_test.zig"),
        @import("tests/color_test.zig"),
        @import("tests/formats/bmp_test.zig"),
        @import("tests/formats/gif_test.zig"),
        @import("tests/formats/jpeg_test.zig"),
        @import("tests/formats/netpbm_test.zig"),
        @import("tests/formats/pam_test.zig"),
        @import("tests/formats/pcx_test.zig"),
        @import("tests/formats/png_test.zig"),
        @import("tests/formats/qoi_test.zig"),
        @import("tests/formats/tga_test.zig"),
        @import("tests/image_test.zig"),
        @import("tests/octree_quantizer_test.zig"),
        @import("tests/pixel_format_test.zig"),
    }) |source_file| std.testing.refAllDeclsRecursive(source_file);
}
