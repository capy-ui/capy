const std = @import("std");
const c = @import("gtk.zig");
const lib = @import("../../main.zig");
const common = @import("common.zig");
const DrawContext = @import("Canvas.zig").DrawContext;

const ImageData = @This();

peer: *c.GdkPixbuf,
mutex: std.Thread.Mutex = .{},
width: usize,
height: usize,

pub const DrawLock = struct {
    _surface: *c.cairo_surface_t,
    draw_context: DrawContext,
    data: *ImageData,

    pub fn end(self: DrawLock) void {
        const width = @as(c_int, @intCast(self.data.width));
        const height = @as(c_int, @intCast(self.data.height));

        c.g_object_unref(@as(*c.GObject, @ptrCast(@alignCast(self.data.peer))));
        self.data.peer = c.gdk_pixbuf_get_from_surface(self._surface, 0, 0, width, height).?;
        c.cairo_destroy(self.draw_context.cr);
        c.cairo_surface_destroy(self._surface);
        self.data.mutex.unlock();
    }
};

// TODO: copy bytes to a new array
pub fn from(width: usize, height: usize, stride: usize, cs: lib.Colorspace, bytes: []const u8) !ImageData {
    const pixbuf = c.gdk_pixbuf_new_from_data(
        bytes.ptr,
        c.GDK_COLORSPACE_RGB,
        @intFromBool(cs == .RGBA),
        8,
        @as(c_int, @intCast(width)),
        @as(c_int, @intCast(height)),
        @as(c_int, @intCast(stride)),
        null,
        null,
    ) orelse return common.BackendError.UnknownError;

    return ImageData{
        .peer = pixbuf,
        .width = width,
        .height = height,
    };
}

pub fn draw(self: *ImageData) DrawLock {
    self.mutex.lock();
    // TODO: just create one surface and use it forever
    const stride = @divFloor(
        @as(c_int, @intCast(c.gdk_pixbuf_get_byte_length(self.peer))),
        c.gdk_pixbuf_get_height(self.peer),
    );
    const surface: *c.cairo_surface_t = c.cairo_image_surface_create_for_data(
        c.gdk_pixbuf_get_pixels(self.peer),
        c.CAIRO_FORMAT_RGB24,
        c.gdk_pixbuf_get_width(self.peer),
        c.gdk_pixbuf_get_height(self.peer),
        stride,
    ) orelse @panic("could not create draw surface");
    // c.gdk_cairo_surface_paint_pixbuf(surface, self.peer);
    // const surface = c.gdk_cairo_surface_create_from_pixbuf(self.peer, 1, null).?;
    const cr = c.cairo_create(surface).?;
    return DrawLock{
        ._surface = surface,
        .draw_context = .{ .cr = cr },
        .data = self,
    };
}

pub fn deinit(self: *ImageData) void {
    self.mutex.lock();
    defer self.mutex.unlock();

    c.g_object_unref(@as(*c.GObject, @ptrCast(@alignCast(self.peer))));
}
