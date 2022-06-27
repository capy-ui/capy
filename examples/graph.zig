const zgt = @import("zgt");
const std = @import("std");

// Small block needed for correct WebAssembly support
pub usingnamespace zgt.cross_platform;

var graph: LineGraph_Impl = undefined;

pub const LineGraph_Impl = struct {
    pub usingnamespace zgt.internal.All(LineGraph_Impl);

    peer: ?zgt.backend.Canvas = null,
    handlers: LineGraph_Impl.Handlers = undefined,
    dataWrappers: LineGraph_Impl.DataWrappers = .{},
    dataFn: fn (x: f32) f32,

    pub fn init(dataFn: fn (x: f32) f32) LineGraph_Impl {
        return LineGraph_Impl.init_events(LineGraph_Impl{ .dataFn = dataFn });
    }

    pub fn draw(self: *LineGraph_Impl, ctx: *zgt.DrawContext) !void {
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
        var legendLayout = zgt.DrawContext.TextLayout.init();
        defer legendLayout.deinit();
        legendLayout.setFont(.{ .face = "Arial", .size = 12.0 });

        while (legendValue < maxValue) : (legendValue += (maxValue - minValue) / 10) {
            const y = @intCast(i32, height) - @floatToInt(i32, @floor((legendValue - minValue) * (@intToFloat(f32, height) / (maxValue - minValue))));
            const text = try std.fmt.bufPrint(&legendBuf, "{d:.1}", .{legendValue});
            _ = text;

            ctx.setColor(0, 0, 0);
            ctx.text(0, y, legendLayout, text);
            ctx.line(0, @intCast(u32, y), width, @intCast(u32, y));
            ctx.stroke();
        }

        x = 0;
        var oldX: u32 = 0;
        var oldY: u32 = 0;
        while (x < 10) : (x += 0.1) {
            const y = self.dataFn(x);
            var dy = @intCast(i32, height) - @floatToInt(i32, @floor((y - minValue) * (@intToFloat(f32, height) / (maxValue - minValue))));
            var dx = @floatToInt(i32, @floor(x * 100)) + 50;
            if (dy < 0) dy = 0;
            if (dx < 0) dx = 0;
            if (oldY == 0) oldY = @intCast(u32, dy);

            ctx.setColor(0, 0, 0);
            ctx.line(oldX, oldY, @intCast(u32, dx), @intCast(u32, dy));
            ctx.stroke();
            ctx.ellipse(oldX, oldY, 3, 3);
            ctx.fill();
            oldX = @intCast(u32, dx);
            oldY = @intCast(u32, dy);
        }
    }

    pub fn show(self: *LineGraph_Impl) !void {
        if (self.peer == null) {
            self.peer = try zgt.backend.Canvas.create();
            try self.show_events();
        }
    }

    pub fn getPreferredSize(self: *LineGraph_Impl, available: zgt.Size) zgt.Size {
        _ = self;
        _ = available;
        return zgt.Size{ .width = 500.0, .height = 200.0 };
    }
};

pub fn LineGraph(config: struct { dataFn: fn (x: f32) f32 }) !LineGraph_Impl {
    var lineGraph = try LineGraph_Impl.init(config.dataFn)
        .addDrawHandler(LineGraph_Impl.draw);
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
    return @floatCast(f32, zgt.Easings.Linear(x / 10.0));
}

fn SetEasing(comptime Easing: fn (x: f64) f64) fn (*zgt.Button_Impl) anyerror!void {
    const func = struct {
        pub fn function(x: f32) f32 {
            return @floatCast(f32, Easing(x / 10.0));
        }
    }.function;

    const callback = struct {
        pub fn callback(btn: *zgt.Button_Impl) anyerror!void {
            _ = btn;
            graph.dataFn = func;
            try graph.requestDraw();
        }
    }.callback;
    return callback;
}

fn drawRectangle(widget: *zgt.Canvas_Impl, ctx: *zgt.Canvas_Impl.DrawContext) !void {
    _ = widget;
    ctx.setColor(0, 0, 0);
    ctx.rectangle(0, 0, 100, 100);
    ctx.fill();
}

var rectangleX = zgt.DataWrapper(?f32).of(0.1);
var animStart: i64 = 0;
pub fn main() !void {
    try zgt.backend.init();

    var window = try zgt.Window.init();
    graph = try LineGraph(.{ .dataFn = easing });

    var rectangle = (try zgt.Column(.{}, .{zgt.Canvas(.{})
        .setPreferredSize(zgt.Size{ .width = 100, .height = 100 })
        .addDrawHandler(drawRectangle)}))
        .bindAlignX(&rectangleX);

    try window.set(zgt.Column(.{}, .{
        zgt.Row(.{ .spacing = 10, .alignX = 0.5 }, .{
            zgt.Button(.{ .label = "Linear", .onclick = SetEasing(zgt.Easings.Linear) }),
            zgt.Button(.{ .label = "In", .onclick = SetEasing(zgt.Easings.In) }),
            zgt.Button(.{ .label = "Out", .onclick = SetEasing(zgt.Easings.Out) }),
            zgt.Button(.{ .label = "In Out", .onclick = SetEasing(zgt.Easings.InOut) }),
        }),
        zgt.Expanded(&graph),
        &rectangle,
    }));

    window.resize(800, 600);
    window.show();

    while (zgt.stepEventLoop(.Asynchronous)) {
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
