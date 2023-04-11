//! Example of a minimal application that loads a blank screen.

pub const panic = android.panic;

comptime {
    _ = android.ANativeActivity_createFunc;
}

/// Entry point for our application.
/// This struct provides the interface to the android support package.
pub const AndroidApp = struct {
    const Self = @This();

    allocator: std.mem.Allocator,
    activity: *android.ANativeActivity,

    /// This is the entry point which initializes a application
    /// that has stored its previous state.
    /// `stored_state` is that state, the memory is only valid for this function.
    pub fn init(allocator: std.mem.Allocator, activity: *android.ANativeActivity, stored_state: ?[]const u8) !Self {
        _ = stored_state;

        return Self{
            .allocator = allocator,
            .activity = activity,
        };
    }

    /// This function is called when the application is successfully initialized.
    /// It should create a background thread that processes the events and runs until
    /// the application gets destroyed.
    pub fn start(self: *Self) !void {
        _ = self;
    }

    /// Uninitialize the application.
    /// Don't forget to stop your background thread here!
    pub fn deinit(self: *Self) void {
        self.* = undefined;
    }
};

const std = @import("std");
const android = @import("android");
