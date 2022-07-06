const std = @import("std");
const internal = @import("internal.zig");
const backend = @import("backend.zig");
const Size = @import("data.zig").Size;
const DataWrapper = @import("data.zig").DataWrapper;
const Widget = @import("widget.zig").Widget;

pub const MenuItem_Impl = struct {
    config: Config,
    /// If there are no items, this is a menu item
    /// Otherwise, this is a menu
    items: []const MenuItem_Impl = &.{},
};

pub const MenuBar_Impl = struct { menus: []const MenuItem_Impl };

const Config = struct {
    pub const Callback = fn () void;

    label: [:0]const u8,
    onClick: ?Callback = null,
};

pub fn MenuItem(config: Config) MenuItem_Impl {
    return MenuItem_Impl{ .config = config };
}

/// 'items' is a tuple
pub fn Menu(config: Config, items: anytype) MenuItem_Impl {
    return MenuItem_Impl{ .config = config, .items = internal.lasting_allocator.dupe(MenuItem_Impl, &items) catch unreachable };
}

/// 'menus' is a tuple
pub fn MenuBar(menus: anytype) MenuBar_Impl {
    return MenuBar_Impl{ .menus = internal.lasting_allocator.dupe(MenuItem_Impl, &menus) catch unreachable };
}
