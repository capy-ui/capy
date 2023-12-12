// Courtesy of https://github.com/hazeycode/zig-objcrt
const std = @import("std");
const c = @import("c.zig");
const trait = @import("../../trait.zig");

/// Sends a message to an id or Class and returns the return value of the called method
pub fn msgSend(comptime ReturnType: type, target: anytype, selector: SEL, args: anytype) ReturnType {
    const target_type = @TypeOf(target);
    if ((target_type == id or target_type == Class) == false) @compileError("msgSend target should be of type id or Class");

    const args_meta = @typeInfo(@TypeOf(args)).Struct.fields;

    if (comptime !trait.isContainer(ReturnType)) {
        const FnType = blk: {
            {
                // TODO(hazeycode): replace this hack with the more generalised code above once it doens't crash the compiler
                break :blk *const switch (args_meta.len) {
                    0 => fn (@TypeOf(target), SEL) callconv(.C) ReturnType,
                    1 => fn (@TypeOf(target), SEL, args_meta[0].type) callconv(.C) ReturnType,
                    2 => fn (@TypeOf(target), SEL, args_meta[0].type, args_meta[1].type) callconv(.C) ReturnType,
                    3 => fn (@TypeOf(target), SEL, args_meta[0].type, args_meta[1].type, args_meta[2].type) callconv(.C) ReturnType,
                    4 => fn (@TypeOf(target), SEL, args_meta[0].type, args_meta[1].type, args_meta[2].type, args_meta[3].type) callconv(.C) ReturnType,
                    5 => fn (@TypeOf(target), SEL, args_meta[0].type, args_meta[1].type, args_meta[2].type, args_meta[3].type, args_meta[4].type) callconv(.C) ReturnType,
                    else => @compileError("Unsupported number of args: add more variants in zig-objcrt/src/message.zig"),
                };
            }
        };
        // NOTE: func is a var because making it const causes a compile error which I believe is a compiler bug
        const func = @as(FnType, @ptrCast(&c.objc_msgSend));
        return @call(.auto, func, .{ target, selector } ++ args);
    } else {
        const FnType = blk: {
            {
                // TODO(hazeycode): replace this hack with the more generalised code above once it doens't crash the compiler
                break :blk *const switch (args_meta.len) {
                    0 => fn (*ReturnType, @TypeOf(target), SEL) callconv(.C) void,
                    1 => fn (*ReturnType, @TypeOf(target), SEL, args_meta[0].type) callconv(.C) void,
                    2 => fn (*ReturnType, @TypeOf(target), SEL, args_meta[0].type, args_meta[1].type) callconv(.C) void,
                    else => @compileError("Unsupported number of args: add more variants in zig-objcrt/src/message.zig"),
                };
            }
        };
        // NOTE: func is a var because making it const causes a compile error which I believe is a compiler bug
        const func = @as(FnType, @ptrCast(&c.objc_msgSend_stret));
        var stret: ReturnType = undefined;
        _ = @call(.auto, func, .{ &stret, target, selector } ++ args);
        return stret;
    }
}

pub fn object_getClass(obj: id) Error!Class {
    return c.object_getClass(obj) orelse Error.FailedToGetClassForObject;
}

pub fn class_getClassMethod(class: Class, selector: SEL) ?Method {
    return c.class_getClassMethod(class, selector);
}

pub fn class_getInstanceMethod(class: Class, selector: SEL) ?Method {
    return c.class_getInstanceMethod(class, selector);
}

pub fn msgSendChecked(comptime ReturnType: type, target: anytype, selector: SEL, args: anytype) !ReturnType {
    switch (@TypeOf(target)) {
        Class => {
            if (class_getClassMethod(target, selector) == null) return Error.ClassDoesNotRespondToSelector;
        },
        id => {
            const class = try object_getClass(target);
            if (class_getInstanceMethod(class, selector) == null) return Error.InstanceDoesNotRespondToSelector;
        },
        else => @compileError("Invalid msgSend target type. Must be a Class or id"),
    }
    return msgSend(ReturnType, target, selector, args);
}

/// The same as calling msgSendChecked except takes a selector name instead of a selector
pub fn msgSendByName(comptime ReturnType: type, target: anytype, sel_name: [:0]const u8, args: anytype) !ReturnType {
    const selector = try sel_getUid(sel_name);
    return msgSendChecked(ReturnType, target, selector, args);
}

pub fn alloc(class: Class) !id {
    const alloc_sel = try sel_getUid("alloc");
    return try msgSendChecked(id, class, alloc_sel, .{});
}

pub fn new(class: Class) !id {
    const new_sel = try sel_getUid("new");
    return try msgSendChecked(id, class, new_sel, .{});
}

// TODO(hazeycode): add missing definitions
pub const Error = error{ FailedToRegisterMethodName, ClassNotRegisteredWithRuntime, ClassDoesNotRespondToSelector, InstanceDoesNotRespondToSelector, FailedToGetClassForObject };

pub const Method = *c.objc_method;

/// An opaque type that represents an Objective-C class.
pub const Class = *c.objc_class;

/// Represents an instance of a class.
pub const object = c.objc_object;

/// A pointer to an instance of a class.
pub const id = *object;

/// An opaque type that represents a method selector.
pub const SEL = *c.objc_selector;

/// A pointer to the function of a method implementation.
pub const IMP = *const anyopaque;

pub const BOOL = i8;

/// Registers a method with the Objective-C runtime system, maps the method
/// name to a selector, and returns the selector value.
///
/// @param str The name of the method you wish to register.
///
/// Returns A pointer of type SEL specifying the selector for the named method.
///
/// NOTE: You must register a method name with the Objective-C runtime system to obtain the
/// method’s selector before you can add the method to a class definition. If the method name
/// has already been registered, this function simply returns the selector.
pub fn sel_registerName(str: [:0]const u8) Error!SEL {
    return c.sel_registerName(str) orelse Error.FailedToRegisterMethodName;
}

/// Registers a method name with the Objective-C runtime system.
/// The implementation of this method is identical to the implementation of sel_registerName.
///
/// @param str The name of the method you wish to register.
///
/// Returns A pointer of type SEL specifying the selector for the named method.
///
/// NOTE: Prior to OS X version 10.0, this method tried to find the selector mapped to the given name
///  and returned NULL if the selector was not found. This was changed for safety, because it was
///  observed that many of the callers of this function did not check the return value for NULL.
pub fn sel_getUid(str: [:0]const u8) Error!SEL {
    return c.sel_getUid(str) orelse Error.FailedToRegisterMethodName;
}

pub fn getClass(class_name: [:0]const u8) Error!Class {
    return c.objc_getClass(class_name) orelse Error.ClassNotRegisteredWithRuntime;
}

pub const CGFloat = switch (@import("builtin").target.ptrBitWidth()) {
    64 => f64,
    32 => f32,
    else => unreachable,
};

pub const NSRect = CGRect;

pub const CGPoint = extern struct {
    x: CGFloat,
    y: CGFloat,
};

pub const CGSize = extern struct {
    width: CGFloat,
    height: CGFloat,
};

pub const CGRect = extern struct {
    origin: CGPoint,
    size: CGSize,

    pub fn make(x: CGFloat, y: CGFloat, w: CGFloat, h: CGFloat) CGRect {
        return .{
            .origin = .{ .x = x, .y = y },
            .size = .{ .width = w, .height = h },
        };
    }
};
