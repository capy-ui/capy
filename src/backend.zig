const std = @import("std");
const builtin = @import("builtin");
const capy = @import("capy.zig");
const shared = @import("backends/shared.zig");

const backend = //if (@hasDecl(@import("root"), "capyBackend"))
    //    @import("root").capyBackend
    //else
    switch (builtin.os.tag) {
        .windows => @import("backends/win32/backend.zig"),
        .macos => @import("backends/macos/backend.zig"),
        .linux, .freebsd => blk: {
            if (builtin.target.abi.isAndroid()) {
                break :blk @import("backends/android/backend.zig");
            } else {
                break :blk @import("backends/gtk/backend.zig");
            }
        },
        .wasi => blk: {
            if (builtin.cpu.arch == .wasm32 or builtin.cpu.arch == .wasm64) {
                break :blk @import("backends/wasm/backend.zig");
            } else {
                @compileError("Unsupported OS: wasi");
            }
        },
        else => @compileError(std.fmt.comptimePrint("Unsupported OS: {}", .{builtin.os.tag})),
    };
pub usingnamespace backend;

pub const DrawContext = struct {
    impl: backend.Canvas.DrawContextImpl,

    pub const TextLayout = backend.Canvas.DrawContextImpl.TextLayout;

    /// Use the given sRGB color as a fill and stroke color.
    pub fn setColorByte(self: *DrawContext, color: capy.Color) void {
        self.setColorRGBA(
            @as(f32, @floatFromInt(color.red)) / 255.0,
            @as(f32, @floatFromInt(color.green)) / 255.0,
            @as(f32, @floatFromInt(color.blue)) / 255.0,
            @as(f32, @floatFromInt(color.alpha)) / 255.0,
        );
    }

    /// Use the given color as a fill and stroke color.
    /// The usual sRGB range corresponds to 0.0 - 1.0 for each component. Going beyond requires HDR.
    pub fn setColor(self: *DrawContext, r: f32, g: f32, b: f32) void {
        self.setColorRGBA(r, g, b, 1.0);
    }

    /// Use the given color as a fill and stroke color.
    /// The usual sRGB range corresponds to 0.0 - 1.0 for each component. Going beyond requires HDR.
    pub fn setColorRGBA(self: *DrawContext, r: f32, g: f32, b: f32, a: f32) void {
        self.impl.setColorRGBA(r, g, b, a);
    }

    /// Use the given gradient for filling and stroking.
    pub fn setLinearGradient(self: *DrawContext, gradient: shared.LinearGradient) void {
        self.impl.setLinearGradient(gradient);
    }

    /// Add a rectangle to the current path
    pub fn rectangle(self: *DrawContext, x: i32, y: i32, w: u32, h: u32) void {
        self.impl.rectangle(x, y, w, h);
    }

    /// Add a rounded rectangle to the current path, with the same roundness on each corner.
    pub fn roundedRectangle(self: *DrawContext, x: i32, y: i32, w: u32, h: u32, corner_radius: f32) void {
        self.roundedRectangleEx(x, y, w, h, @splat(corner_radius));
    }

    /// Add a rounded rectangle to the current path, each corner size can be configured
    /// individually. There are four corner sizes corresponding to the top-left, top-right,
    /// bottom-left and bottom-right respectively.
    pub fn roundedRectangleEx(self: *DrawContext, x: i32, y: i32, w: u32, h: u32, corner_radiuses: [4]f32) void {
        self.impl.roundedRectangleEx(x, y, w, h, corner_radiuses);
    }

    /// Add an ellipse to the current path
    pub fn ellipse(self: *DrawContext, x: i32, y: i32, w: u32, h: u32) void {
        self.impl.ellipse(x, y, w, h);
    }

    /// Immediately draw the following text
    pub fn text(self: *DrawContext, x: i32, y: i32, layout: TextLayout, str: []const u8) void {
        self.impl.text(x, y, layout, str);
    }

    /// Immediately draw the given line
    pub fn line(self: *DrawContext, x1: i32, y1: i32, x2: i32, y2: i32) void {
        self.impl.line(x1, y1, x2, y2);
    }

    /// Immediately draw the given image. The image is stretched to fit the destination rectangle.
    pub fn image(self: *DrawContext, x: i32, y: i32, w: u32, h: u32, data: capy.ImageData) void {
        self.impl.image(x, y, w, h, data);
    }

    /// Clear the specified region and set it to the background color
    pub fn clear(self: *DrawContext, x: u32, y: u32, w: u32, h: u32) void {
        self.impl.clear(x, y, w, h);
    }

    pub fn setStrokeWidth(self: *DrawContext, width: f32) void {
        self.impl.setStrokeWidth(width);
    }

    /// Stroke the current path and reset the path
    pub fn stroke(self: *DrawContext) void {
        self.impl.stroke();
    }

    /// Fill the current path and reset the path
    pub fn fill(self: *DrawContext) void {
        self.impl.fill();
    }
};

test {
    // ensure the selected backend atleast compiles
    std.testing.refAllDecls(backend);
}

test "backend: create window" {
    try backend.init();
    var window = try backend.Window.create();
    defer window.deinit();
    window.show();

    var prng = std.Random.Xoshiro256.init(std.testing.random_seed);
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

    try std.testing.fuzz({}, fuzzTextField, .{});
}

fn fuzzTextField(_: void, input: []const u8) !void {
    var field = try backend.TextField.create();
    defer field.deinit();
    field.setText(input);
    if (std.unicode.utf8ValidateSlice(input)) {
        // This constraint only holds if the input is valid UTF-8
        try std.testing.expectEqualStrings(input, field.getText());
    }
}

test "backend: button" {
    try std.testing.fuzz({}, fuzzButton, .{});
}

fn fuzzButton(_: void, input: []const u8) !void {
    var button = try backend.Button.create();
    defer button.deinit();

    const null_terminated_input = try std.testing.allocator.dupeZ(u8, input);
    defer std.testing.allocator.free(null_terminated_input);

    button.setLabel(null_terminated_input);
    if (std.unicode.utf8ValidateSlice(input)) {
        // This constraint only holds if the input is valid UTF-8
        try std.testing.expectEqualStrings(null_terminated_input, button.getLabel());
    }
}

test "backend: scrollable" {
    try backend.init();
    var scrollable = try backend.ScrollView.create();
    defer scrollable.deinit();

    // TODO: more tests
}
