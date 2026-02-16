const std = @import("std");
const icon_data_module = @import("capy_icon_data");

/// Raw PNG bytes embedded at compile time from the -Dicon build option.
pub const embedded_icon_png: ?[]const u8 = icon_data_module.data;

/// Decode the embedded icon PNG into an ImageData, cached after first call.
/// Returns null if no icon was embedded at build time.
pub fn getEmbeddedIcon() ?@import("image.zig").ImageData {
    const S = struct {
        var cached: ?@import("image.zig").ImageData = null;
        var initialized: bool = false;
    };
    if (S.initialized) return S.cached;
    S.initialized = true;

    const png_data = embedded_icon_png orelse return null;
    S.cached = @import("image.zig").ImageData.fromBuffer(
        @import("internal.zig").allocator,
        png_data,
    ) catch null;
    return S.cached;
}
