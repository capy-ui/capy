pub const BMP = @import("bmp.zig").Bitmap;
pub const JPEG = @import("jpeg.zig").JPEG;
pub const PBM = @import("netpbm.zig").PBM;
pub const PCX = @import("pcx.zig").PCX;
pub const PGM = @import("netpbm.zig").PGM;
pub const PNG = @import("png.zig").PNG;
pub const PPM = @import("netpbm.zig").PPM;
pub const QOI = @import("qoi.zig").QOI;
pub const TGA = @import("tga.zig").TGA;

pub const ImageEncoderOptions = union(@import("../Image.zig").Format) {
    bmp: void,
    jpg: void,
    pbm: PBM.EncoderOptions,
    pcx: void,
    pgm: PGM.EncoderOptions,
    png: PNG.EncoderOptions,
    ppm: PPM.EncoderOptions,
    qoi: QOI.EncoderOptions,
    tga: void,
};
