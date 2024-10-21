const std = @import("std");
const capy = @import("capy");
pub usingnamespace capy.cross_platform;

var selected_index: capy.Atom(usize) = capy.Atom(usize).of(0);

pub fn main() !void {
    try capy.backend.init();

    var window = try capy.Window.init();
    try window.set(capy.column(.{}, .{
        capy.button(.{ .label = "one-way flight", .onclick = oneWay }),
        capy.button(.{ .label = "return flight", .onclick = returnFlight }),
        capy.textField(.{ .name = "start-date", .text = "27.03.2014" }),
        capy.textField(.{ .name = "return-date", .text = "27.03.2014" }),
        capy.button(.{ .name = "book-button", .label = "Book", .onclick = bookFlight }),
    }));

    window.setTitle("Book Flight");
    window.show();

    const root = window.getChild().?.as(capy.Container);
    const start_field = root.getChildAs(capy.TextField, "start-date").?;
    const return_field = root.getChildAs(capy.TextField, "return-date").?;
    const book_button = root.getChildAs(capy.Button, "book-button").?;

    try return_field.readOnly.dependOn(.{&selected_index}, &(struct {
        fn a(index: usize) bool {
            return index != 1; // only enabled for return flight
        }
    }.a));

    // Quite literally, the 'enabled' property of button depends on start field's text and return field's text
    try book_button.enabled.dependOn(.{ &start_field.text, &return_field.text, &selected_index }, &(struct {
        fn a(start_text: []const u8, return_text: []const u8, index: usize) bool {
            const start_date = parseDate(start_text) catch return false;
            const return_date = parseDate(return_text) catch return false;

            // return date must be after departure date
            return return_date > start_date or index == 0;
        }
    }.a));

    capy.runEventLoop();
}

// TODO: switch back to *capy.Button when ziglang/zig#12325 is fixed
fn oneWay(_: *anyopaque) !void {
    selected_index.set(0);
}

// TODO: switch back to *capy.Button when ziglang/zig#12325 is fixed
fn returnFlight(_: *anyopaque) !void {
    selected_index.set(1);
}

// TODO: switch back to *capy.Button when ziglang/zig#12325 is fixed
fn bookFlight(button_: *anyopaque) !void {
    const button = @as(*capy.Button, @ptrCast(@alignCast(button_)));

    const root = button.getRoot().?.as(capy.Container);
    _ = root;
}

/// Inaccurate sample date parsing routine.
pub fn parseDate(date: []const u8) !u64 {
    var split = std.mem.splitScalar(u8, date, '.');
    const day = split.next() orelse return error.MissingDay;
    const month = split.next() orelse return error.MissingMonth;
    const year = split.next() orelse return error.MissingYear;
    if (split.rest().len != 0) {
        return error.InvalidFormat;
    }

    const dayInt = try std.fmt.parseInt(u64, day, 10);
    const monthInt = try std.fmt.parseInt(u64, month, 10);
    const yearInt = try std.fmt.parseInt(u64, year, 10);

    // this is a date format that only works for comparison
    return yearInt * 10000 + monthInt * 100 + dayInt;
}
