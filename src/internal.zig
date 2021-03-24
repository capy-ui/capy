const root = @import("root");
const std = @import("std");

/// Allocator used for small, short-lived and repetitive allocations.
/// You can change this by setting the `zgtScratchAllocator` field in your main file
/// or by setting the `zgtAllocator` field which will also apply as lasting allocator.
pub const scratch_allocator = if (@hasDecl(root, "zgtScratchAllocator")) root.zgtScratchAllocator
    else if (@hasDecl(root, "zgtAllocator")) root.zgtAllocator
    else std.heap.page_allocator;

/// Allocator used for bigger, longer-lived but rare allocations (example: widgets).
/// You can change this by setting the `zgtLastingAllocator` field in your main file
/// or by setting the `zgtAllocator` field which will also apply as scratch allocator.
pub const lasting_allocator = if (@hasDecl(root, "zgtLastingAllocator")) root.zgtScratchAllocator
    else if (@hasDecl(root, "zgtAllocator")) root.zgtAllocator
    else std.heap.page_allocator;
