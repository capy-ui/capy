pub const BMP = @import("bmp.zig").BMP;
pub const GIF = @import("gif.zig").GIF;
pub const JPEG = @import("jpeg.zig").JPEG;
pub const PBM = @import("netpbm.zig").PBM;
pub const PCX = @import("pcx.zig").PCX;
pub const PGM = @import("netpbm.zig").PGM;
pub const PNG = @import("png.zig").PNG;
pub const PPM = @import("netpbm.zig").PPM;
pub const QOI = @import("qoi.zig").QOI;
pub const TGA = @import("tga.zig").TGA;
pub const PAM = @import("pam.zig").PAM;

pub const ImageEncoderOptions = union(@import("../Image.zig").Format) {
    bmp: BMP.EncoderOptions,
    gif: void,
    jpg: void,
    pbm: PBM.EncoderOptions,
    pcx: PCX.EncoderOptions,
    pgm: PGM.EncoderOptions,
    png: PNG.EncoderOptions,
    ppm: PPM.EncoderOptions,
    qoi: QOI.EncoderOptions,
    tga: TGA.EncoderOptions,
    pam: PAM.EncoderOptions,
};
