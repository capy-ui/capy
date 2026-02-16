const std = @import("std");
const capy = @import("capy");

// ── Slide data ──────────────────────────────────────────────────────────────

const Slide = struct {
    title: [:0]const u8,
    subtitle: [:0]const u8,
    bg: [3]f32, // r, g, b  (0-1)
    show_logo: bool = false,
};

const slides = [_]Slide{
    .{ .title = "Welcome to Capy", .subtitle = "A cross-platform GUI library for Zig", .bg = .{ 0.17, 0.17, 0.17 }, .show_logo = true },
    .{ .title = "Declarative UI", .subtitle = "Build interfaces with simple, composable widgets", .bg = .{ 0.10, 0.21, 0.36 } },
    .{ .title = "Native Controls", .subtitle = "Uses each platform's own toolkit", .bg = .{ 0.18, 0.20, 0.25 } },
    .{ .title = "Cross-Platform", .subtitle = "Windows  \xc2\xb7  macOS  \xc2\xb7  Linux  \xc2\xb7  Android  \xc2\xb7  Web", .bg = .{ 0.12, 0.15, 0.22 } },
    .{ .title = "Get Started", .subtitle = "github.com/capy-ui/capy", .bg = .{ 0.17, 0.42, 0.69 } },
};

// ── Global state ────────────────────────────────────────────────────────────

var slide_index: usize = 0;
var window: capy.Window = undefined;

var title_layout: capy.DrawContext.TextLayout = undefined;
var subtitle_layout: capy.DrawContext.TextLayout = undefined;
var logo_data: ?capy.ImageData = null;

var slide_canvas: *capy.Canvas = undefined;
var counter_label: *capy.Label = undefined;
var prev_btn: *capy.Button = undefined;
var next_btn: *capy.Button = undefined;

// ── Helpers ─────────────────────────────────────────────────────────────────

var counter_buf: [32]u8 = undefined;

fn counterText() [:0]const u8 {
    const text = std.fmt.bufPrintZ(&counter_buf, "{d} / {d}", .{ slide_index + 1, slides.len }) catch "?/?";
    return text;
}

fn refreshUI() void {
    slide_canvas.requestDraw() catch {};
    counter_label.text.set(counterText());
    prev_btn.enabled.set(slide_index > 0);
    next_btn.enabled.set(slide_index < slides.len - 1);
}

// ── Callbacks ───────────────────────────────────────────────────────────────

fn prevSlide(_: *anyopaque) !void {
    if (slide_index > 0) {
        slide_index -= 1;
        refreshUI();
    }
}

fn nextSlide(_: *anyopaque) !void {
    if (slide_index < slides.len - 1) {
        slide_index += 1;
        refreshUI();
    }
}

fn toggleFullscreen(_: *anyopaque) !void {
    window.setFullscreen(.{ .borderless = null });
}

// ── Canvas draw handler ─────────────────────────────────────────────────────

fn drawSlide(_: *anyopaque, ctx: *capy.DrawContext) !void {
    const w = slide_canvas.getWidth();
    const h = slide_canvas.getHeight();
    if (w == 0 or h == 0) return;
    const slide = slides[slide_index];

    // Background
    ctx.setColor(slide.bg[0], slide.bg[1], slide.bg[2]);
    ctx.rectangle(0, 0, w, h);
    ctx.fill();

    // Logo image (centered in upper portion)
    if (slide.show_logo) {
        if (logo_data) |img| {
            const max_h = h / 3;
            const max_w = w * 2 / 3;
            const ratio = @as(f32, @floatFromInt(img.width)) / @as(f32, @floatFromInt(img.height));
            var iw: u32 = undefined;
            var ih: u32 = undefined;
            if (@as(f32, @floatFromInt(max_w)) / ratio < @as(f32, @floatFromInt(max_h))) {
                iw = max_w;
                ih = @intFromFloat(@as(f32, @floatFromInt(iw)) / ratio);
            } else {
                ih = max_h;
                iw = @intFromFloat(@as(f32, @floatFromInt(ih)) * ratio);
            }
            const ix = @as(i32, @intCast(w / 2)) - @as(i32, @intCast(iw / 2));
            const iy = @as(i32, @intCast(h / 4)) - @as(i32, @intCast(ih / 2));
            ctx.image(ix, iy, iw, ih, img);
        }
    }

    // Title (centered)
    const ts = title_layout.getTextSize(slide.title);
    const tx = @as(i32, @intCast(w / 2)) - @as(i32, @intCast(ts.width / 2));
    const ty: i32 = if (slide.show_logo)
        @as(i32, @intCast(h / 2 + h / 8))
    else
        @as(i32, @intCast(h / 2 - ts.height));

    ctx.setColor(1.0, 1.0, 1.0);
    ctx.text(tx, ty, title_layout, slide.title);

    // Subtitle (centered, below title)
    const ss = subtitle_layout.getTextSize(slide.subtitle);
    const sx = @as(i32, @intCast(w / 2)) - @as(i32, @intCast(ss.width / 2));
    const sy = ty + @as(i32, @intCast(ts.height)) + 16;
    ctx.setColor(0.75, 0.75, 0.80);
    ctx.text(sx, sy, subtitle_layout, slide.subtitle);

    // Navigation dots
    const dot_r: u32 = 8;
    const dot_gap: u32 = 20;
    const total = @as(u32, @intCast(slides.len)) * dot_gap;
    const ox = w / 2 - total / 2;
    const oy = h - 50;
    for (0..slides.len) |i| {
        const dx: u32 = ox + @as(u32, @intCast(i)) * dot_gap;
        if (i == slide_index) {
            ctx.setColor(1.0, 1.0, 1.0);
        } else {
            ctx.setColor(0.5, 0.5, 0.55);
        }
        ctx.ellipse(@intCast(dx), @intCast(oy), dot_r, dot_r);
        ctx.fill();
    }
}

// ── Main ────────────────────────────────────────────────────────────────────

pub fn main() !void {
    try capy.init();

    // Load logo
    logo_data = capy.ImageData.fromFile(capy.internal.allocator, "assets/ziglogo.png") catch |err| blk: {
        std.log.warn("Could not load ziglogo.png: {s}", .{@errorName(err)});
        break :blk null;
    };

    // Text layouts
    title_layout = capy.DrawContext.TextLayout.init();
    title_layout.setFont(.{ .face = "Helvetica", .size = 48.0 });
    subtitle_layout = capy.DrawContext.TextLayout.init();
    subtitle_layout.setFont(.{ .face = "Helvetica", .size = 24.0 });

    // Widgets
    slide_canvas = capy.canvas(.{});
    slide_canvas.addDrawHandler(&drawSlide) catch {};

    prev_btn = capy.button(.{ .label = "\xe2\x97\x80 Prev", .onclick = prevSlide, .enabled = false });
    next_btn = capy.button(.{ .label = "Next \xe2\x96\xb6", .onclick = nextSlide });
    counter_label = capy.label(.{ .text = counterText() });

    window = try capy.Window.init();
    try window.set(
        capy.column(.{}, .{
            capy.expanded(slide_canvas),
            capy.row(.{ .spacing = 8 }, .{
                prev_btn,
                capy.expanded(capy.alignment(.{}, counter_label)),
                next_btn,
                capy.button(.{ .label = "Fullscreen", .onclick = toggleFullscreen }),
            }),
        }),
    );

    window.setTitle("Slide Viewer");
    window.setPreferredSize(800, 600);
    window.show();
    capy.runEventLoop();
}
