const capy = @import("capy");
const std = @import("std");

// Small block needed for correct WebAssembly support
pub usingnamespace capy.cross_platform;

pub const LineGraph = struct {
    pub usingnamespace capy.internal.All(LineGraph);

    peer: ?capy.backend.Canvas = null,
    widget_data: LineGraph.WidgetData = .{},
    dataFn: capy.Atom(*const fn (x: f32) f32),

    pub fn init(config: LineGraph.Config) LineGraph {
        var line_graph = LineGraph.init_events(LineGraph{ .dataFn = capy.Atom(*const fn (x: f32) f32).of(config.dataFn) });
        line_graph.addDrawHandler(&LineGraph.draw) catch unreachable;
        return line_graph;
    }

    pub fn draw(self: *LineGraph, ctx: *capy.DrawContext) !void {
        const width = self.getWidth();
        const height = self.getHeight();
        ctx.setColor(1, 1, 1);
        ctx.rectangle(0, 0, width, height);
        ctx.fill();

        var x: f32 = 0;
        var minValue: f32 = 0;
        var maxValue: f32 = 0;
        while (x < 10) : (x += 0.1) {
            const value = self.dataFn.get()(x);
            maxValue = @max(maxValue, value);
            minValue = @min(minValue, value);
        }
        maxValue += maxValue / 10;
        minValue += minValue / 10;

        var legendValue: f32 = minValue;
        var legendBuf: [100]u8 = undefined; // the program can't handle a number that is 100 digits long so it's enough
        var legendLayout = capy.DrawContext.TextLayout.init();
        defer legendLayout.deinit();
        legendLayout.setFont(.{ .face = "Arial", .size = 12.0 });

        while (legendValue < maxValue) : (legendValue += (maxValue - minValue) / 10) {
            const y = @as(i32, @intCast(height)) - @as(i32, @intFromFloat(@floor((legendValue - minValue) * (@as(f32, @floatFromInt(height)) / (maxValue - minValue)))));
            const text = try std.fmt.bufPrint(&legendBuf, "{d:.1}", .{legendValue});

            ctx.setColor(0, 0, 0);
            ctx.text(0, y, legendLayout, text);
            ctx.line(0, y, @as(i32, @intCast(width)), y);
            ctx.stroke();
        }

        x = 0;
        var oldX: i32 = 0;
        var oldY: i32 = 0;
        while (x < 10) : (x += 0.1) {
            const y = self.dataFn.get()(x);
            var dy = @as(i32, @intCast(height)) - @as(i32, @intFromFloat(@floor((y - minValue) * (@as(f32, @floatFromInt(height)) / (maxValue - minValue)))));
            var dx = @as(i32, @intFromFloat(@floor(x * 100))) + 50;
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

    fn onDataFnAtomChanged(_: *const fn (f32) f32, userdata: ?*anyopaque) void {
        const self: *LineGraph = @ptrCast(@alignCast(userdata.?));
        self.requestDraw() catch {};
    }

    pub fn show(self: *LineGraph) !void {
        if (self.peer == null) {
            self.peer = try capy.backend.Canvas.create();
            _ = try self.dataFn.addChangeListener(.{ .function = onDataFnAtomChanged, .userdata = self });
            try self.setupEvents();
        }
    }

    pub fn getPreferredSize(self: *LineGraph, available: capy.Size) capy.Size {
        _ = self;
        _ = available;
        return capy.Size{ .width = 500.0, .height = 200.0 };
    }
};

pub fn lineGraph(config: LineGraph.Config) *LineGraph {
    return LineGraph.alloc(config);
}

const smoothData = true;
const myData = [_]f32{ 0.0, 1.0, 5.0, 4.0, 3.0, 2.0, 6.0, 0.0 };

fn lerp(a: f32, b: f32, t: f32) f32 {
    return a * (1 - t) + b * t;
}

fn myDataFunction(x: f32) f32 {
    if (x < 0) return 0;
    const idx = @as(usize, @intFromFloat(@floor(x)));
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
    return @as(f32, @floatCast(capy.Easings.Linear(x / 10.0)));
}

// This demonstrates how you can use Zig's ability to generate functions at compile-time
// in order to make cool and useful things
fn SetEasing(comptime Easing: fn (x: f64) f64) fn (*anyopaque) anyerror!void {
    const func = struct {
        pub fn function(x: f32) f32 {
            return @as(f32, @floatCast(Easing(x / 10.0)));
        }
    }.function;

    const callback = struct {
        // TODO: switch back to *capy.Button_Impl when ziglang/zig#12325 is fixed
        pub fn callback(_: *anyopaque) anyerror!void {
            graph.dataFn.set(func);
            try graph.requestDraw();
        }
    }.callback;
    return callback;
}

// TODO: switch back to *capy.Canvas_Impl when ziglang/zig#12325 is fixed
fn drawRectangle(_: *anyopaque, ctx: *capy.Canvas.DrawContext) !void {
    ctx.setColor(0, 0, 0);
    ctx.rectangle(0, 0, 100, 100);
    ctx.fill();
}

var graph: *LineGraph = undefined;
pub fn main() !void {
    try capy.backend.init();

    var rectangleX = capy.Atom(f32).of(0);
    var window = try capy.Window.init();
    graph = lineGraph(.{ .dataFn = easing });

    try window.set(capy.column(.{}, .{
        capy.alignment(.{}, capy.row(.{ .spacing = 10 }, .{
            capy.button(.{ .label = "Linear", .onclick = SetEasing(capy.Easings.Linear) }),
            capy.button(.{ .label = "In", .onclick = SetEasing(capy.Easings.In) }),
            capy.button(.{ .label = "Out", .onclick = SetEasing(capy.Easings.Out) }),
            capy.button(.{ .label = "In Out", .onclick = SetEasing(capy.Easings.InOut) }),
        })),
        capy.expanded(graph),
        (try capy.alignment(
            .{},
            capy.rect(.{
                .preferredSize = capy.Size{ .width = 100, .height = 100 },
                .color = capy.Color.black,
            }),
        ))
            .bind("x", &rectangleX),
    }));

    window.setPreferredSize(800, 600);
    window.show();

    const ListenerData = struct {
        rectangleX: *capy.Atom(f32),
        animStart: i64,
    };
    var listener_data = ListenerData{
        .rectangleX = &rectangleX,
        .animStart = std.time.milliTimestamp(),
    };

    // Listeners are always deinitialized when the event source is destroyed.
    // In this case, this means it will be deinitialized when the window is destroyed.
    // Therefore, as long as we don't want to remove it mid-program, we don't have to deinit this listener manually
    _ = try window.on_frame.listen(.{
        .callback = struct {
            fn callback(userdata: ?*anyopaque) void {
                const data: *ListenerData = @ptrCast(@alignCast(userdata.?));
                var dt = std.time.milliTimestamp() - data.animStart;
                if (dt > 1500)
                    data.animStart = std.time.milliTimestamp();
                if (dt > 1000)
                    dt = 1000;
                const t = @as(f32, @floatFromInt(dt)) / 1000;
                data.rectangleX.set(graph.dataFn.get()(t * 10.0));
            }
        }.callback,
        .userdata = &listener_data,
    });
    capy.runEventLoop();
}
