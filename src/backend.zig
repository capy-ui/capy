const std = @import("std");
const builtin = @import("builtin");

const backend = //if (@hasDecl(@import("root"), "capyBackend"))
    //    @import("root").capyBackend
    //else
    switch (builtin.os.tag) {
    .windows => @import("backends/win32/backend.zig"),
    .macos => @import("backends/macos/backend.zig"),
    .linux, .freebsd => blk: {
        if (builtin.target.isAndroid()) {
            break :blk @import("backends/android/backend.zig");
        } else {
            break :blk @import("backends/gtk/backend.zig");
        }
    },
    .freestanding => blk: {
        if (builtin.cpu.arch == .wasm32 or builtin.cpu.arch == .wasm64) {
            break :blk @import("backends/wasm/backend.zig");
        } else {
            @compileError("Unsupported OS: freestanding");
        }
    },
    else => @compileError(std.fmt.comptimePrint("Unsupported OS: {}", .{builtin.os.tag})),
};
pub usingnamespace backend;

test {
    // ensure selected backend atleast compiles
    std.testing.refAllDecls(backend);
}

test "backend: create window" {
    try backend.init();
    var window = try backend.Window.create();
    defer window.deinit();
    window.show();

    var prng = std.rand.Xoshiro256.init(0);
    var random = prng.random();

    {
        var i: usize = 0;
        while (i < 300) : (i += 1) {
            if (i == 150) {
                window.close();
            }
            window.resize(random.int(u16), random.int(u16));
            try std.testing.expectEqual(i < 150, backend.runStep(.Asynchronous));

            std.time.sleep(1 * std.time.ns_per_ms);
        }
    }
}

test "backend: text field" {
    try backend.init();
    var field = try backend.TextField.create();
    defer field.deinit();
    field.setText("Hello, World!");
    try std.testing.expectEqualStrings("Hello, World!", field.getText());

    const str = "שָׁלוֹםUnicode 👩‍👦‍👦 नमस्ते";
    field.setText(str);
    try std.testing.expectEqualStrings(str, field.getText());

    field.setReadOnly(true);
    field.setReadOnly(false);
}

test "backend: scrollable" {
    try backend.init();
    var scrollable = try backend.ScrollView.create();
    defer scrollable.deinit();

    // TODO: more tests
}
