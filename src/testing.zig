//! Testing module for Capy applications
const capy = @import("capy.zig");

pub const VirtualWindow = struct {
    window: capy.Window,

    pub fn init() !VirtualWindow {
        const window = try capy.Window.init();
        return VirtualWindow{ .window = window };
    }

    pub fn deinit(self: *VirtualWindow) void {
        self.window.deinit();
    }

    // TODO: methods: expectFocused, expectNotFocused, pressKey, click, expectVisible,
    // expectNotVisible, hash (to check if two states are identical or not) ...
};
