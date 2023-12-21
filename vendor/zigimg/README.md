# Zig Image library

This is a work in progress library to create, process, read and write different image formats with [Zig](https://ziglang.org/) programming language.

![License](https://img.shields.io/github/license/zigimg/zigimg) ![Issue](https://img.shields.io/github/issues-raw/zigimg/zigimg?style=flat) ![Commit](https://img.shields.io/github/last-commit/zigimg/zigimg) ![CI](https://github.com/zigimg/zigimg/workflows/CI/badge.svg)

[![Join our Discord!](https://discordapp.com/api/guilds/1161009516771549374/widget.png?style=banner2)](https://discord.gg/TYgEEuEGnK)

## Install & Build

This project assume current Zig master (0.12.0-dev.799+d68f39b54 or higher) with stage2 self-hosted compiler.

### Use zigimg in your project

How to add to your project:

#### As a submodule

1. Clone this repository or add as a submodule
1. Add to your `build.zig`
```
exe.addAnonymousModule("zigimg", .{.source_file = .{ .path = "zigimg.zig" }});
```

#### Through the package manager

1. Example build.zig.zon file

```
.{
    .name = "app",
    .version = "0.0.0",
    .dependencies = .{
        .zigimg = .{
            .url = "https://github.com/zigimg/zigimg/archive/$REPLACE_WITH_WANTED_COMMIT$.tar.gz",
        },
    },
}
```

2. When it fails to build due to a mismatched hash, add the `hash` line to the dependency

```
.zigimg = .{
    .url = "https://github.com/zigimg/zigimg/archive/$REPLACE_WITH_WANTED_COMMIT$.tar.gz",
    .hash = "$REPLACE_WITH_HASH_FROM_BUILD_ERROR$",
},
```


## Test suite

To run the test suite, checkout the [test suite](https://github.com/zigimg/test-suite) and run

1. Checkout zigimg
1. Go back one folder and checkout the [test suite](https://github.com/zigimg/test-suite) 
1. Run the tests with `zig build`
```
zig build test
```

## Supported image formats

| Image Format  | Read          | Write          |
| ------------- |:-------------:|:--------------:|
| ANIM          | ❌            | ❌            |
| BMP           | ✔️ (Partial)  | ✔️ (Partial)  |
| GIF           | ✔️            | ❌            |
| ICO           | ❌            | ❌            |
| IILBM         | ❌            | ❌            |
| JPEG          | ❌            | ❌            |
| PAM           | ✔️            | ✔️            |
| PBM           | ✔️            | ✔️            |
| PCX           | ✔️            | ✔️            |
| PGM           | ✔️ (Partial)  | ✔️ (Partial)  |
| PNG           | ✔️            | ✔️ (Partial)  |
| PPM           | ✔️ (Partial)  | ✔️ (Partial)  |
| QOI           | ✔️            | ✔️            |
| TGA           | ✔️            | ✔️            |
| TIFF          | ❌            | ❌            |
| XBM           | ❌            | ❌            |
| XPM           | ❌            | ❌            |

### BMP - Bitmap

* version 4 BMP
* version 5 BMP
* 24-bit RGB read & write
* 32-bit RGBA read & write
* Doesn't support any compression

### GIF - Graphics Interchange Format

* Support GIF87a and GIF89a
* Support animated GIF with Netscape application extension for looping information
* Supported interlaced
* Supports tiled and layered images used to achieve pseudo true color and more.
* The plain text extension is not supported

### PAM - Portable Arbitrary Map

Currently, this only supports a subset of PAMs where:
* The tuple type is official (see `man 5 pam`) or easily inferred (and by extension, depth is 4 or less)
* All the images in a sequence have the same dimensions and maxval (it is technically possible to support animations with different maxvals and tuple types as each `AnimationFrame` has its own `PixelStorage`, however, this is likely not expected by users of the library)
* Grayscale,
* Grayscale with alpha
* Rgb555
* Rgb24 and Rgba32
* Bgr24 and Bgra32
* Rgb48 and Rgba64

### PBM - Portable Bitmap format

* Everything is supported

### PCX - ZSoft Picture Exchange format

* Support monochrome, 4 color, 16 color and 256 color indexed images
* Support 24-bit RGB images

### PGM - Portable Graymap format

* Support 8-bit and 16-bit grayscale images
* 16-bit ascii grayscale loading not tested

### PNG - Portable Network Graphics

* Support all pixel formats supported by PNG (grayscale, grayscale+alpha, indexed, truecolor, truecolor with alpha) in 8-bit or 16-bit.
* Support the mininal chunks in order to decode the image.
* Not all images in Png Test Suite is covered but should be good enough for now.

### PPM - Portable Pixmap format

* Support 24-bit RGB (8-bit per channel)
* Missing 48-bit RGB (16-bit per channel)

### QOI - Quite OK Image Format

* Imported from https://github.com/MasterQ32/zig-qoi with blessing of the author

### TGA - Truevision TGA format

* Supports uncompressed and compressed 8-bit grayscale, indexed with 16-bit and 24-bit colormap, truecolor with 16-bit(RGB555), 24-bit or 32-bit bit depth.
* Supports reading version 1 and version 2
* Supports writing version 2