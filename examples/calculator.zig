const std = @import("std");
const capy = @import("capy");
pub usingnamespace capy.cross_platform;

// Short names to avoid writing 'capy.' each time
const Allocator = std.mem.Allocator;

var computationLabel: *capy.Label = undefined;
var allocator: Allocator = undefined;

// TODO: switch back to *capy.button_Impl when ziglang/zig#12325 is fixed
pub fn pressedKey(button_: *anyopaque) !void {
    const button = @as(*capy.Button, @ptrCast(@alignCast(button_)));

    const buttonLabel = button.getLabel();
    const labelText = computationLabel.getText();

    // Concat the computation label with the first character of the button's label
    var larger = try allocator.alloc(u8, labelText.len + 1); // allocate a string one character longer than labelText
    @memcpy(larger[0..labelText.len], labelText); // copy labelText's contents to the newly allocated string
    larger[labelText.len] = buttonLabel[0]; // finally, set the last letter

    computationLabel.setText(larger); // and now we can put that as our new computation label text
    allocator.free(labelText);
}

// TODO: switch back to *capy.button_Impl when ziglang/zig#12325 is fixed
pub fn erase(_: *anyopaque) !void {
    allocator.free(computationLabel.getText());
    computationLabel.setText("");
}

fn findOperator(computation: []const u8, pos: usize) ?usize {
    return std.mem.indexOfScalarPos(u8, computation, pos, '+') orelse std.mem.indexOfScalarPos(u8, computation, pos, '-') orelse std.mem.indexOfScalarPos(u8, computation, pos, '*') orelse std.mem.indexOfScalarPos(u8, computation, pos, '/');
}

// TODO: switch back to *capy.button_Impl when ziglang/zig#12325 is fixed
pub fn compute(_: *anyopaque) !void {
    const rawText = computationLabel.getText();
    const computation = rawText;

    const FloatType = f64;

    var result: FloatType = 0;
    var pos: usize = 0;

    while (true) {
        const op = findOperator(computation, pos);
        if (op) |operator| {
            const leftHand = computation[pos..operator];
            const end = findOperator(computation, operator + 1) orelse computation.len;
            const rightHand = computation[operator + 1 .. end];
            const leftHandNum = std.fmt.parseFloat(FloatType, leftHand) catch std.math.nan(FloatType);
            const rightHandNum = std.fmt.parseFloat(FloatType, rightHand) catch std.math.nan(FloatType);

            if (pos == 0) result = leftHandNum;

            switch (computation[operator]) {
                '+' => result += rightHandNum,
                '-' => result -= rightHandNum,
                '*' => result *= rightHandNum,
                '/' => result /= rightHandNum,
                else => unreachable,
            }

            pos = end;
        } else {
            if (pos == 0) {
                result = std.fmt.parseFloat(FloatType, computation) catch std.math.nan(FloatType);
            }
            break;
        }
    }

    allocator.free(computationLabel.getText());
    const text = try std.fmt.allocPrint(allocator, "{d}", .{result});
    computationLabel.setText(text);
}

pub fn main() !void {
    try capy.init();
    defer capy.deinit();

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer if (comptime !@import("builtin").target.cpu.arch.isWasm()) {
        _ = gpa.deinit();
    };

    if (comptime !@import("builtin").target.cpu.arch.isWasm()) {
        allocator = gpa.allocator();
    } else {
        allocator = std.heap.page_allocator;
    }

    var window = try capy.Window.init();
    computationLabel = capy.label(.{ .text = "" });
    defer allocator.free(computationLabel.getText());
    try window.set(capy.column(.{ .spacing = 10 }, .{
        capy.alignment(.{}, capy.column(.{}, .{
            computationLabel,
            capy.grid(.{
                .template_columns = &.{ .{ .pixels = 100 }, .{ .pixels = 100 }, .{ .pixels = 100 }, .{ .pixels = 200 } },
                .template_rows = &.{ .{ .pixels = 60 }, .{ .pixels = 60 }, .{ .pixels = 60 }, .{ .pixels = 60 }, .{ .pixels = 60 } },
                .column_spacing = 10,
                .row_spacing = 10,
            }, .{
                capy.button(.{ .label = "7", .onclick = pressedKey }),
                capy.button(.{ .label = "8", .onclick = pressedKey }),
                capy.button(.{ .label = "9", .onclick = pressedKey }),
                capy.button(.{ .label = "+", .onclick = pressedKey }),
                capy.button(.{ .label = "4", .onclick = pressedKey }),
                capy.button(.{ .label = "5", .onclick = pressedKey }),
                capy.button(.{ .label = "6", .onclick = pressedKey }),
                capy.button(.{ .label = "-", .onclick = pressedKey }),
                capy.button(.{ .label = "1", .onclick = pressedKey }),
                capy.button(.{ .label = "2", .onclick = pressedKey }),
                capy.button(.{ .label = "3", .onclick = pressedKey }),
                capy.button(.{ .label = "*", .onclick = pressedKey }),
                capy.button(.{ .label = "/", .onclick = pressedKey }),
                capy.button(.{ .label = "0", .onclick = pressedKey }),
                capy.button(.{ .label = "CE", .onclick = erase }),
                capy.button(.{ .label = ".", .onclick = pressedKey }),
                capy.spacing(),
                capy.button(.{ .label = "=", .onclick = compute }),
            }),
        })),
    }));
    window.setPreferredSize(400, 500);
    window.setTitle("Calculator");
    window.show();
    capy.runEventLoop();
}
