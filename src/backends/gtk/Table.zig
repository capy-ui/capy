const std = @import("std");
const c = @import("gtk.zig");
const lib = @import("../../capy.zig");
const common = @import("common.zig");
const ColumnDef = @import("../../components/Table.zig").ColumnDef;

const Table = @This();

peer: *c.GtkWidget, // The GtkScrolledWindow
tree_view: *c.GtkWidget,
list_store: *c.GtkListStore,
cell_provider: ?*const fn (row: usize, col: usize, buf: []u8) []const u8 = null,
row_count: usize = 0,
column_count: usize = 0,

const _events = common.Events(@This());
pub const setupEvents = _events.setupEvents;
pub const copyEventUserData = _events.copyEventUserData;
pub const setUserData = _events.setUserData;
pub const setCallback = _events.setCallback;
pub const setOpacity = _events.setOpacity;
pub const requestDraw = _events.requestDraw;
pub const getX = _events.getX;
pub const getY = _events.getY;
pub const getWidth = _events.getWidth;
pub const getHeight = _events.getHeight;
pub const getPreferredSize = _events.getPreferredSize;
pub const deinit = _events.deinit;

fn gtkSelectionChanged(selection: ?*c.GtkTreeSelection, _: c.gpointer) callconv(.c) void {
    const tv: [*c]c.GtkTreeView = c.gtk_tree_selection_get_tree_view(selection);
    const widget: *c.GtkWidget = @ptrCast(tv);
    const data = common.getEventUserData(widget);

    var model: ?*c.GtkTreeModel = null;
    var iter: c.GtkTreeIter = undefined;
    if (c.gtk_tree_selection_get_selected(selection, &model, &iter) != 0) {
        // Get the path to determine the row index
        const path = c.gtk_tree_model_get_path(model, &iter);
        if (path) |p| {
            defer c.gtk_tree_path_free(p);
            const indices = c.gtk_tree_path_get_indices(p);
            if (indices != null) {
                const idx: usize = @intCast(indices[0]);
                if (data.user.propertyChangeHandler) |handler|
                    handler("selected", @ptrCast(&idx), data.userdata);
            }
        }
    } else {
        // No selection
        const null_val: ?usize = null;
        if (data.user.propertyChangeHandler) |handler|
            handler("selected", @ptrCast(&null_val), data.userdata);
    }
}

fn gtkColumnClicked(column: ?*c.GtkTreeViewColumn, _: c.gpointer) callconv(.c) void {
    // Find the column index by checking the tree view's columns
    const tv_widget = c.gtk_tree_view_column_get_tree_view(column);
    if (tv_widget == null) return;
    const tv: [*c]c.GtkTreeView = @ptrCast(tv_widget);
    const widget: *c.GtkWidget = @ptrCast(tv);
    const data = common.getEventUserData(widget);

    const columns = c.gtk_tree_view_get_columns(tv);
    if (columns == null) return;
    defer c.g_list_free(columns);

    var list = columns;
    var idx: usize = 0;
    while (list != null) : ({
        list = list.*.next;
        idx += 1;
    }) {
        if (list.*.data == @as(c.gpointer, @ptrCast(column))) {
            if (data.user.propertyChangeHandler) |handler|
                handler("sort", @ptrCast(&idx), data.userdata);
            break;
        }
    }
}

pub fn create() common.BackendError!Table {
    // Create the GtkTreeView (starts with no model)
    const tree_view = c.gtk_tree_view_new() orelse return error.UnknownError;
    c.gtk_tree_view_set_headers_visible(@ptrCast(tree_view), 1);

    // Create the GtkScrolledWindow wrapper
    const scroll = c.gtk_scrolled_window_new() orelse return error.UnknownError;
    c.gtk_scrolled_window_set_child(@ptrCast(scroll), tree_view);

    // Create an empty list store (will be configured when setColumns is called)
    var col_types = [1]c.GType{c.G_TYPE_STRING};
    const list_store = c.gtk_list_store_newv(1, &col_types) orelse return error.UnknownError;

    // Set up events on the scroll view (the peer)
    try Table.setupEvents(scroll);

    // Also copy event data to tree_view so we can access it in callbacks
    Table.copyEventUserData(scroll, tree_view);

    // Connect selection changed signal
    const selection = c.gtk_tree_view_get_selection(@ptrCast(tree_view));
    c.gtk_tree_selection_set_mode(selection, c.GTK_SELECTION_SINGLE);
    _ = c.g_signal_connect_data(
        @as(c.gpointer, @ptrCast(selection)),
        "changed",
        @as(c.GCallback, @ptrCast(&gtkSelectionChanged)),
        null,
        null,
        0,
    );

    return Table{
        .peer = scroll,
        .tree_view = tree_view,
        .list_store = list_store,
    };
}

pub fn setColumns(self: *Table, columns: []const ColumnDef) void {
    // Remove existing columns
    while (true) {
        const col = c.gtk_tree_view_get_column(@ptrCast(self.tree_view), 0);
        if (col == null) break;
        _ = c.gtk_tree_view_remove_column(@ptrCast(self.tree_view), col);
    }

    // Create new list store with correct number of string columns
    const n_cols: c_int = @intCast(columns.len);
    const allocator = lib.internal.allocator;
    const col_types = allocator.alloc(c.GType, columns.len) catch return;
    defer allocator.free(col_types);
    for (col_types) |*ct| ct.* = c.G_TYPE_STRING;
    self.list_store = c.gtk_list_store_newv(n_cols, col_types.ptr) orelse return;
    c.gtk_tree_view_set_model(@ptrCast(self.tree_view), @ptrCast(self.list_store));

    // Add columns with cell renderers
    for (columns, 0..) |col_def, i| {
        const renderer = c.gtk_cell_renderer_text_new();
        const col = c.gtk_tree_view_column_new() orelse continue;

        const title = allocator.dupeZ(u8, col_def.header) catch continue;
        defer allocator.free(title);
        c.gtk_tree_view_column_set_title(col, title.ptr);
        c.gtk_tree_view_column_pack_start(col, renderer, 1);
        c.gtk_tree_view_column_add_attribute(col, renderer, "text", @intCast(i));
        c.gtk_tree_view_column_set_sizing(col, c.GTK_TREE_VIEW_COLUMN_FIXED);
        c.gtk_tree_view_column_set_fixed_width(col, @intFromFloat(col_def.width));
        c.gtk_tree_view_column_set_min_width(col, @intFromFloat(col_def.min_width));
        c.gtk_tree_view_column_set_resizable(col, 1);
        c.gtk_tree_view_column_set_clickable(col, 1);

        // Connect column header click signal
        _ = c.g_signal_connect_data(
            @as(c.gpointer, @ptrCast(col)),
            "clicked",
            @as(c.GCallback, @ptrCast(&gtkColumnClicked)),
            null,
            null,
            0,
        );

        _ = c.gtk_tree_view_append_column(@ptrCast(self.tree_view), col);
    }

    self.column_count = columns.len;
}

pub fn setCellProvider(self: *Table, provider: *const fn (row: usize, col: usize, buf: []u8) []const u8) void {
    self.cell_provider = provider;
}

pub fn setRowCount(self: *Table, count: usize) void {
    self.row_count = count;
    self.populateListStore();
}

pub fn setSelectedRow(self: *Table, row: ?usize) void {
    const selection = c.gtk_tree_view_get_selection(@ptrCast(self.tree_view));
    if (row) |r| {
        var iter: c.GtkTreeIter = undefined;
        if (c.gtk_tree_model_iter_nth_child(@ptrCast(self.list_store), &iter, null, @intCast(r)) != 0) {
            c.gtk_tree_selection_select_iter(selection, &iter);
        }
    } else {
        c.gtk_tree_selection_unselect_all(selection);
    }
}

pub fn getSelectedRow(self: *Table) ?usize {
    const selection = c.gtk_tree_view_get_selection(@ptrCast(self.tree_view));
    var model: ?*c.GtkTreeModel = null;
    var iter: c.GtkTreeIter = undefined;
    if (c.gtk_tree_selection_get_selected(selection, &model, &iter) != 0) {
        const path = c.gtk_tree_model_get_path(model, &iter);
        if (path) |p| {
            defer c.gtk_tree_path_free(p);
            const indices = c.gtk_tree_path_get_indices(p);
            if (indices != null) return @intCast(indices[0]);
        }
    }
    return null;
}

pub fn reloadData(self: *Table) void {
    self.populateListStore();
}

fn populateListStore(self: *Table) void {
    c.gtk_list_store_clear(self.list_store);
    const provider = self.cell_provider orelse return;
    if (self.column_count == 0) return;

    var buf: [256]u8 = undefined;
    const allocator = lib.internal.allocator;

    for (0..self.row_count) |row| {
        var iter: c.GtkTreeIter = undefined;
        c.gtk_list_store_append(self.list_store, &iter);

        for (0..self.column_count) |col| {
            const text = provider(row, col, &buf);
            const z_text = allocator.dupeZ(u8, text) catch continue;
            defer allocator.free(z_text);

            // Use g_value_set_string approach for setting cell data
            var value: c.GValue = std.mem.zeroes(c.GValue);
            _ = c.g_value_init(&value, c.G_TYPE_STRING);
            c.g_value_set_string(&value, z_text.ptr);
            c.gtk_list_store_set_value(self.list_store, &iter, @intCast(col), &value);
            c.g_value_unset(&value);
        }
    }
}
