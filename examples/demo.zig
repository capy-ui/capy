const capy = @import("capy");
const std = @import("std");
pub usingnamespace capy.cross_platform;

var gpa: std.heap.GeneralPurposeAllocator(.{}) = undefined;
pub const capy_allocator = gpa.allocator();

var corner_1 = capy.Atom(f32).of(5);
var corner_2 = capy.Atom(f32).of(5);
var corner_3 = capy.Atom(f32).of(5);
var corner_4 = capy.Atom(f32).of(5);

pub fn main() !void {
    gpa = .{};
    defer _ = gpa.deinit();

    try capy.init();
    defer capy.deinit();

    var window = try capy.Window.init();
    defer window.deinit();

    var somesliderValue = capy.Atom(f32).of(0);
    var somesliderText = try capy.FormattedAtom(capy.internal.lasting_allocator, "{d:.1}", .{&somesliderValue});

    try window.set(capy.row(.{ .spacing = 0 }, .{
        capy.navigationSidebar(.{}),
        capy.tabs(.{
            capy.tab(.{ .label = "Border Layout" }, BorderLayoutExample()),
            capy.tab(.{ .label = "Buttons" }, capy.column(.{}, .{
                // alignX = 0 means buttons should be aligned to the left
                // TODO: use constraint layout (when it's added) to make all buttons same width
                capy.alignment(.{ .x = 0 }, capy.button(.{ .label = "Button", .onclick = moveButton })),
                capy.button(.{ .label = "Button (disabled)", .enabled = false }),
                capy.checkBox(.{ .label = "Checked", .checked = true }), // TODO: dynamic label based on checked
                capy.checkBox(.{ .label = "Disabled", .enabled = false }),
                capy.row(.{}, .{
                    capy.expanded(capy.slider(.{ .min = -10, .max = 10, .step = 0.1 })
                        .bind("value", &somesliderValue)),
                    capy.label(.{})
                        .bind("text", somesliderText),
                }),
            })),
            capy.tab(.{ .label = "Rounded Rectangle" }, capy.column(.{}, .{
                capy.alignment(
                    .{},
                    capy.canvas(.{ .preferredSize = capy.Size.init(100, 100), .ondraw = drawRounded }),
                ),
                capy.row(.{}, .{
                    capy.expanded(capy.slider(.{ .min = 0, .max = 100, .step = 0.1 })
                        .bind("value", &corner_1)),
                    capy.expanded(capy.slider(.{ .min = 0, .max = 100, .step = 0.1 })
                        .bind("value", &corner_2)),
                }),
                capy.row(.{}, .{
                    capy.expanded(capy.slider(.{ .min = 0, .max = 100, .step = 0.1 })
                        .bind("value", &corner_3)),
                    capy.expanded(capy.slider(.{ .min = 0, .max = 100, .step = 0.1 })
                        .bind("value", &corner_4)),
                }),
            })),
            //capy.tab(.{ .label = "Drawing" }, capy.expanded(drawer(.{}))),
        }),
    }));

    window.show();
    capy.runEventLoop();
    std.log.info("Goodbye!", .{});
}

fn drawRounded(cnv: *anyopaque, ctx: *capy.DrawContext) !void {
    const canvas = @as(*capy.Canvas, @ptrCast(@alignCast(cnv)));

    ctx.setColor(0.7, 0.9, 0.3);
    ctx.setLinearGradient(.{ .x0 = 80, .y0 = 0, .x1 = 100, .y1 = 100, .stops = &.{
        .{ .offset = 0.1, .color = capy.Color.yellow },
        .{ .offset = 0.8, .color = capy.Color.red },
    } });
    ctx.roundedRectangleEx(
        0,
        0,
        canvas.getWidth(),
        canvas.getHeight(),
        .{ corner_1.get(), corner_2.get(), corner_3.get(), corner_4.get() },
    );
    ctx.fill();
}

pub const Drawer = struct {
    pub usingnamespace capy.internal.All(Drawer);

    peer: ?capy.backend.Canvas = null,
    handlers: Drawer.Handlers = undefined,
    dataWrappers: Drawer.Atoms = .{},
    image: capy.ImageData,

    pub fn init() !Drawer {
        return Drawer.init_events(Drawer{
            .image = try capy.ImageData.new(1, 1, .RGB), // start with a 1x1 image
        });
    }

    pub fn onDraw(self: *Drawer, ctx: *capy.DrawContext) !void {
        const width = self.getWidth();
        const height = self.getHeight();
        ctx.image(0, 0, width, height, self.image);
    }

    pub fn onResize(self: *Drawer, size: capy.Size) !void {
        if (size.width > self.image.width or size.height > self.image.height) {
            self.image.deinit(); // delete old image
            self.image = try capy.ImageData.new(size.width, size.height, .RGB);
            @import("std").log.info("new image of size {}", .{size});
        }
    }

    pub fn show(self: *Drawer) !void {
        if (self.peer == null) {
            self.peer = try capy.backend.canvas.create();
            try self.show_events();
        }
    }

    pub fn getPreferredSize(self: *Drawer, _: capy.Size) capy.Size {
        return .{ .width = self.image.width, .height = self.image.height };
    }
};

pub fn drawer(config: Drawer.Config) !Drawer {
    _ = config;
    var lineGraph = try Drawer.init();
    try lineGraph.addDrawHandler(&Drawer.onDraw);
    try lineGraph.addResizeHandler(&Drawer.onResize);
    return lineGraph;
}

// You can simulate a border layout using only column, row and expanded
fn BorderLayoutExample() anyerror!capy.Container {
    return capy.column(.{}, .{
        capy.label(.{ .text = "Top", .alignment = .Center }),
        capy.expanded(
            capy.row(.{}, .{
                capy.label(.{ .text = "Left", .alignment = .Center }),
                capy.expanded(
                    capy.label(.{ .text = "Center", .alignment = .Center }),
                ),
                capy.label(.{ .text = "Right", .alignment = .Center }),
            }),
        ),
        capy.label(.{ .text = "Bottom", .alignment = .Center }),
    });
}

fn moveButton(button_: *anyopaque) !void {
    const button = @as(*capy.Button, @ptrCast(@alignCast(button_)));
    const parent = button.getParent().?.as(capy.Alignment);

    const alignX = &parent.x;
    // Ensure the current animation is done before starting another
    if (!alignX.hasAnimation()) {
        if (alignX.get() == 0) { // if on the left
            alignX.animate(capy.Easings.InOut, 1, 1000);
        } else {
            alignX.animate(capy.Easings.InOut, 0, 1000);
        }
    }
}
