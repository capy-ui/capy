pub const AllFormats = @import("src/formats/all.zig");
pub const bmp = @import("src/formats/bmp.zig");
pub const color = @import("src/color.zig");
pub const FormatInterface = @import("src/format_interface.zig").FormatInterface;
pub const Image = @import("src/Image.zig");
pub const netpbm = @import("src/formats/netpbm.zig");
pub const OctTreeQuantizer = @import("src/octree_quantizer.zig").OctTreeQuantizer;
pub const pcx = @import("src/formats/pcx.zig");
pub const PixelFormat = @import("src/pixel_format.zig").PixelFormat;
pub const jpeg = @import("src/formats/jpeg.zig");
pub const png = @import("src/formats/png.zig");
pub const qoi = @import("src/formats/qoi.zig");
pub const tga = @import("src/formats/tga.zig");

test {
    @import("std").testing.refAllDecls(@This());
    _ = @import("src/formats/png/reader.zig");
    _ = @import("tests/color_test.zig");
    _ = @import("tests/formats/bmp_test.zig");
    _ = @import("tests/formats/jpeg_test.zig");
    _ = @import("tests/formats/netpbm_test.zig");
    _ = @import("tests/formats/pcx_test.zig");
    _ = @import("tests/formats/png_test.zig");
    _ = @import("tests/formats/qoi_test.zig");
    _ = @import("tests/formats/tga_test.zig");
    _ = @import("tests/image_test.zig");
    _ = @import("tests/octree_quantizer_test.zig");
}
