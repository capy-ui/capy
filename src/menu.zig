const std = @import("std");
const backend = @import("backend.zig");
const Size = @import("data.zig").Size;
const DataWrapper = @import("data.zig").DataWrapper;
const Widget = @import("widget.zig").Widget;

pub const MenuItem_Impl = struct {
    label: [:0]const u8,
    /// If there are no items, this is a menu item
    /// Otherwise, this is a menu
    items: []const MenuItem_Impl = &.{},
};

pub const MenuBar_Impl = struct {
    menus: []const MenuItem_Impl
};

const Config = struct {};

pub fn MenuItem(label: [:0]const u8, config: Config) MenuItem_Impl {
    _ = config;
    return MenuItem_Impl { .label = label };
}

/// 'items' is a tuple
pub fn Menu(label: [:0]const u8, items: anytype) MenuItem_Impl {
    return MenuItem_Impl { .label = label, .items = &items };
}

/// 'menus' is a tuple
pub fn MenuBar(menus: anytype) MenuBar_Impl {
    return MenuBar_Impl { .menus = &menus };
}
