const zgt = @import("zgt");
const std = @import("std");

var graph: LineGraph_Impl = undefined;

pub const LineGraph_Impl = struct {
    pub usingnamespace zgt.internal.All(LineGraph_Impl);

    peer: ?zgt.backend.Canvas = null,
    handlers: LineGraph_Impl.Handlers = undefined,
    dataFn: fn(x: f32) f32,

    pub fn init(dataFn: fn(x: f32) f32) LineGraph_Impl {
        return LineGraph_Impl.init_events(LineGraph_Impl {
            .dataFn = dataFn
        });
    }

    pub fn draw(self: *LineGraph_Impl, ctx: zgt.DrawContext) !void {
        const width = self.getWidth();
        const height = self.getHeight();
        ctx.clear(0, 0, width, height);

        var x: f32 = 0;
        var oldX: i32 = 0;
        var oldY: i32 = 0;
        while (x < 10) : (x += 0.1) {
            const y = self.dataFn(x - 5) + 1;
            const dy = @intCast(i32, height) - @floatToInt(i32, @floor(y * 100));
            const dx = @floatToInt(i32, @floor(x * 100));

            ctx.setColor(0, 0, 0);
            ctx.line(oldX, oldY, dx, dy);
            ctx.stroke();
            oldX = dx; oldY = dy;
        }
    }

    /// Internal function used at initialization.
    /// It is used to move some pointers so things do not break.
    pub fn pointerMoved(self: *LineGraph_Impl) void {
        _ = self;
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
        return zgt.Size { .width = 500.0, .height = 200.0 };
    }
};

pub fn LineGraph(config: struct { dataFn: fn(x: f32) f32 }) !LineGraph_Impl {
    var lineGraph = LineGraph_Impl.init(config.dataFn);
    try lineGraph.addDrawHandler(LineGraph_Impl.draw);
    return lineGraph;
}

const smoothData = true;
const myData = [_]f32 {
    0.0, 1.0, 5.0, 4.0, 3.0, 2.0, 6.0, 0.0
};

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
        const next = if (idx+1 >= myData.len) myData[idx] else myData[idx+1];
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
    const exp = std.math.exp(-(x*x / 2.0));
    return exp / ps;
}

var rand = std.rand.DefaultPrng.init(0);
fn randf(x: f32) f32 {
    _ = x;
    return rand.random.float(f32);
}

pub fn main() !void {
    try zgt.backend.init();

    var window = try zgt.Window.init();
    graph = try LineGraph(.{ .dataFn = myDataFunction });
    try window.set(
        zgt.Column(.{}, .{
            zgt.Expanded(&graph)
        })
    );

    window.resize(800, 600);
    window.show();
    window.run();
}
