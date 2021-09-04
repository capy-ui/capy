pub const Window = @import("window.zig").Window;

pub usingnamespace @import("button.zig");
pub usingnamespace @import("label.zig");
pub usingnamespace @import("text.zig");
pub usingnamespace @import("canvas.zig");
pub usingnamespace @import("containers.zig");
pub usingnamespace @import("data.zig");

pub const internal = @import("internal.zig");
pub const backend  = @import("backend.zig");

// TODO: widget types with comptime reflection (some sort of vtable)
