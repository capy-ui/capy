pub usingnamespace @import("window.zig");
pub usingnamespace @import("button.zig");
pub usingnamespace @import("label.zig");
pub usingnamespace @import("text.zig");
pub usingnamespace @import("canvas.zig");
pub usingnamespace @import("containers.zig");

// TODO: widget types with comptime reflection (some sort of vtable)

pub usingnamespace 
    if (@hasDecl(@import("root"), "main")) // do not import a main function if the root file already has one
        struct {}
    else
        @import("backend.zig").public;
