//! general utilizies and constants
const std = @import("std");

// See figure A.6 in T.81.
pub const ZigzagOffsets = blk: {
    var offsets: [64]usize = undefined;
    offsets[0] = 0;

    var current_offset: usize = 0;
    var direction: enum { north_east, south_west } = .north_east;
    var i: usize = 1;
    while (i < 64) : (i += 1) {
        switch (direction) {
            .north_east => {
                if (current_offset < 8) {
                    // Hit top edge
                    current_offset += 1;
                    direction = .south_west;
                } else if (current_offset % 8 == 7) {
                    // Hit right edge
                    current_offset += 8;
                    direction = .south_west;
                } else {
                    current_offset -= 7;
                }
            },
            .south_west => {
                if (current_offset >= 56) {
                    // Hit bottom edge
                    current_offset += 1;
                    direction = .north_east;
                } else if (current_offset % 8 == 0) {
                    // Hit left edge
                    current_offset += 8;
                    direction = .north_east;
                } else {
                    current_offset += 7;
                }
            },
        }

        if (current_offset >= 64) {
            @compileError(std.fmt.comptimePrint("ZigzagOffsets: Hit offset {} (>= 64) at index {}!\n", .{ current_offset, i }));
        }

        offsets[i] = current_offset;
    }

    break :blk offsets;
};

/// The precalculated IDCT multipliers. This is possible because the only part of
/// the IDCT calculation that changes between runs is the coefficients.
/// see A.3.3 of t.81 1992
pub const IDCTMultipliers = blk: {
    var multipliers: [8][8][8][8]f32 = undefined;
    @setEvalBranchQuota(4700);

    var y: usize = 0;
    while (y < 8) : (y += 1) {
        var x: usize = 0;
        while (x < 8) : (x += 1) {
            var u: usize = 0;
            while (u < 8) : (u += 1) {
                var v: usize = 0;
                while (v < 8) : (v += 1) {
                    const C_u: f32 = if (u == 0) 1.0 / @sqrt(2.0) else 1.0;
                    const C_v: f32 = if (v == 0) 1.0 / @sqrt(2.0) else 1.0;

                    const x_cosine = @cos(((2 * @as(f32, @floatFromInt(x)) + 1) * @as(f32, @floatFromInt(u)) * std.math.pi) / 16.0);
                    const y_cosine = @cos(((2 * @as(f32, @floatFromInt(y)) + 1) * @as(f32, @floatFromInt(v)) * std.math.pi) / 16.0);
                    const uv_value = C_u * C_v * x_cosine * y_cosine;
                    multipliers[y][x][u][v] = uv_value;
                }
            }
        }
    }

    break :blk multipliers;
};

/// Marker codes, see t-81 section B.1.1.3
pub const Markers = enum(u16) {
    // Start of Frame markers, non-differential, Huffman coding
    sof0 = 0xFFC0, // Baseline DCT
    sof1 = 0xFFC1, // Extended sequential DCT
    sof2 = 0xFFC2, // Progressive DCT
    sof3 = 0xFFC3, // Lossless sequential

    // Start of Frame markers, differential, Huffman coding
    sof5 = 0xFFC5, // Differential sequential DCT
    sof6 = 0xFFC6, // Differential progressive DCT
    sof7 = 0xFFC7, // Differential lossless sequential

    // Start of Frame markers, non-differential, arithmetic coding
    sof9 = 0xFFC9, // Extended sequential DCT
    sof10 = 0xFFCA, // Progressive DCT
    sof11 = 0xFFCB, // Lossless sequential

    // Start of Frame markers, differential, arithmetic coding
    sof13 = 0xFFCD, // Differential sequential DCT
    sof14 = 0xFFCE, // Differential progressive DCT
    sof15 = 0xFFCF, // Differential lossless sequential

    define_huffman_tables = 0xFFC4,
    define_arithmetic_coding = 0xFFCC,

    // 0xFFD0-0xFFD7: Restart markers
    restart0 = 0xFFD0,
    restart1 = 0xFFD1,
    restart2 = 0xFFD2,
    restart3 = 0xFFD3,
    restart4 = 0xFFD4,
    restart5 = 0xFFD5,
    restart6 = 0xFFD6,
    restart7 = 0xFFD7,

    start_of_image = 0xFFD8,
    end_of_image = 0xFFD9,
    start_of_scan = 0xFFDA,
    define_quantization_tables = 0xFFDB,
    define_number_of_lines = 0xFFDC,
    define_restart_interval = 0xFFDD,
    define_hierarchical_progression = 0xFFDE,
    expand_reference_components = 0xFFDF,

    // 0xFFE0-0xFFEF application segments markers add 0-15 as needed.
    application0 = 0xFFE0,

    // 0xFFF0-0xFFFD jpeg extension markers add 0-13 as needed.
    jpeg_extension0 = 0xFFF0,
    comment = 0xFFFE,

    // reserved markers from 0xFF01-0xFFBF, add as needed
};

pub const MAX_COMPONENTS = 3;
pub const MAX_BLOCKS = 8;
pub const MCU = [64]i32;
