const std = @import("std");
const objc = @import("objc");
const CapyAppDelegate = @This();

pub var instance: ?CapyAppDelegate = null;

obj: objc.Object,
class: objc.Class,

pub fn get() CapyAppDelegate {
    if (instance) |delegate| {
        return delegate;
    } else {
        const class = objc.allocateClassPair(objc.getClass("NSObject").?, "CapyAppDelegate").?;
        // const NSApplicationDelegate = objc.getProtocol("NSApplicationDelegate").?;
        // std.debug.assert(objc.c.class_addProtocol(class.value, NSApplicationDelegate.value) != 0);
        _ = class.addMethod("applicationDidFinishLaunching:", struct {
            fn a(self: objc.c.id, _: objc.c.SEL, notification: objc.c.id) callconv(.C) void {
                _ = notification;
                // Stop NSApplication's event loop so we can replace it by our own
                const NSApplication = objc.getClass("NSApplication").?;
                const app = NSApplication.msgSend(objc.Object, "sharedApplication", .{});
                app.msgSend(void, "stop:", .{self});
            }
        }.a) catch unreachable;

        // Stubs from the NSApplicationDelegate protocol
        // Unfortunately, a protocol only exists in the Objective-C runtime if a file imports it, but
        // NSApplicationDelegate isn't imported anywhere by default, which means we can't use it.
        // Hence the need to reimplement all methods.
        _ = class.addMethod("applicationWillFinishLaunching:", struct {
            fn a(_: objc.c.id, _: objc.c.SEL, _: objc.c.id) callconv(.C) void {}
        }.a) catch unreachable;
        _ = class.addMethod("applicationWillBecomeActive:", struct {
            fn a(_: objc.c.id, _: objc.c.SEL, _: objc.c.id) callconv(.C) void {}
        }.a) catch unreachable;
        _ = class.addMethod("applicationDidBecomeActive::", struct {
            fn a(_: objc.c.id, _: objc.c.SEL, _: objc.c.id) callconv(.C) void {}
        }.a) catch unreachable;
        _ = class.addMethod("applicationWillResignActive:", struct {
            fn a(_: objc.c.id, _: objc.c.SEL, _: objc.c.id) callconv(.C) void {}
        }.a) catch unreachable;
        _ = class.addMethod("applicationDidResignActive:", struct {
            fn a(_: objc.c.id, _: objc.c.SEL, _: objc.c.id) callconv(.C) void {}
        }.a) catch unreachable;
        const NSApplicationTerminateReply = enum(c_int) {
            Cancel = 0,
            Now = 1,
            Later = 2,
        };
        _ = class.addMethod("applicationShouldTerminate:", struct {
            fn a(_: objc.c.id, _: objc.c.SEL, _: objc.c.id) callconv(.C) c_int {
                return @intFromEnum(NSApplicationTerminateReply.Now);
            }
        }.a) catch unreachable;
        _ = class.addMethod("applicationShouldTerminateAfterLastWindowClosed:", struct {
            fn a(_: objc.c.id, _: objc.c.SEL, _: objc.c.id) callconv(.C) bool {
                return false;
            }
        }.a) catch unreachable;
        _ = class.addMethod("applicationWillTerminate:", struct {
            fn a(_: objc.c.id, _: objc.c.SEL, _: objc.c.id) callconv(.C) void {}
        }.a) catch unreachable;
        _ = class.addMethod("applicationWillHide:", struct {
            fn a(_: objc.c.id, _: objc.c.SEL, _: objc.c.id) callconv(.C) void {}
        }.a) catch unreachable;
        _ = class.addMethod("applicationDidHide:", struct {
            fn a(_: objc.c.id, _: objc.c.SEL, _: objc.c.id) callconv(.C) void {}
        }.a) catch unreachable;
        _ = class.addMethod("applicationWillUnhide:", struct {
            fn a(_: objc.c.id, _: objc.c.SEL, _: objc.c.id) callconv(.C) void {}
        }.a) catch unreachable;
        _ = class.addMethod("applicationDidUnhide:", struct {
            fn a(_: objc.c.id, _: objc.c.SEL, _: objc.c.id) callconv(.C) void {}
        }.a) catch unreachable;
        _ = class.addMethod("applicationWillUpdate:", struct {
            fn a(_: objc.c.id, _: objc.c.SEL, _: objc.c.id) callconv(.C) void {}
        }.a) catch unreachable;
        _ = class.addMethod("applicationDidUpdate:", struct {
            fn a(_: objc.c.id, _: objc.c.SEL, _: objc.c.id) callconv(.C) void {}
        }.a) catch unreachable;
        _ = class.addMethod("applicationShouldHandleReopen:hasVisibleWindows:", struct {
            fn a(_: objc.c.id, _: objc.c.SEL, _: objc.c.id, _: objc.c.id) callconv(.C) bool {
                return true;
            }
        }.a) catch unreachable;
        _ = class.addMethod("applicationDockMenu:", struct {
            fn a(_: objc.c.id, _: objc.c.SEL, _: objc.c.id) callconv(.C) objc.c.id {
                return 0;
            }
        }.a) catch unreachable;
        _ = class.addMethod("applicationShouldAutomaticallyLocalizeKeyEquivalents:", struct {
            fn a(_: objc.c.id, _: objc.c.SEL, _: objc.c.id) callconv(.C) bool {
                return true;
            }
        }.a) catch unreachable;
        _ = class.addMethod("application:willPresentError:", struct {
            fn a(_: objc.c.id, _: objc.c.SEL, _: objc.c.id) callconv(.C) void {}
        }.a) catch unreachable;
        _ = class.addMethod("applicationDidChangeScreenParameters:", struct {
            fn a(_: objc.c.id, _: objc.c.SEL, _: objc.c.id) callconv(.C) void {}
        }.a) catch unreachable;
        objc.registerClassPair(class);

        instance = CapyAppDelegate{
            .obj = class.msgSend(objc.Object, "alloc", .{})
                .msgSend(objc.Object, "init", .{}),
            .class = class,
        };
        return instance.?;
    }
}

pub fn deinit(self: CapyAppDelegate) void {
    self.class.disposeClassPair();
}
