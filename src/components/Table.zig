const std = @import("std");
const builtin = @import("builtin");
const backend = @import("../backend.zig");
const internal = @import("../internal.zig");
const Size = @import("../data.zig").Size;
const Atom = @import("../data.zig").Atom;
const Color = @import("../color.zig").Color;
const sys = @import("../system_colors.zig");
const MouseButton = @import("../backends/shared.zig").MouseButton;

/// Definition of a table column.
pub const ColumnDef = struct {
    header: [:0]const u8,
    width: f32 = 100.0,
    min_width: f32 = 40.0,
};

/// Callback type for providing cell data.
pub const CellProvider = *const fn (row: usize, col: usize, buf: []u8) []const u8;

/// Whether a native table backend is available on this platform.
const has_native_table = backend.Table != void;
/// The peer type: native Table when available, Canvas as fallback.
const TablePeer = if (has_native_table) backend.Table else backend.Canvas;

/// A multi-column data table with headers, row selection, sorting indicators,
/// and virtual scrolling. Data is provided via a callback function.
/// Uses native platform table widgets (NSTableView, etc.) when available,
/// falling back to canvas-drawn rendering.
pub const Table = struct {
    const _all = internal.All(@This());
    pub const WidgetData = _all.WidgetData;
    pub const WidgetClass = _all.WidgetClass;
    pub const Atoms = _all.Atoms;
    pub const Config = _all.Config;
    pub const Callback = _all.Callback;
    pub const DrawCallback = _all.DrawCallback;
    pub const ButtonCallback = _all.ButtonCallback;
    pub const MouseMoveCallback = _all.MouseMoveCallback;
    pub const ScrollCallback = _all.ScrollCallback;
    pub const ResizeCallback = _all.ResizeCallback;
    pub const KeyTypeCallback = _all.KeyTypeCallback;
    pub const KeyPressCallback = _all.KeyPressCallback;
    pub const PropertyChangeCallback = _all.PropertyChangeCallback;
    pub const Handlers = _all.Handlers;
    pub const init_events = _all.init_events;
    pub const setupEvents = _all.setupEvents;
    pub const addClickHandler = _all.addClickHandler;
    pub const addDrawHandler = _all.addDrawHandler;
    pub const addMouseButtonHandler = _all.addMouseButtonHandler;
    pub const addMouseMotionHandler = _all.addMouseMotionHandler;
    pub const addScrollHandler = _all.addScrollHandler;
    pub const addResizeHandler = _all.addResizeHandler;
    pub const addKeyTypeHandler = _all.addKeyTypeHandler;
    pub const addKeyPressHandler = _all.addKeyPressHandler;
    pub const addPropertyChangeHandler = _all.addPropertyChangeHandler;
    pub const requestDraw = _all.requestDraw;
    pub const alloc = _all.alloc;
    pub const ref = _all.ref;
    pub const unref = _all.unref;
    pub const showWidget = _all.showWidget;
    pub const isDisplayedFn = _all.isDisplayedFn;
    pub const deinitWidget = _all.deinitWidget;
    pub const getPreferredSizeWidget = _all.getPreferredSizeWidget;
    pub const getX = _all.getX;
    pub const getY = _all.getY;
    pub const getSize = _all.getSize;
    pub const getWidth = _all.getWidth;
    pub const getHeight = _all.getHeight;
    pub const asWidget = _all.asWidget;
    pub const addUserdata = _all.addUserdata;
    pub const withUserdata = _all.withUserdata;
    pub const getUserdata = _all.getUserdata;
    pub const set = _all.set;
    pub const get = _all.get;
    pub const bind = _all.bind;
    pub const withProperty = _all.withProperty;
    pub const withBinding = _all.withBinding;
    pub const getName = _all.getName;
    pub const setName = _all.setName;
    pub const getParent = _all.getParent;
    pub const getRoot = _all.getRoot;
    pub const getAnimationController = _all.getAnimationController;
    pub const clone = _all.clone;
    pub const widget_clone = _all.widget_clone;
    pub const deinit = _all.deinit;

    peer: ?TablePeer = null,
    widget_data: Table.WidgetData = .{},

    /// Number of data rows.
    row_count: Atom(usize) = Atom(usize).of(0),
    /// Currently selected row, or null for no selection.
    selected_row: Atom(?usize) = Atom(?usize).of(null),
    /// Column index used for sort indicator, or null.
    sort_column: Atom(?usize) = Atom(?usize).of(null),
    /// Sort direction.
    sort_ascending: Atom(bool) = Atom(bool).of(true),
    /// Height of each data row in pixels.
    row_height: Atom(f32) = Atom(f32).of(28.0),
    /// Height of the header row in pixels.
    header_height: Atom(f32) = Atom(f32).of(32.0),
    /// Header background color.
    header_color: Atom(Color) = Atom(Color).of(Color.fromRGB(0xF0, 0xF0, 0xF0)),
    /// Color for alternating rows (even rows).
    row_color_even: Atom(Color) = Atom(Color).of(Color.fromRGB(0xFF, 0xFF, 0xFF)),
    /// Color for alternating rows (odd rows).
    row_color_odd: Atom(Color) = Atom(Color).of(Color.fromRGB(0xF8, 0xF8, 0xF8)),
    /// Selected row highlight color.
    selected_color: Atom(Color) = Atom(Color).of(Color.fromRGB(0xCC, 0xDD, 0xEE)),

    _columns: []const ColumnDef = &.{},
    _cell_provider: ?CellProvider = null,
    _scroll_y: f32 = 0.0,
    _hovered_row: ?usize = null,
    _on_sort: ?*const fn (col: usize, ascending: bool) void = null,
    _on_select: ?*const fn (row: ?usize) void = null,

    pub fn init(config: Table.Config) Table {
        var tbl = Table.init_events(Table{});
        if (!has_native_table) {
            // Canvas fallback: set dark-mode-aware colors
            tbl.header_color.set(sys.tableHeader());
            tbl.row_color_even.set(sys.tableRowEven());
            tbl.row_color_odd.set(sys.tableRowOdd());
            tbl.selected_color.set(sys.selectedBackground());
        }
        internal.applyConfigStruct(&tbl, config);
        if (!has_native_table) {
            // Canvas fallback: register draw/event handlers
            tbl.addDrawHandler(&Table.draw) catch unreachable;
            tbl.addMouseButtonHandler(&Table.onMouseButton) catch unreachable;
            tbl.addMouseMotionHandler(&Table.onMouseMove) catch unreachable;
            tbl.addScrollHandler(&Table.onScroll) catch unreachable;
            tbl.addKeyPressHandler(&Table.onKeyPress) catch unreachable;
        }
        return tbl;
    }

    pub fn setColumns(self: *Table, columns: []const ColumnDef) *Table {
        self._columns = columns;
        return self;
    }

    pub fn setCellProvider(self: *Table, provider: CellProvider) *Table {
        self._cell_provider = provider;
        return self;
    }

    pub fn onSort(self: *Table, callback: *const fn (col: usize, ascending: bool) void) *Table {
        self._on_sort = callback;
        return self;
    }

    pub fn onSelect(self: *Table, callback: *const fn (row: ?usize) void) *Table {
        self._on_select = callback;
        return self;
    }

    pub fn getPreferredSize(self: *Table, available: Size) Size {
        var total_w: f32 = 0;
        for (self._columns) |col| total_w += col.width;
        const w: f32 = @min(available.width, @max(total_w, 100.0));
        return available.intersect(Size.init(w, 300));
    }

    fn getMaxScrollY(self: *Table) f32 {
        const rh = self.row_height.get();
        const hh = self.header_height.get();
        const total_content = @as(f32, @floatFromInt(self.row_count.get())) * rh;
        const viewport = @as(f32, @floatFromInt(self.getHeight())) - hh;
        return @max(0.0, total_content - viewport);
    }

    fn onScroll(self: *Table, _: f32, dy: f32) !void {
        self._scroll_y = std.math.clamp(self._scroll_y + dy * 20.0, 0.0, self.getMaxScrollY());
        self.peer.?.requestDraw() catch {};
    }

    fn onKeyPress(self: *Table, keycode: u16) !void {
        const row_count = self.row_count.get();
        if (row_count == 0) return;

        const current = self.selected_row.get();
        const new_sel: ?usize = switch (keycode) {
            0xF701 => blk: { // Down arrow
                if (current) |c| {
                    break :blk if (c + 1 < row_count) c + 1 else c;
                } else break :blk 0;
            },
            0xF700 => blk: { // Up arrow
                if (current) |c| {
                    break :blk if (c > 0) c - 1 else 0;
                } else break :blk 0;
            },
            else => return,
        };

        if (new_sel != current) {
            self.selected_row.set(new_sel);
            if (self._on_select) |cb| cb(new_sel);
            // Scroll to keep selection visible
            if (new_sel) |sel| {
                const rh = self.row_height.get();
                const hh = self.header_height.get();
                const sel_top = @as(f32, @floatFromInt(sel)) * rh;
                const sel_bot = sel_top + rh;
                const viewport_h = @as(f32, @floatFromInt(self.getHeight())) - hh;

                if (sel_top < self._scroll_y) {
                    self._scroll_y = sel_top;
                } else if (sel_bot > self._scroll_y + viewport_h) {
                    self._scroll_y = sel_bot - viewport_h;
                }
            }
            self.peer.?.requestDraw() catch {};
        }
    }

    fn onMouseButton(self: *Table, button: MouseButton, pressed: bool, x: i32, y: i32) !void {
        if (button != .Left or !pressed) return;

        const hh: i32 = @intFromFloat(self.header_height.get());

        if (y < hh) {
            // Click in header: toggle sort
            var col_x: f32 = 0;
            for (self._columns, 0..) |col, i| {
                if (@as(f32, @floatFromInt(x)) >= col_x and @as(f32, @floatFromInt(x)) < col_x + col.width) {
                    const was_this = self.sort_column.get() != null and self.sort_column.get().? == i;
                    if (was_this) {
                        self.sort_ascending.set(!self.sort_ascending.get());
                    } else {
                        self.sort_column.set(i);
                        self.sort_ascending.set(true);
                    }
                    if (self._on_sort) |cb| cb(i, self.sort_ascending.get());
                    self.peer.?.requestDraw() catch {};
                    return;
                }
                col_x += col.width;
            }
        } else {
            // Click in data area: select row
            const rh = self.row_height.get();
            const data_y = @as(f32, @floatFromInt(y - hh)) + self._scroll_y;
            const row_idx: usize = @intFromFloat(data_y / rh);
            if (row_idx < self.row_count.get()) {
                self.selected_row.set(row_idx);
                if (self._on_select) |cb| cb(row_idx);
                self.peer.?.requestDraw() catch {};
            }
        }
    }

    fn onMouseMove(self: *Table, _: i32, y: i32) !void {
        const hh: i32 = @intFromFloat(self.header_height.get());
        var new_hovered: ?usize = null;

        if (y >= hh) {
            const rh = self.row_height.get();
            const data_y = @as(f32, @floatFromInt(y - hh)) + self._scroll_y;
            const row_idx: usize = @intFromFloat(data_y / rh);
            if (row_idx < self.row_count.get()) {
                new_hovered = row_idx;
            }
        }

        if (new_hovered != self._hovered_row) {
            self._hovered_row = new_hovered;
            self.peer.?.requestDraw() catch {};
        }
    }

    pub fn draw(self: *Table, ctx: *backend.DrawContext) !void {
        const w = self.getWidth();
        const h = self.getHeight();
        const hh_f = self.header_height.get();
        const hh: u31 = @intFromFloat(hh_f);
        const rh = self.row_height.get();
        const rh_i: u31 = @intFromFloat(rh);

        var header_layout = backend.DrawContext.TextLayout.init();
        header_layout.setFont(.{ .face = "Helvetica-Bold", .size = 13.0 });
        var cell_layout = backend.DrawContext.TextLayout.init();
        cell_layout.setFont(.{ .face = "Helvetica", .size = 13.0 });

        // Fill entire widget background first (for areas below data rows)
        ctx.setColorByte(sys.background());
        ctx.rectangle(0, 0, w, h);
        ctx.fill();

        // Draw header background
        ctx.setColorByte(self.header_color.get());
        ctx.rectangle(0, 0, w, hh);
        ctx.fill();

        // Draw header text and separators
        var col_x: f32 = 0;
        for (self._columns, 0..) |col, i| {
            const cx: i32 = @intFromFloat(col_x);

            // Header text
            ctx.setColorByte(sys.label());
            const text_size = header_layout.getTextSize(col.header);
            ctx.text(cx + 8, @as(i32, @intCast(hh / 2)) - @as(i32, @intCast(text_size.height / 2)), header_layout, col.header);

            // Sort indicator
            if (self.sort_column.get()) |sc| {
                if (sc == i) {
                    const arrow_x = cx + @as(i32, @intCast(text_size.width)) + 14;
                    const arrow_y: i32 = @intCast(hh / 2);
                    if (self.sort_ascending.get()) {
                        // Up triangle
                        ctx.line(arrow_x - 4, arrow_y + 3, arrow_x, arrow_y - 3);
                        ctx.line(arrow_x, arrow_y - 3, arrow_x + 4, arrow_y + 3);
                    } else {
                        // Down triangle
                        ctx.line(arrow_x - 4, arrow_y - 3, arrow_x, arrow_y + 3);
                        ctx.line(arrow_x, arrow_y + 3, arrow_x + 4, arrow_y - 3);
                    }
                }
            }

            // Column separator
            if (i > 0) {
                ctx.setColorByte(sys.separator());
                ctx.rectangle(cx, 0, 1, hh);
                ctx.fill();
            }

            col_x += col.width;
        }

        // Draw header bottom border
        ctx.setColorByte(sys.separator());
        ctx.rectangle(0, @as(i32, @intCast(hh)) - 1, w, 1);
        ctx.fill();

        // Draw data rows (virtual scrolling)
        const viewport_h: f32 = @as(f32, @floatFromInt(h)) - hh_f;
        const first_visible_row: usize = @intFromFloat(self._scroll_y / rh);
        const visible_rows: usize = @intFromFloat(viewport_h / rh + 2.0);
        const total_rows = self.row_count.get();

        var cell_buf: [256]u8 = undefined;

        var row: usize = first_visible_row;
        while (row < @min(first_visible_row + visible_rows, total_rows)) : (row += 1) {
            const row_y_f = @as(f32, @floatFromInt(row)) * rh - self._scroll_y + hh_f;
            const row_y: i32 = @intFromFloat(row_y_f);

            // Skip rows above viewport
            if (row_y + @as(i32, rh_i) < @as(i32, @intCast(hh))) continue;
            // Skip rows below viewport
            if (row_y >= @as(i32, @intCast(h))) break;

            // Row background
            const is_selected = self.selected_row.get() != null and self.selected_row.get().? == row;
            const is_hovered = self._hovered_row != null and self._hovered_row.? == row;

            const row_bg = if (is_selected)
                self.selected_color.get()
            else if (is_hovered)
                sys.tableRowHovered()
            else if (row % 2 == 0)
                self.row_color_even.get()
            else
                self.row_color_odd.get();

            ctx.setColorByte(row_bg);
            ctx.rectangle(0, row_y, w, rh_i);
            ctx.fill();

            // Cell text
            if (self._cell_provider) |provider| {
                col_x = 0;
                for (self._columns, 0..) |col, ci| {
                    const cx: i32 = @intFromFloat(col_x);
                    const cell_text = provider(row, ci, &cell_buf);

                    ctx.setColorByte(sys.label());
                    const text_size = cell_layout.getTextSize(cell_text);
                    ctx.text(cx + 8, row_y + @as(i32, rh_i / 2) - @as(i32, @intCast(text_size.height / 2)), cell_layout, cell_text);

                    // Column separator in data area
                    if (ci > 0) {
                        ctx.setColorByte(sys.separator());
                        ctx.rectangle(cx, row_y, 1, rh_i);
                        ctx.fill();
                    }

                    col_x += col.width;
                }
            }
        }

        // Draw scrollbar if needed
        if (total_rows > 0) {
            const total_content = @as(f32, @floatFromInt(total_rows)) * rh;
            if (total_content > viewport_h) {
                const scrollbar_w: u31 = 8;
                const scrollbar_x: i32 = @as(i32, @intCast(w)) - scrollbar_w - 2;
                const thumb_ratio = viewport_h / total_content;
                const thumb_h: u31 = @max(20, @as(u31, @intFromFloat(viewport_h * thumb_ratio)));
                const thumb_y_offset = (viewport_h - @as(f32, @floatFromInt(thumb_h))) * (self._scroll_y / self.getMaxScrollY());
                const thumb_y: i32 = @as(i32, @intCast(hh)) + @as(i32, @intFromFloat(thumb_y_offset));

                ctx.setColorByte(sys.shadow());
                if (builtin.os.tag == .windows) {
                    ctx.rectangle(scrollbar_x, thumb_y, scrollbar_w, thumb_h);
                } else {
                    ctx.roundedRectangleEx(scrollbar_x, thumb_y, scrollbar_w, thumb_h, [4]f32{ 4, 4, 4, 4 });
                }
                ctx.fill();
            }
        }
    }

    pub fn show(self: *Table) !void {
        if (self.peer == null) {
            if (comptime has_native_table) {
                // Native table backend
                var peer = try backend.Table.create();
                peer.setColumns(self._columns);
                if (self._cell_provider) |provider| {
                    peer.setCellProvider(provider);
                }
                peer.setRowCount(self.row_count.get());
                if (self.selected_row.get()) |row| {
                    peer.setSelectedRow(row);
                }
                self.peer = peer;
                // Sync row_count changes to native widget
                _ = try self.row_count.addChangeListener(.{ .function = struct {
                    fn callback(new_count: usize, userdata: ?*anyopaque) void {
                        const ptr: *Table = @ptrCast(@alignCast(userdata.?));
                        if (ptr.peer) |*p| p.setRowCount(new_count);
                    }
                }.callback, .userdata = self });
                // Sync selected_row changes to native widget
                _ = try self.selected_row.addChangeListener(.{ .function = struct {
                    fn callback(new_sel: ?usize, userdata: ?*anyopaque) void {
                        const ptr: *Table = @ptrCast(@alignCast(userdata.?));
                        if (ptr.peer) |*p| p.setSelectedRow(new_sel);
                    }
                }.callback, .userdata = self });
            } else {
                // Canvas fallback
                self.peer = try backend.Canvas.create();
                _ = try self.row_count.addChangeListener(.{ .function = struct {
                    fn callback(_: usize, userdata: ?*anyopaque) void {
                        const ptr: *Table = @ptrCast(@alignCast(userdata.?));
                        ptr.peer.?.requestDraw() catch {};
                    }
                }.callback, .userdata = self });
                _ = try self.selected_row.addChangeListener(.{ .function = struct {
                    fn callback(_: ?usize, userdata: ?*anyopaque) void {
                        const ptr: *Table = @ptrCast(@alignCast(userdata.?));
                        ptr.peer.?.requestDraw() catch {};
                    }
                }.callback, .userdata = self });
            }
            try self.setupEvents();
        }
    }
};

pub fn table(config: Table.Config) *Table {
    return Table.alloc(config);
}

test "Table default properties" {
    try backend.init();
    var tbl = table(.{ .row_count = 5 });
    defer tbl.deinit();

    try std.testing.expectEqual(@as(usize, 5), tbl.row_count.get());
    try std.testing.expectEqual(@as(?usize, null), tbl.selected_row.get());
    try std.testing.expectEqual(@as(?usize, null), tbl.sort_column.get());
    try std.testing.expect(tbl.sort_ascending.get());
    try std.testing.expectApproxEqAbs(@as(f32, 28.0), tbl.row_height.get(), 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 32.0), tbl.header_height.get(), 0.001);
    try std.testing.expectEqual(@as(?CellProvider, null), tbl._cell_provider);
}

test "Table setColumns" {
    try backend.init();
    var tbl = table(.{ .row_count = 3 });
    defer tbl.deinit();

    _ = tbl.setColumns(&.{
        .{ .header = "Name", .width = 100 },
        .{ .header = "Age", .width = 60 },
    });
    try std.testing.expectEqual(@as(usize, 2), tbl._columns.len);
    try std.testing.expectEqualStrings("Name", tbl._columns[0].header);
    try std.testing.expectEqual(@as(f32, 100.0), tbl._columns[0].width);
    try std.testing.expectEqualStrings("Age", tbl._columns[1].header);
}

test "Table setCellProvider" {
    try backend.init();

    const provider = struct {
        fn cell(_: usize, _: usize, buf: []u8) []const u8 {
            const text = "test";
            @memcpy(buf[0..text.len], text);
            return buf[0..text.len];
        }
    }.cell;

    var tbl = table(.{ .row_count = 1 });
    defer tbl.deinit();
    _ = tbl.setCellProvider(&provider);

    try std.testing.expect(tbl._cell_provider != null);
    // Verify the provider works
    var buf: [64]u8 = undefined;
    const result = tbl._cell_provider.?(0, 0, &buf);
    try std.testing.expectEqualStrings("test", result);
}

test Table {
    var tbl = table(.{ .row_count = 10 });
    tbl.ref();
    defer tbl.unref();
    try std.testing.expectEqual(@as(usize, 10), tbl.row_count.get());
    try std.testing.expectEqual(@as(?usize, null), tbl.selected_row.get());
}
