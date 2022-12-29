const capy = @import("capy");
const std = @import("std");
pub usingnamespace capy.cross_platform;

var gpa: std.heap.GeneralPurposeAllocator(.{}) = undefined;
pub const capy_allocator = gpa.allocator();

pub fn main() !void {
    try capy.backend.init();
    gpa = .{};
    defer _ = gpa.deinit();

    var window = try capy.Window.init();
    defer window.deinit();

    try window.set(capy.Tabs(.{
        capy.Tab(.{ .label = "Border Layout" }, BorderLayoutExample()),
        capy.Tab(.{ .label = "Buttons" }, capy.Column(.{}, .{
            // alignX = 0 means buttons should be aligned to the left
            // TODO: use constraint layout (when it's added) to make all buttons same width
            capy.Button(.{ .label = "Button", .alignX = 0, .onclick = moveButton }),
            capy.Button(.{ .label = "Button (disabled)", .enabled = false }),
            capy.CheckBox(.{ .label = "Checked", .checked = true }), // TODO: dynamic label based on checked
            capy.CheckBox(.{ .label = "Disabled", .enabled = false }),
        })),
        //capy.Tab(.{ .label = "Drawing" }, capy.Expanded(Drawer(.{}))),
    }));

    window.show();
    capy.runEventLoop();
    std.log.info("Goodbye!", .{});
}

pub const Drawer_Impl = struct {
    pub usingnamespace capy.internal.All(Drawer_Impl);

    peer: ?capy.backend.Canvas = null,
    handlers: Drawer_Impl.Handlers = undefined,
    dataWrappers: Drawer_Impl.DataWrappers = .{},
    image: capy.ImageData,

    pub fn init() !Drawer_Impl {
        return Drawer_Impl.init_events(Drawer_Impl{
            .image = try capy.ImageData.new(1, 1, .RGB), // start with a 1x1 image
        });
    }

    pub fn onDraw(self: *Drawer_Impl, ctx: *capy.DrawContext) !void {
        const width = self.getWidth();
        const height = self.getHeight();
        ctx.image(0, 0, width, height, self.image);
    }

    pub fn onResize(self: *Drawer_Impl, size: capy.Size) !void {
        if (size.width > self.image.width or size.height > self.image.height) {
            self.image.deinit(); // delete old image
            self.image = try capy.ImageData.new(size.width, size.height, .RGB);
            @import("std").log.info("new image of size {}", .{size});
        }
    }

    pub fn show(self: *Drawer_Impl) !void {
        if (self.peer == null) {
            self.peer = try capy.backend.Canvas.create();
            try self.show_events();
        }
    }

    pub fn getPreferredSize(self: *Drawer_Impl, _: capy.Size) capy.Size {
        return .{ .width = self.image.width, .height = self.image.height };
    }
};

pub fn Drawer(config: Drawer_Impl.Config) !Drawer_Impl {
    _ = config;
    var lineGraph = try Drawer_Impl.init();
    try lineGraph.addDrawHandler(&Drawer_Impl.onDraw);
    try lineGraph.addResizeHandler(&Drawer_Impl.onResize);
    return lineGraph;
}

// You can simulate a border layout using only Column, Row and Expanded
fn BorderLayoutExample() anyerror!capy.Container_Impl {
    return capy.Column(.{}, .{
        capy.Label(.{ .text = "Top" }),
        capy.Expanded(
            capy.Row(.{}, .{
                capy.Label(.{ .text = "Left" }),
                capy.Expanded(
                    capy.Label(.{ .text = "Center" }),
                ),
                capy.Label(.{ .text = "Right" }),
            }),
        ),
        capy.Label(.{ .text = "Bottom " }),
    });
}

fn moveButton(button_: *anyopaque) !void {
    const button = @ptrCast(*capy.Button_Impl, @alignCast(@alignOf(capy.Button_Impl), button_));
    const alignX = &button.dataWrappers.alignX;

    // Ensure the current animation is done before starting another
    if (!alignX.hasAnimation()) {
        if (alignX.get().? == 0) { // if on the left
            alignX.animate(capy.Easings.InOut, 1, 1000);
        } else {
            alignX.animate(capy.Easings.InOut, 0, 1000);
        }
    }
}
