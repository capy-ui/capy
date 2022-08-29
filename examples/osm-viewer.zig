const std = @import("std");
const capy = @import("capy");

pub usingnamespace capy.cross_platform;

pub const MapViewer_Impl = struct {
    pub usingnamespace capy.internal.All(MapViewer_Impl);

    // Required fields for all components.

    // The peer of the component is a widget in the backend we use, corresponding
    // to our component. For example here, using `capy.backend.Canvas` creates
    // a GtkDrawingBox on GTK+, a custom canvas on win32, a <canvas> element on
    // the web, etc.
    peer: ?capy.backend.Canvas = null,
    // .Handlers and .DataWrappers are implemented by `capy.internal.All(MapViewer_Impl)`
    handlers: MapViewer_Impl.Handlers = undefined,
    dataWrappers: MapViewer_Impl.DataWrappers = .{},

    // Our own component state.
    tileCache: std.AutoHashMap(TilePosition, Tile),
    pendingRequests: std.AutoHashMap(TilePosition, capy.http.HttpResponse),
    // TODO: between 0-1 wrapping for easier application of zoom
    // TODO: this should preferably be the map center
    camX: f32 = 0,
    camY: f32 = 0,
    camZoom: u5 = 5,
    isDragging: bool = false,
    lastMouseX: i32 = 0,
    lastMouseY: i32 = 0,

    pub const Config = struct {
        allocator: std.mem.Allocator = capy.internal.lasting_allocator,
    };

    const TilePosition = struct {
        zoom: u5,
        x: i32,
        y: i32,

        fn deg2rad(theta: f32) f32 {
            return theta / 180 * std.math.pi;
        }

        /// 'lon' and 'lat' are in degrees
        pub fn fromLonLat(zoom: u5, lon: f32, lat: f32) TilePosition {
            const n = std.math.pow(f32, 2, @intToFloat(f32, zoom));
            const x = n * ((lon + 180) / 360);
            const lat_rad = deg2rad(lat);
            const y = n * (1 - (std.math.ln(
                std.math.tan(lat_rad) + (1.0 / std.math.cos(lat_rad))
            ) / std.math.pi)) / 2;
            return TilePosition {
                .zoom = zoom,
                .x = @floatToInt(i32, x),
                .y = @floatToInt(i32, y)
            };
        }
    };

    const Tile = struct {
        data: capy.ImageData
    };

    pub fn init(config: Config) MapViewer_Impl {
        return MapViewer_Impl.init_events(MapViewer_Impl{
            .tileCache = std.AutoHashMap(TilePosition, Tile).init(config.allocator),
            .pendingRequests = std.AutoHashMap(TilePosition, capy.http.HttpResponse).init(config.allocator),
        });
    }

    // Implementation Methods
    pub fn getTile(self: *MapViewer_Impl, pos: TilePosition) ?Tile {
        const modTileXY = std.math.powi(i32, 2, pos.zoom) catch unreachable;
        const actual_pos = TilePosition {
            .zoom = pos.zoom,
            .x = @mod(pos.x, modTileXY),
            .y = @mod(pos.y, modTileXY),
        };
        if (self.tileCache.get(actual_pos)) |tile| {
            return tile;
        } else {
            if (self.pendingRequests.get(actual_pos) == null) {
                var buf: [2048]u8 = undefined;
                const url = std.fmt.bufPrint(&buf, "https://tile.openstreetmap.org/{}/{}/{}.png", .{ actual_pos.zoom, actual_pos.x, actual_pos.y }) catch unreachable;
                const request = capy.http.HttpRequest.get(url);
                const response = request.send() catch unreachable;
                self.pendingRequests.put(actual_pos, response ) catch unreachable;
            }
            return null;
        }
    }

    pub fn checkRequests(self: *MapViewer_Impl) !void {
        var iterator = self.pendingRequests.keyIterator();
        while (iterator.next()) |key| {
            const response = self.pendingRequests.getPtr(key.*).?;
            if (response.isReady()) {
                // Read the body of the HTTP response and store it in memory
                var contents = std.ArrayList(u8).init(capy.internal.scratch_allocator);
                defer contents.deinit();

                var buf: [512]u8 = undefined;
                while (true) {
                    const len = try response.read(&buf);
                    if (len == 0) break;
                    try contents.writer().writeAll(buf[0..len]);
                }

                const imageData = try capy.ImageData.fromBuffer(capy.internal.scratch_allocator, contents.toOwnedSlice());
                try self.tileCache.put(key.*, .{ .data = imageData });
                self.pendingRequests.removeByPtr(key);
                self.requestDraw() catch unreachable;
                break;
            }
        }
    }

    // Component Methods (drawing, showing, ...)

    // Here we'll draw ourselves the content of the map
    // It works because in MapViewer() function, we do addDrawHandler(MapViewer.draw)
    pub fn draw(self: *MapViewer_Impl, ctx: *capy.DrawContext) !void {
        const width = self.getWidth();
        const height = self.getHeight();
        ctx.clear(0, 0, width, height);

        const camX = @floatToInt(i32, self.camX);
        const camY = @floatToInt(i32, self.camY);
        var x: i32 = @divFloor(camX, 256);
        while (x < @divFloor(camX + @intCast(i32, width)+255, 256)) : (x += 1) {
            var y: i32 = @divFloor(camY, 256);
            while (y < @divFloor(camY + @intCast(i32, height)+255, 256)) : (y += 1) {
                self.drawTile(ctx, TilePosition { .x = x, .y = y, .zoom = self.camZoom });
            }
        }
    }

    fn drawTile(self: *MapViewer_Impl, ctx: *capy.DrawContext, pos: TilePosition) void {
        const x = -@floatToInt(i32, self.camX) + pos.x * 256;
        const y = -@floatToInt(i32, self.camY) + pos.y * 256;
        if (self.getTile(pos)) |tile| {
            ctx.image(x, y, 256, 256, tile.data);
        } else {
            var layout = capy.DrawContext.TextLayout.init();
            defer layout.deinit();
            var buf: [100]u8 = undefined;
            ctx.text(x, y, layout,
                std.fmt.bufPrint(&buf, "T{d},{d}@{d}", .{ pos.x, pos.y, pos.zoom }) catch unreachable);
        }
    }

    fn mouseButton(self: *MapViewer_Impl, button: capy.MouseButton, pressed: bool, x: i32, y: i32) !void {
        _ = x; _ = y;
        if (button == .Left) {
            self.isDragging = pressed;
            self.lastMouseX = x;
            self.lastMouseY = y;
        }
    }

    fn mouseMoved(self: *MapViewer_Impl, x: i32, y: i32) !void {
        if (self.isDragging) {
            // TODO: smooth move
            self.camX -= @intToFloat(f32, x - self.lastMouseX);
            self.camY -= @intToFloat(f32, y - self.lastMouseY);

            self.lastMouseX = x;
            self.lastMouseY = y;
            self.requestDraw() catch unreachable;
        }
    }

    fn mouseScroll(self: *MapViewer_Impl, dx: f32, dy: f32) !void {
        _ = dx;
        if (dy > 0) {
            self.camZoom -|= @floatToInt(u5, dy);
            self.camX /= 2*dy;
            self.camY /= 2*dy;
        } else {
            self.camZoom +|= @floatToInt(u5, -dy);
            self.camX *= 2*-dy;
            self.camY *= 2*-dy;
        }
        if (self.camZoom > 14) {
            self.camZoom = 14;
        }
        self.requestDraw() catch unreachable;
    }

    // All components have this method, which is automatically called
    // when Capy needs to create the native peers of your widget.
    pub fn show(self: *MapViewer_Impl) !void {
        if (self.peer == null) {
            self.peer = try capy.backend.Canvas.create();
            try self.show_events();
        }
    }

    pub fn getPreferredSize(self: *MapViewer_Impl, available: capy.Size) capy.Size {
        _ = self;
        _ = available;
        return capy.Size{ .width = 500.0, .height = 200.0 };
    }
};

pub fn MapViewer(config: MapViewer_Impl.Config) !MapViewer_Impl {
    var map_viewer = MapViewer_Impl.init(config);
    _ = try map_viewer.addDrawHandler(MapViewer_Impl.draw);
    _ = try map_viewer.addMouseButtonHandler(MapViewer_Impl.mouseButton);
    _ = try map_viewer.addMouseMotionHandler(MapViewer_Impl.mouseMoved);
    _ = try map_viewer.addScrollHandler(MapViewer_Impl.mouseScroll);
    return map_viewer;
}

pub fn main() !void {
    try capy.backend.init();

    var window = try capy.Window.init();
    try window.set(
        capy.Column(.{}, .{
            capy.Row(.{}, .{
                capy.Expanded(capy.TextField(.{})),
                capy.Button(.{ .label = "Go!" }),
            }),
            capy.Expanded(
                (try MapViewer(.{}))
                    .setName("map-viewer")
            ),
        }),
    );
    window.setTitle("OpenStreetMap Viewer");
    window.show();

    while (capy.stepEventLoop(.Asynchronous)) {
        const root = window.getChild().?.as(capy.Container_Impl);
        const viewer = root.getChildAs(MapViewer_Impl, "map-viewer").?;
        try viewer.checkRequests();
    }
}
