const std = @import("std");
const internal = @import("../internal.zig");
const backend = @import("../backend.zig");
const Size = @import("../data.zig").Size;
const DataWrapper = @import("../data.zig").DataWrapper;
const Widget = @import("../widget.zig").Widget;

pub const MenuItem = struct {
    config: Config,
    /// If there are no items, this is a menu item
    /// Otherwise, this is a menu
    items: []const MenuItem = &.{},
};

pub const MenuBar = struct { menus: []const MenuItem };

const Config = struct {
    pub const Callback = fn () void;

    label: [:0]const u8,
    onClick: ?*const Callback = null,
};

pub fn menuItem(config: Config) MenuItem {
    return MenuItem{ .config = config };
}

/// 'items' is a tuple
pub fn menu(config: Config, items: anytype) MenuItem {
    return MenuItem{ .config = config, .items = internal.lasting_allocator.dupe(MenuItem, &items) catch unreachable };
}

/// 'menus' is a tuple
pub fn menuBar(menus: anytype) MenuBar {
    return MenuBar{ .menus = internal.lasting_allocator.dupe(MenuItem, &menus) catch unreachable };
}
