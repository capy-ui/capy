const std = @import("std");
const capy = @import("capy");
pub usingnamespace capy.cross_platform;

var selectedIndex: capy.Atom(usize) = capy.Atom(usize).of(0);

pub fn main() !void {
    try capy.backend.init();

    var window = try capy.Window.init();
    try window.set(capy.Column(.{}, .{
        capy.Button(.{ .label = "one-way flight", .onclick = oneWay }),
        capy.Button(.{ .label = "return flight", .onclick = returnFlight }),
        capy.TextField(.{ .name = "start-date", .text = "27.03.2014" }),
        capy.TextField(.{ .name = "return-date", .text = "27.03.2014" }),
        capy.Button(.{ .name = "book-button", .label = "Book", .onclick = bookFlight }),
    }));

    window.setTitle("Book Flight");
    window.show();

    const root = window.getChild().?.as(capy.Container_Impl);
    const start_field = root.getChildAs(capy.TextField_Impl, "start-date").?;
    const return_field = root.getChildAs(capy.TextField_Impl, "return-date").?;
    const book_button = root.getChildAs(capy.Button_Impl, "book-button").?;

    try return_field.readOnly.dependOn(.{&selectedIndex}, &(struct {
        fn a(index: usize) bool {
            return index != 1; // only enabled for return flight
        }
    }.a));

    // Quite literally, the 'enabled' property of button depends on start field's text and return field's text
    try book_button.enabled.dependOn(.{ &start_field.text, &return_field.text }, &(struct {
        fn a(start_text: []const u8, return_text: []const u8) bool {
            const start_date = parseDate(start_text) catch return false;
            const return_date = parseDate(return_text) catch return false;

            // return date must be after departure date
            return return_date > start_date;
        }
    }.a));

    capy.runEventLoop();
}

// TODO: switch back to *capy.Button_Impl when ziglang/zig#12325 is fixed
fn oneWay(_: *anyopaque) !void {
    selectedIndex.set(0);
}

// TODO: switch back to *capy.Button_Impl when ziglang/zig#12325 is fixed
fn returnFlight(_: *anyopaque) !void {
    selectedIndex.set(1);
}

// TODO: switch back to *capy.Button_Impl when ziglang/zig#12325 is fixed
fn bookFlight(button_: *anyopaque) !void {
    const button = @ptrCast(*capy.Button_Impl, @alignCast(@alignOf(capy.Button_Impl), button_));

    const root = button.getRoot().?.as(capy.Container_Impl);
    _ = root;
}

/// Inaccurate sample date parsing routine.
pub fn parseDate(date: []const u8) !u64 {
    var split = std.mem.split(u8, date, ".");
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
