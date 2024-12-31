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

var totalEnergy = capy.Atom(f32).of(0);

const BALL_DIAMETER = 20;
const BALL_RADIUS = BALL_DIAMETER / 2;

var gpa = std.heap.GeneralPurposeAllocator(.{}){};
pub const capy_allocator = gpa.allocator();

pub fn main() !void {
    defer _ = gpa.deinit();
    try capy.init();
    defer capy.deinit();

    defer totalEnergy.deinit();
    balls = std.ArrayList(Ball).init(capy.internal.lasting_allocator);
    defer balls.deinit();

    // Generate random balls
    var prng = std.Random.DefaultPrng.init(@as(u64, @bitCast(std.time.milliTimestamp())));
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

    // the canvas isn't referenced (canvas.ref()) so it will get deinitialized whenever the window
    // is deinitialized
    var canvas = capy.canvas(.{
        .preferredSize = capy.Size.init(500, 500),
        .ondraw = @as(*const fn (*anyopaque, *capy.DrawContext) anyerror!void, @ptrCast(&onDraw)),
        .name = "ball-canvas",
    });
    try canvas.addMouseButtonHandler(&onMouseButton);
    try canvas.addMouseMotionHandler(&onMouseMotion);

    var totalEnergyFormat = try capy.FormattedAtom(capy.internal.lasting_allocator, "Total Kinetic Energy: {d:.2}", .{&totalEnergy});
    defer totalEnergyFormat.deinit();

    var window = try capy.Window.init();
    defer window.deinit();
    try window.set(capy.column(.{}, .{
        capy.label(.{ .text = "Balls with attraction and friction" }),
        capy.label(.{})
            .bind("text", totalEnergyFormat),
        capy.alignment(.{}, canvas),
    }));

    window.setTitle("Balls");
    window.setPreferredSize(600, 600);
    window.show();

    var simThread = try std.Thread.spawn(.{}, simulationThread, .{&window});
    defer simThread.join();

    capy.runEventLoop();
}

fn onMouseButton(widget: *capy.Canvas, button: capy.MouseButton, pressed: bool, x: i32, y: i32) !void {
    mouseX = x;
    mouseY = y;
    if (button == .Left) {
        if (pressed) {
            selected_ball_index = null;
            for (balls.items, 0..) |*ball, i| {
                const dx = ball.x - @as(f32, @floatFromInt(x));
                const dy = ball.y - @as(f32, @floatFromInt(y));
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

fn onMouseMotion(widget: *capy.Canvas, x: i32, y: i32) !void {
    if (selected_ball_index != null) {
        mouseX = x;
        mouseY = y;
        try widget.requestDraw();
    }
}

fn onDraw(widget: *capy.Canvas, ctx: *capy.DrawContext) !void {
    const width = widget.getWidth();
    const height = widget.getHeight();

    ctx.setColor(1, 1, 1);
    ctx.rectangle(0, 0, width, height);
    ctx.fill();

    for (balls.items, 0..) |ball, i| {
        const is_selected = if (selected_ball_index) |target| (i == target) else false;
        if (is_selected) {
            ctx.setColor(1, 0, 0);
        } else {
            ctx.setColor(0, 0, 0);
        }
        ctx.ellipse(@as(i32, @intFromFloat(ball.x)), @as(i32, @intFromFloat(ball.y)), BALL_DIAMETER, BALL_DIAMETER);
        ctx.fill();
    }

    if (selected_ball_index) |index| {
        const ball = balls.items[index];
        ctx.setColor(0, 0, 0);
        ctx.line(@as(i32, @intFromFloat(ball.x + BALL_RADIUS)), @as(i32, @intFromFloat(ball.y + BALL_RADIUS)), mouseX, mouseY);
        ctx.stroke();
    }
}

fn simulationThread(window: *capy.Window) !void {
    const root = window.getChild().?.as(capy.Container);
    const canvas = root.getChild("ball-canvas").?.as(capy.Canvas);

    while (window.visible.get()) {
        const delta = 1.0 / 60.0;
        for (balls.items, 0..) |*ball, i| {
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
                    if (distance < BALL_DIAMETER) {
                        // Collision!
                        if (std.math.sign(ball.velX) == std.math.sign(dx) or std.math.sign(ball.velY) == std.math.sign(dy)) {
                            // We only take it if they're approaching each other to avoid two balls
                            // getting stuck forever
                            const oldVelX = ball.velX;
                            const oldVelY = ball.velY;
                            ball.velX = otherBall.velX;
                            ball.velY = otherBall.velY;

                            otherBall.velX = oldVelX;
                            otherBall.velY = oldVelY;

                            const offshoot = (BALL_DIAMETER - distance) / 2;
                            ball.x -= (dx / distance) * offshoot / 2;
                            ball.y -= (dy / distance) * offshoot / 2;
                            otherBall.x += (dy / distance) * offshoot / 2;
                            otherBall.y += (dy / distance) * offshoot / 2;
                        }
                    }

                    // Attraction
                    const dr2 = BALL_RADIUS / distance;
                    const dr6 = dr2 * dr2 * dr2;
                    const dr12 = dr6 * dr6;
                    //const attractionForce = 10 / (distance * distance);
                    const attractionForce = 10 * 1 * -(dr12 - dr6);
                    if (distance > BALL_DIAMETER) {
                        ball.velX += (dx / distance) * attractionForce;
                        ball.velY += (dy / distance) * attractionForce;
                    }
                }
            }

            // Moving applied by user
            const is_selected = if (selected_ball_index) |idx| (i == idx) else false;
            if (is_selected) {
                const dx = @as(f32, @floatFromInt(mouseX)) - ball.x;
                const dy = @as(f32, @floatFromInt(mouseY)) - ball.y;
                ball.velX += dx / 10;
                ball.velY += dy / 10;
            }

            // Friction
            const friction = 0.01;
            ball.velX *= 1 - friction;
            ball.velY *= 1 - friction;

            ball.velX = @min(1000, ball.velX);
            ball.velY = @min(1000, ball.velY);
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
