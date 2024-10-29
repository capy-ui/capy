const Atom = @import("data.zig").Atom;

pub const Font = struct {
    /// The font family
    family: ?[]const u8 = null,
    /// The font size, in points.
    size: ?f64 = null,
};

pub const TextAlignment = enum {
    Left,
    Center,
    Right,
};

pub const TextLayout = struct {
    font: Font = .{},
    alignment: TextAlignment = .Left,
};
