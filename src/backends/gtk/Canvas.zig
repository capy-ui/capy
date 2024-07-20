const std = @import("std");
const c = @import("gtk.zig");
const lib = @import("../../main.zig");
const common = @import("common.zig");

const Canvas = @This();
const Window = @import("Window.zig");

/// Actual GtkCanvas
peer: *c.GtkWidget,

pub usingnamespace common.Events(Canvas);

// TODO: use f32 for coordinates?
// avoid the burden of converting between signed and unsigned integers?

pub const DrawContext = struct {
    cr: *c.cairo_t,
    widget: ?*c.GtkWidget = null,

    pub const Font = struct {
        face: [:0]const u8,
        size: f64,
    };

    pub const TextSize = struct { width: u32, height: u32 };

    pub const TextLayout = struct {
        _layout: *c.PangoLayout,
        _context: *c.PangoContext,
        /// If null, no text wrapping is applied, otherwise the text is wrapping as if this was the maximum width.
        wrap: ?f64 = null,

        pub fn setFont(self: *TextLayout, font: Font) void {
            const fontDescription = c.pango_font_description_from_string(font.face.ptr) orelse unreachable;
            c.pango_font_description_set_size(fontDescription, @as(c_int, @intFromFloat(@floor(font.size * @as(f64, c.PANGO_SCALE)))));
            c.pango_layout_set_font_description(self._layout, fontDescription);
            c.pango_font_description_free(fontDescription);
        }

        pub fn deinit(self: *TextLayout) void {
            c.g_object_unref(self._layout);
            c.g_object_unref(self._context);
        }

        pub fn getTextSize(self: *TextLayout, str: []const u8) TextSize {
            var width: c_int = undefined;
            var height: c_int = undefined;
            c.pango_layout_set_width(self._layout, if (self.wrap) |w| @as(c_int, @intFromFloat(@floor(w * @as(f64, c.PANGO_SCALE)))) else -1);
            c.pango_layout_set_text(self._layout, str.ptr, @as(c_int, @intCast(str.len)));
            c.pango_layout_get_pixel_size(self._layout, &width, &height);

            return TextSize{ .width = @as(u32, @intCast(width)), .height = @as(u32, @intCast(height)) };
        }

        pub fn init() TextLayout {
            const context = c.gtk_widget_create_pango_context(Window.randomWindow).?;
            return TextLayout{ ._context = context, ._layout = c.pango_layout_new(context).? };
        }
    };

    pub fn setColorByte(self: *DrawContext, color: lib.Color) void {
        self.setColorRGBA(@as(f32, @floatFromInt(color.red)) / 255.0, @as(f32, @floatFromInt(color.green)) / 255.0, @as(f32, @floatFromInt(color.blue)) / 255.0, @as(f32, @floatFromInt(color.alpha)) / 255.0);
    }

    /// Colors components are from 0 to 1.
    pub fn setColor(self: *DrawContext, r: f32, g: f32, b: f32) void {
        self.setColorRGBA(r, g, b, 1);
    }

    pub fn setColorRGBA(self: *DrawContext, r: f32, g: f32, b: f32, a: f32) void {
        const color = c.GdkRGBA{ .red = r, .green = g, .blue = b, .alpha = a };
        c.gdk_cairo_set_source_rgba(self.cr, &color);
    }

    pub const LinearGradient = struct {
        x0: f32,
        y0: f32,
        x1: f32,
        y1: f32,
        stops: []const Stop,

        pub const Stop = struct {
            offset: f32,
            color: lib.Color,
        };
    };

    pub fn setLinearGradient(self: *DrawContext, gradient: LinearGradient) void {
        const pattern = c.cairo_pattern_create_linear(gradient.x0, gradient.y0, gradient.x1, gradient.y1).?;
        for (gradient.stops) |stop| {
            c.cairo_pattern_add_color_stop_rgba(
                pattern,
                stop.offset,
                @as(f32, @floatFromInt(stop.color.red)) / 255.0,
                @as(f32, @floatFromInt(stop.color.green)) / 255.0,
                @as(f32, @floatFromInt(stop.color.blue)) / 255.0,
                @as(f32, @floatFromInt(stop.color.alpha)) / 255.0,
            );
        }
        c.cairo_set_source(self.cr, pattern);
    }

    /// Add a rectangle to the current path
    pub fn rectangle(self: *DrawContext, x: i32, y: i32, w: u32, h: u32) void {
        c.cairo_rectangle(self.cr, @as(f64, @floatFromInt(x)), @as(f64, @floatFromInt(y)), @as(f64, @floatFromInt(w)), @as(f64, @floatFromInt(h)));
    }

    pub fn roundedRectangle(self: *DrawContext, x: i32, y: i32, w: u32, h: u32, corner_radius: f32) void {
        self.roundedRectangleEx(x, y, w, h, .{corner_radius} ** 4);
    }

    /// The radiuses are in order: top left, top right, bottom left, bottom right
    pub fn roundedRectangleEx(self: *DrawContext, x: i32, y: i32, w: u32, h: u32, corner_radiuses: [4]f32) void {
        var corners: [4]f32 = corner_radiuses;
        if (corners[0] + corners[1] > @as(f32, @floatFromInt(w))) {
            const left_prop = corners[0] / (corners[0] + corners[1]);
            corners[0] = left_prop * @as(f32, @floatFromInt(w));
            corners[1] = (1 - left_prop) * @as(f32, @floatFromInt(w));
        }
        if (corners[2] + corners[3] > @as(f32, @floatFromInt(w))) {
            const left_prop = corners[2] / (corners[2] + corners[3]);
            corners[2] = left_prop * @as(f32, @floatFromInt(w));
            corners[3] = (1 - left_prop) * @as(f32, @floatFromInt(w));
        }
        if (corners[0] + corners[2] > @as(f32, @floatFromInt(h))) {
            const top_prop = corners[0] / (corners[0] + corners[2]);
            corners[0] = top_prop * @as(f32, @floatFromInt(h));
            corners[2] = (1 - top_prop) * @as(f32, @floatFromInt(h));
        }
        if (corners[1] + corners[3] > @as(f32, @floatFromInt(h))) {
            const top_prop = corners[1] / (corners[1] + corners[3]);
            corners[1] = top_prop * @as(f32, @floatFromInt(h));
            corners[3] = (1 - top_prop) * @as(f32, @floatFromInt(h));
        }

        c.cairo_new_sub_path(self.cr);
        c.cairo_arc(
            self.cr,
            @as(f64, @floatFromInt(x + @as(i32, @intCast(w)))) - corners[1],
            @as(f64, @floatFromInt(y)) + corners[1],
            corners[1],
            -std.math.pi / 2.0,
            0.0,
        );
        c.cairo_arc(
            self.cr,
            @as(f64, @floatFromInt(x + @as(i32, @intCast(w)))) - corners[3],
            @as(f64, @floatFromInt(y + @as(i32, @intCast(h)))) - corners[3],
            corners[3],
            0.0,
            std.math.pi / 2.0,
        );
        c.cairo_arc(
            self.cr,
            @as(f64, @floatFromInt(x)) + corners[2],
            @as(f64, @floatFromInt(y + @as(i32, @intCast(h)))) - corners[2],
            corners[2],
            std.math.pi / 2.0,
            std.math.pi,
        );
        c.cairo_arc(
            self.cr,
            @as(f64, @floatFromInt(x)) + corners[0],
            @as(f64, @floatFromInt(y)) + corners[0],
            corners[0],
            std.math.pi,
            std.math.pi / 2.0 * 3.0,
        );
        c.cairo_close_path(self.cr);
    }

    pub fn ellipse(self: *DrawContext, x: i32, y: i32, w: u32, h: u32) void {
        if (w == h) { // if it is a circle, we can use something slightly faster
            c.cairo_arc(self.cr, @as(f64, @floatFromInt(x + @as(i32, @intCast(w / 2)))), @as(f64, @floatFromInt(y + @as(i32, @intCast(w / 2)))), @as(f64, @floatFromInt(w / 2)), 0, 2 * std.math.pi);
            return;
        }
        var matrix: c.cairo_matrix_t = undefined;
        c.cairo_get_matrix(self.cr, &matrix);
        const scale = @as(f32, @floatFromInt(@max(w, h))) / 2;
        c.cairo_scale(self.cr, @as(f32, @floatFromInt(w / 2)) / scale, @as(f32, @floatFromInt(h / 2)) / scale);
        c.cairo_arc(self.cr, @as(f32, @floatFromInt(w / 2)), @as(f32, @floatFromInt(h / 2)), scale, 0, 2 * std.math.pi);
        c.cairo_set_matrix(self.cr, &matrix);
    }

    pub fn clear(self: *DrawContext, x: u32, y: u32, w: u32, h: u32) void {
        if (self.widget) |widget| {
            const styleContext = c.gtk_widget_get_style_context(widget);
            c.gtk_render_background(styleContext, self.cr, @as(f64, @floatFromInt(x)), @as(f64, @floatFromInt(y)), @as(f64, @floatFromInt(w)), @as(f64, @floatFromInt(h)));
        }
    }

    pub fn text(self: *DrawContext, x: i32, y: i32, layout: TextLayout, str: []const u8) void {
        const pangoLayout = layout._layout;
        var inkRect: c.PangoRectangle = undefined;
        c.pango_layout_get_pixel_extents(pangoLayout, null, &inkRect);

        const dx = @as(f64, @floatFromInt(inkRect.x));
        const dy = @as(f64, @floatFromInt(inkRect.y));
        c.cairo_move_to(self.cr, @as(f64, @floatFromInt(x)) + dx, @as(f64, @floatFromInt(y)) + dy);
        c.pango_layout_set_width(pangoLayout, if (layout.wrap) |w| @as(c_int, @intFromFloat(@floor(w * @as(f64, c.PANGO_SCALE)))) else -1);
        c.pango_layout_set_text(pangoLayout, str.ptr, @as(c_int, @intCast(str.len)));
        c.pango_layout_set_single_paragraph_mode(pangoLayout, 1); // used for coherence with other backends
        c.pango_cairo_update_layout(self.cr, pangoLayout);
        c.pango_cairo_show_layout(self.cr, pangoLayout);
    }

    pub fn line(self: *DrawContext, x1: i32, y1: i32, x2: i32, y2: i32) void {
        c.cairo_move_to(self.cr, @as(f64, @floatFromInt(x1)), @as(f64, @floatFromInt(y1)));
        c.cairo_line_to(self.cr, @as(f64, @floatFromInt(x2)), @as(f64, @floatFromInt(y2)));
        c.cairo_stroke(self.cr);
    }

    pub fn image(self: *DrawContext, x: i32, y: i32, w: u32, h: u32, data: lib.ImageData) void {
        c.cairo_save(self.cr);
        defer c.cairo_restore(self.cr);

        const width = @as(f64, @floatFromInt(data.width));
        const height = @as(f64, @floatFromInt(data.height));
        c.cairo_scale(self.cr, @as(f64, @floatFromInt(w)) / width, @as(f64, @floatFromInt(h)) / height);
        c.gdk_cairo_set_source_pixbuf(
            self.cr,
            data.peer.peer,
            @as(f64, @floatFromInt(x)) / (@as(f64, @floatFromInt(w)) / width),
            @as(f64, @floatFromInt(y)) / (@as(f64, @floatFromInt(h)) / height),
        );
        c.cairo_paint(self.cr);
    }

    pub fn setStrokeWidth(self: *DrawContext, width: f32) void {
        c.cairo_set_line_width(self.cr, width);
    }

    /// Stroke the current path and reset the path.
    pub fn stroke(self: *DrawContext) void {
        c.cairo_stroke(self.cr);
    }

    /// Fill the current path and reset the path.
    pub fn fill(self: *DrawContext) void {
        c.cairo_fill(self.cr);
    }
};

fn gtkCanvasDraw(peer: ?*c.GtkDrawingArea, cr: ?*c.cairo_t, _: c_int, _: c_int, _: ?*anyopaque) callconv(.C) void {
    const data = common.getEventUserData(@ptrCast(peer.?));
    var dc = DrawContext{ .cr = cr.?, .widget = @ptrCast(peer.?) };

    if (data.class.drawHandler) |handler|
        handler(&dc, @intFromPtr(data));
    if (data.user.drawHandler) |handler|
        handler(&dc, data.userdata);
}

pub fn create() common.BackendError!Canvas {
    const peer = c.gtk_drawing_area_new() orelse return common.BackendError.UnknownError;
    c.gtk_widget_set_can_focus(peer, 1);
    c.gtk_drawing_area_set_draw_func(@ptrCast(peer), &gtkCanvasDraw, null, null);

    try Canvas.setupEvents(peer);
    common.getEventUserData(peer).focusOnClick = true;

    return Canvas{ .peer = peer };
}
