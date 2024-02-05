const capy = @import("capy");
const std = @import("std");
pub usingnamespace capy.cross_platform;

var gpa: std.heap.GeneralPurposeAllocator(.{}) = undefined;
pub const capy_allocator = gpa.allocator();

var pitch = capy.Atom(f32).of(440.0);

fn sine(generator: *const capy.audio.AudioGenerator, time: u64, n_frames: u32) void {
    const left = generator.getBuffer(0);
    const right = generator.getBuffer(1);

    var i: u32 = 0;
    const frequency = pitch.get();

    const seconds_per_frame = 1.0 / 44100.0;

    const time_seconds: f64 = @as(f64, @floatFromInt(time)) / 44100.0;

    while (i < n_frames) : (i += 1) {
        const inner_time = (time_seconds + @as(f64, @floatFromInt(i)) * seconds_per_frame) * 2 * std.math.pi * frequency;
        const value: f32 = @floatCast(@sin(inner_time));
        left[i] = value;
        right[i] = value;
    }
}

pub fn main() !void {
    gpa = .{};
    defer _ = gpa.deinit();

    try capy.init();
    defer capy.deinit();

    var window = try capy.Window.init();
    defer window.deinit();

    try window.set(
        capy.alignment(.{}, capy.column(.{}, .{
            rotatingDisc(), // TODO
            capy.label(.{ .text = "Audio Name", .alignment = .Center }),
            capy.slider(.{ .min = 40, .max = 2000, .step = 1 })
                .bind("value", &pitch),
        })),
    );

    window.show();

    var generator = try capy.audio.AudioGenerator.init(sine, 2);
    try generator.register();

    generator.play();

    capy.runEventLoop();
}

/// A spinning CD disc with the thumbnail of the audio or none if there isn't any
fn rotatingDisc() !*capy.Canvas {
    var canvas = capy.canvas(.{
        .preferredSize = capy.Size.init(256, 256),
    });
    try canvas.addDrawHandler(&drawRotatingDisc);
    return canvas;
}

fn drawRotatingDisc(self: *capy.Canvas, ctx: *capy.DrawContext) anyerror!void {
    const width = self.getWidth();
    const height = self.getHeight();

    // TODO: we need multiply drawing (with circle) or arbitrary clipping paths
    // it should be able to handle an outer circle and an inner circle for the CD disc
    // TODO: do that clipping in path? transform path into clipping?

    ctx.setColor(0, 0, 0);
    ctx.ellipse(0, 0, width, height);
    ctx.fill();

    ctx.setColor(1, 1, 1);
    ctx.ellipse(@as(i32, @intCast(width / 2 -| 20)), @as(i32, @intCast(height / 2 -| 20)), 40, 40);
    ctx.fill();

    ctx.setColor(0.9, 0.9, 0.9);
    ctx.ellipse(@as(i32, @intCast(width / 2 -| 15)), @as(i32, @intCast(height / 2 -| 15)), 30, 30);
    ctx.fill();
}
