//! this module implements the JFIF header
//! specified in https://www.w3.org/Graphics/JPEG/itu-t81.pdf
//! section B.2.1 and assumes that there will be an application0 segment.

const std = @import("std");

const buffered_stream_source = @import("../../buffered_stream_source.zig");
const Image = @import("../../Image.zig");
const Markers = @import("./utils.zig").Markers;

const Self = @This();

/// see https://www.ecma-international.org/wp-content/uploads/ECMA_TR-98_1st_edition_june_2009.pdf
/// chapt 10.
pub const DensityUnit = enum(u8) {
    pixels = 0,
    dots_per_inch = 1,
    dots_per_cm = 2,
};

jfif_revision: u16,
density_unit: DensityUnit,
x_density: u16,
y_density: u16,

pub fn read(buffered_stream: *buffered_stream_source.DefaultBufferedStreamSourceReader) !Self {
    // Read the first APP0 header.
    const reader = buffered_stream.reader();
    try buffered_stream.seekTo(2);
    const maybe_app0_marker = try reader.readInt(u16, .big);
    if (maybe_app0_marker != @intFromEnum(Markers.application0)) {
        return error.App0MarkerDoesNotExist;
    }

    // Header length
    _ = try reader.readInt(u16, .big);

    var identifier_buffer: [4]u8 = undefined;
    _ = try reader.read(identifier_buffer[0..]);

    if (!std.mem.eql(u8, identifier_buffer[0..], "JFIF")) {
        return error.JfifIdentifierNotSet;
    }

    // NUL byte after JFIF
    _ = try reader.readByte();

    const jfif_revision = try reader.readInt(u16, .big);
    const density_unit: DensityUnit = @enumFromInt(try reader.readByte());
    const x_density = try reader.readInt(u16, .big);
    const y_density = try reader.readInt(u16, .big);

    const thumbnailWidth = try reader.readByte();
    const thumbnailHeight = try reader.readByte();

    if (thumbnailWidth != 0 or thumbnailHeight != 0) {
        // TODO: Support thumbnails (not important)
        return error.ThumbnailImagesUnsupported;
    }

    // Make sure there are no application markers after us.
    // TODO: Support application markers, present in versions 1.02 and above.
    // see https://www.ecma-international.org/wp-content/uploads/ECMA_TR-98_1st_edition_june_2009.pdf
    // chapt 10.1
    if (((try reader.readInt(u16, .big)) & 0xFFF0) == @intFromEnum(Markers.application0)) {
        return error.ExtraneousApplicationMarker;
    }

    try buffered_stream.seekBy(-2);

    return Self{
        .jfif_revision = jfif_revision,
        .density_unit = density_unit,
        .x_density = x_density,
        .y_density = y_density,
    };
}
