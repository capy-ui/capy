const capy = @import("capy");
const std = @import("std");

// Small block needed for correct WebAssembly support
pub usingnamespace capy.cross_platform;

var graph: LineGraph_Impl = undefined;

pub const LineGraph_Impl = struct {
    pub usingnamespace capy.internal.All(LineGraph_Impl);

    peer: ?capy.backend.Canvas = null,
    handlers: LineGraph_Impl.Handlers = undefined,
    dataWrappers: LineGraph_Impl.DataWrappers = .{},
    dataFn: *const fn (x: f32) f32,

    pub fn init(dataFn: *const fn (x: f32) f32) LineGraph_Impl {
        return LineGraph_Impl.init_events(LineGraph_Impl{ .dataFn = dataFn });
    }

    pub fn draw(self: *LineGraph_Impl, ctx: *capy.DrawContext) !void {
        const width = self.getWidth();
        const height = self.getHeight();
        ctx.setColor(1, 1, 1);
        ctx.rectangle(0, 0, width, height);
        ctx.fill();

        var x: f32 = 0;
        var minValue: f32 = 0;
        var maxValue: f32 = 0;
        while (x < 10) : (x += 0.1) {
            const value = self.dataFn(x);
            maxValue = std.math.max(maxValue, value);
            minValue = std.math.min(minValue, value);
        }
        maxValue += maxValue / 10;
        minValue += minValue / 10;

        var legendValue: f32 = minValue;
        var legendBuf: [100]u8 = undefined; // the program can't handle a number that is 100 digits long so it's enough
        var legendLayout = capy.DrawContext.TextLayout.init();
        defer legendLayout.deinit();
        legendLayout.setFont(.{ .face = "Arial", .size = 12.0 });

        while (legendValue < maxValue) : (legendValue += (maxValue - minValue) / 10) {
            const y = @intCast(i32, height) - @floatToInt(i32, @floor((legendValue - minValue) * (@intToFloat(f32, height) / (maxValue - minValue))));
            const text = try std.fmt.bufPrint(&legendBuf, "{d:.1}", .{legendValue});

            ctx.setColor(0, 0, 0);
            ctx.text(0, y, legendLayout, text);
            ctx.line(0, y, @intCast(i32, width), y);
            ctx.stroke();
        }

        x = 0;
        var oldX: i32 = 0;
        var oldY: i32 = 0;
        while (x < 10) : (x += 0.1) {
            const y = self.dataFn(x);
            var dy = @intCast(i32, height) - @floatToInt(i32, @floor((y - minValue) * (@intToFloat(f32, height) / (maxValue - minValue))));
            var dx = @floatToInt(i32, @floor(x * 100)) + 50;
            if (dy < 0) dy = 0;
            if (dx < 0) dx = 0;
            if (oldY == 0) oldY = dy;

            ctx.setColor(0, 0, 0);
            ctx.line(oldX, oldY, dx, dy);
            ctx.stroke();
            ctx.ellipse(oldX - 3, oldY - 3, 6, 6);
            ctx.fill();
            oldX = dx;
            oldY = dy;
        }
    }

    pub fn show(self: *LineGraph_Impl) !void {
        if (self.peer == null) {
            self.peer = try capy.backend.Canvas.create();
            try self.show_events();
        }
    }

    pub fn getPreferredSize(self: *LineGraph_Impl, available: capy.Size) capy.Size {
        _ = self;
        _ = available;
        return capy.Size{ .width = 500.0, .height = 200.0 };
    }
};

pub fn LineGraph(config: struct { dataFn: *const fn (x: f32) f32 }) !LineGraph_Impl {
    var lineGraph = LineGraph_Impl.init(config.dataFn);
    try lineGraph.addDrawHandler(&LineGraph_Impl.draw);
    return lineGraph;
}

const smoothData = true;
const myData = [_]f32{ 0.0, 1.0, 5.0, 4.0, 3.0, 2.0, 6.0, 0.0 };

fn lerp(a: f32, b: f32, t: f32) f32 {
    return a * (1 - t) + b * t;
}

fn myDataFunction(x: f32) f32 {
    if (x < 0) return 0;
    const idx = @floatToInt(usize, @floor(x));
    if (idx >= myData.len) return 0;

    if (smoothData) {
        const fract = std.math.modf(x).fpart;
        const cur = myData[idx];
        const next = if (idx + 1 >= myData.len) myData[idx] else myData[idx + 1];
        return lerp(cur, next, fract);
    } else {
        return myData[idx];
    }
}

fn sinus(x: f32) f32 {
    return std.math.sin(x);
}

fn stdNormDev(x: f32) f32 {
    const ps = std.math.sqrt(2 * std.math.pi);
    const exp = std.math.exp(-(x * x / 2.0));
    return exp / ps;
}

var rand = std.rand.DefaultPrng.init(0);
fn randf(x: f32) f32 {
    _ = x;
    return rand.random().float(f32);
}

fn easing(x: f32) f32 {
    return @floatCast(f32, capy.Easings.Linear(x / 10.0));
}

// This demonstrates how you can use Zig's ability to generate functions at compile-time
// in order to make cool and useful things
fn SetEasing(comptime Easing: fn (x: f64) f64) fn (*anyopaque) anyerror!void {
    const func = struct {
        pub fn function(x: f32) f32 {
            return @floatCast(f32, Easing(x / 10.0));
        }
    }.function;

    const callback = struct {
        // TODO: switch back to *capy.Button_Impl when ziglang/zig#12325 is fixed
        pub fn callback(_: *anyopaque) anyerror!void {
            graph.dataFn = func;
            try graph.requestDraw();
        }
    }.callback;
    return callback;
}

// TODO: switch back to *capy.Canvas_Impl when ziglang/zig#12325 is fixed
fn drawRectangle(_: *anyopaque, ctx: *capy.Canvas_Impl.DrawContext) !void {
    ctx.setColor(0, 0, 0);
    ctx.rectangle(0, 0, 100, 100);
    ctx.fill();
}

var rectangleX = capy.DataWrapper(f32).of(0.1);
var animStart: i64 = 0;
pub fn main() !void {
    try capy.backend.init();

    var window = try capy.Window.init();
    graph = try LineGraph(.{ .dataFn = easing });

    var rectangle = (try capy.Align(
        .{},
        capy.Canvas(.{
            .preferredSize = capy.Size{ .width = 100, .height = 100 },
            .ondraw = drawRectangle,
        }),
    ))
        .bind("x", &rectangleX);

    try window.set(capy.Column(.{}, .{
        capy.Align(.{}, capy.Row(.{ .spacing = 10 }, .{
            capy.Button(.{ .label = "Linear", .onclick = SetEasing(capy.Easings.Linear) }),
            capy.Button(.{ .label = "In", .onclick = SetEasing(capy.Easings.In) }),
            capy.Button(.{ .label = "Out", .onclick = SetEasing(capy.Easings.Out) }),
            capy.Button(.{ .label = "In Out", .onclick = SetEasing(capy.Easings.InOut) }),
        })),
        capy.Expanded(&graph),
        &rectangle,
    }));

    window.resize(800, 600);
    window.show();

    while (capy.stepEventLoop(.Asynchronous)) {
        var dt = std.time.milliTimestamp() - animStart;
        if (dt > 1500) {
            animStart = std.time.milliTimestamp();
            continue;
        } else if (dt > 1000) {
            dt = 1000;
        }
        const t = @intToFloat(f32, dt) / 1000;
        rectangleX.set(graph.dataFn(t * 10.0));
        std.time.sleep(30);
    }
}
