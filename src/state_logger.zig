const std = @import("std");
const internal = @import("internal.zig");

const OutputTarget = enum { disabled, stdout, stderr, file };

var target: OutputTarget = .disabled;
var file_handle: ?std.fs.File = null;
var mutex: std.Thread.Mutex = .{};

pub fn init() void {
    const env_val = std.process.getEnvVarOwned(internal.allocator, "CAPY_UI_STATE_CHANGES_TO") catch return;
    defer internal.allocator.free(env_val);

    if (std.mem.eql(u8, env_val, "@stdout")) {
        target = .stdout;
    } else if (std.mem.eql(u8, env_val, "@stderr")) {
        target = .stderr;
    } else {
        file_handle = std.fs.cwd().createFile(env_val, .{}) catch |err| {
            std.debug.print("CAPY_UI_STATE_CHANGES_TO: failed to open '{s}': {s}\n", .{ env_val, @errorName(err) });
            return;
        };
        target = .file;
    }
}

pub fn deinit() void {
    if (file_handle) |fh| fh.close();
    file_handle = null;
    target = .disabled;
}

pub fn isEnabled() bool {
    return target != .disabled;
}

pub fn logPropertyChange(
    widget_type: []const u8,
    widget_name: ?[]const u8,
    widget_addr: usize,
    property: []const u8,
    new_value_str: []const u8,
) void {
    if (target == .disabled) return;
    mutex.lock();
    defer mutex.unlock();

    const file = getFile() orelse return;

    // Build widget identifier: "Type#name" or "Type#0xaddr"
    var addr_buf: [18]u8 = undefined;
    const widget_id = if (widget_name) |n| n else std.fmt.bufPrint(&addr_buf, "0x{x}", .{widget_addr}) catch "?";

    // Format entire line into buffer, then write atomically
    var buf: [1024]u8 = undefined;
    const line = std.fmt.bufPrint(&buf, "{{\"widget\":\"{s}#{s}\",\"property\":\"{s}\",\"value\":{s}}}\n", .{
        shortTypeName(widget_type),
        widget_id,
        property,
        new_value_str,
    }) catch return;

    file.writeAll(line) catch {};
}

fn getFile() ?std.fs.File {
    return switch (target) {
        .disabled => null,
        .stdout => std.fs.File.stdout(),
        .stderr => std.fs.File.stderr(),
        .file => file_handle,
    };
}

/// Extract short name from full Zig type path.
/// e.g. "components.Slider.Slider" -> "Slider", "internal.All(...).T" -> "T"
fn shortTypeName(full: []const u8) []const u8 {
    // Find last '.' and return everything after it
    var i = full.len;
    while (i > 0) {
        i -= 1;
        if (full[i] == '.') {
            return full[i + 1 ..];
        }
    }
    return full;
}
