const std = @import("std");
const capy = @import("capy");
pub usingnamespace capy.cross_platform;

const Ball = struct {
    x: f32,
    y: f32,
    velX: f32 = 0,
    velY: f32 = 0,
};

var balls: std.ArrayList(Ball) = undefined;
var selected_ball_index: ?usize = null;
var mouseX: i32 = 0;
var mouseY: i32 = 0;

var totalEnergy = capy.DataWrapper(f32).of(0);

const BALL_DIAMETER = 10;
const BALL_RADIUS = BALL_DIAMETER / 2;

//var gpa = std.heap.GeneralPurposeAllocator(.{}) {};
//pub const capy_allocator = gpa.allocator();

pub fn main() !void {
    try capy.backend.init();
    balls = std.ArrayList(Ball).init(capy.internal.lasting_allocator);

    // Generate random balls
    var prng = std.rand.DefaultPrng.init(@bitCast(u64, std.time.milliTimestamp()));
    const random = prng.random();
    var i: usize = 0;
    while (i < 100) : (i += 1) {
        try balls.append(Ball{
            .x = random.float(f32) * 500,
            .y = random.float(f32) * 500,
            .velX = random.float(f32) * 100,
            .velY = random.float(f32) * 100,
        });
    }

    var canvas = capy.Canvas(.{
        .preferredSize = capy.Size.init(500, 500),
        .ondraw = @ptrCast(*const fn(*anyopaque, *capy.DrawContext) anyerror!void, &onDraw),
        .name = "ball-canvas",
    });
    try canvas.addMouseButtonHandler(&onMouseButton);
    try canvas.addMouseMotionHandler(&onMouseMotion);

    var totalEnergyFormat = try capy.FormatDataWrapper(capy.internal.lasting_allocator, "Total Kinetic Energy: {d:.2}", .{&totalEnergy});
    defer totalEnergyFormat.deinit();

    var window = try capy.Window.init();
    try window.set(capy.Column(.{}, .{
        capy.Label(.{ .text = "Balls with attraction and friction" }),
        capy.Label(.{ })
                .bind("text", totalEnergyFormat),
		capy.Align(.{}, &canvas),
    }));

    window.setTitle("Balls");
    window.resize(600, 600);
    window.show();

    var simThread = try std.Thread.spawn(.{}, simulationThread, .{ &window });
    defer simThread.join();

    capy.runEventLoop();
}

fn onMouseButton(widget: *capy.Canvas_Impl, button: capy.MouseButton, pressed: bool, x: i32, y: i32) !void {
    mouseX = x;
    mouseY = y;
    if (button == .Left) {
        if (pressed) {
            selected_ball_index = null;
            for (balls.items) |*ball, i| {
                const dx = ball.x - @intToFloat(f32, x);
                const dy = ball.y - @intToFloat(f32, y);
                const distance = std.math.sqrt((dx * dx) + (dy * dy));
                if (distance < BALL_RADIUS * 2) { // give some room
                    selected_ball_index = i;
                    break;
                }
            }
        } else {
            selected_ball_index = null;
        }
        try widget.requestDraw();
    }
}

fn onMouseMotion(widget: *capy.Canvas_Impl, x: i32, y: i32) !void {
    if (selected_ball_index != null) {
        mouseX = x;
        mouseY = y;
        try widget.requestDraw();
    }
}

fn onDraw(widget: *capy.Canvas_Impl, ctx: *capy.DrawContext) !void {
    const width = widget.getWidth();
    const height = widget.getHeight();

    ctx.setColor(1, 1, 1);
    ctx.rectangle(0, 0, width, height);
    ctx.fill();

    for (balls.items) |ball, i| {
        const is_selected = if (selected_ball_index) |target| (i == target) else false;
        if (is_selected) {
            ctx.setColor(1, 0, 0);
        } else {
            ctx.setColor(0, 0, 0);
        }
        ctx.ellipse(@floatToInt(i32, ball.x), @floatToInt(i32, ball.y), 10, 10);
        ctx.fill();
    }

    if (selected_ball_index) |index| {
        const ball = balls.items[index];
        ctx.setColor(0, 0, 0);
        ctx.line(@floatToInt(i32, ball.x), @floatToInt(i32, ball.y), mouseX, mouseY);
        ctx.stroke();
    }
}

fn simulationThread(window: *capy.Window) !void {
    const root = window.getChild().?.as(capy.Container_Impl);
    const canvas = root.getChild("ball-canvas").?.as(capy.Canvas_Impl);

    while (true) {
        const delta = 1.0 / 60.0;
        for (balls.items) |*ball, i| {
            // Moving
            ball.x += ball.velX * delta;
            ball.y += ball.velY * delta;

            // Wall collision check
            if (ball.x > 500 - BALL_DIAMETER) {
                ball.x = 500 - BALL_DIAMETER;
                if (ball.velX > 0) ball.velX = -ball.velX;
            }
            if (ball.x < 0) {
                ball.x = 0;
                if (ball.velX < 0) ball.velX = -ball.velX;
            }
            if (ball.y > 500 - BALL_DIAMETER) {
                ball.y = 500 - BALL_DIAMETER;
                if (ball.velY > 0) ball.velY = -ball.velY;
            }
            if (ball.y < 0) {
                ball.y = 0;
                if (ball.velY < 0) ball.velY = -ball.velY;
            }

            // Ball collision check
            for (balls.items) |*otherBall| {
                if (otherBall != ball) {
                    const dx = otherBall.x - ball.x;
                    const dy = otherBall.y - ball.y;
                    const distance = std.math.sqrt((dx * dx) + (dy * dy));
                    if (distance < BALL_RADIUS) {
                        // Collision!
                        if (std.math.sign(ball.velX) == @as(f32, if(dx > 0) 1 else -1) or std.math.sign(ball.velY) == @as(f32, if(dy > 0) 1 else -1)) {
                            // We only take it if they're approaching each other to avoid two balls
                            // getting stuck forever
                            const oldVelX = ball.velX;
                            const oldVelY = ball.velY;
                            ball.velX = otherBall.velX;
                            ball.velY = otherBall.velY;

                            otherBall.velX = oldVelX;
                            otherBall.velY = oldVelY;
                        }
                    }

                    // Attraction
                    //const dr2 = distance / BALL_RADIUS;
                    //const dr6 = dr2 * dr2 * dr2;
                    //const dr12 = dr6 * dr6;
                    const attractionForce = 1000 / (distance * distance);

                    ball.velX += (dx/distance) * attractionForce;
                    ball.velY += (dy/distance) * attractionForce;
                }
            }

            // Moving applied by user
            const is_selected = if (selected_ball_index) |idx| (i == idx) else false;
            if (is_selected) {
                const dx = @intToFloat(f32, mouseX) - ball.x;
                const dy = @intToFloat(f32, mouseY) - ball.y;
                ball.velX += dx / 10;
                ball.velY += dy / 10;
            }

            // Friction
            const friction = 0.001;
            ball.velX *= 1 - friction;
            ball.velY *= 1 - friction;
        }

        var total: f32 = 0; // count total energy
        for (balls.items) |ball| {
            total += std.math.sqrt((ball.velX * ball.velX) + (ball.velY * ball.velY));
        }
        totalEnergy.set(total);

        try canvas.requestDraw();
        std.time.sleep(16 * std.time.ns_per_ms);
    }
}
