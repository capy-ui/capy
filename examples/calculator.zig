const std = @import("std");
const capy = @import("capy");
pub usingnamespace capy.cross_platform;

// Short names to avoid writing 'capy.' each time
const Button = capy.Button;
const Margin = capy.Margin;
const Expanded = capy.Expanded;
const Row = capy.Row;

const Allocator = std.mem.Allocator;

var computationLabel: capy.Label_Impl = undefined;
var allocator: Allocator = undefined;

pub fn pressedKey(button: *capy.Button_Impl) !void {
    const buttonLabel = button.getLabel();
    const labelText = computationLabel.getText();

    // Concat the computation label with the first character of the button's label
    var larger = try allocator.allocSentinel(u8, labelText.len + 1, 0); // allocate a null-terminated string one character longer than labelText
    std.mem.copy(u8, larger, labelText); // copy labelText's contents to the newly allocated string
    larger[labelText.len] = buttonLabel[0]; // finally, set the last letter

    computationLabel.setText(larger); // and now we can put that as our new computation label text
    allocator.free(larger);
}

pub fn erase(button: *capy.Button_Impl) !void {
    _ = button;
    computationLabel.setText("");
}

fn findOperator(computation: []const u8, pos: usize) ?usize {
    return std.mem.indexOfScalarPos(u8, computation, pos, '+') orelse std.mem.indexOfScalarPos(u8, computation, pos, '-') orelse std.mem.indexOfScalarPos(u8, computation, pos, '*') orelse std.mem.indexOfScalarPos(u8, computation, pos, '/');
}

pub fn compute(button: *capy.Button_Impl) !void {
    _ = button;
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

    const text = try std.fmt.allocPrintZ(allocator, "{d}", .{result});
    computationLabel.setText(text);
    allocator.free(text);
}

pub fn main() !void {
    try capy.backend.init();
    if (comptime !@import("builtin").target.isWasm()) {
        var gpa = std.heap.GeneralPurposeAllocator(.{}){};
        defer _ = gpa.deinit();
        allocator = gpa.allocator();
    } else {
        allocator = std.heap.page_allocator;
    }

    var window = try capy.Window.init();
    computationLabel = capy.Label(.{ .text = "", .alignment = .Left });
    try window.set(capy.Column(.{ .expand = .Fill, .spacing = 10 }, .{
        &computationLabel,
        Expanded(Row(.{ .expand = .Fill, .spacing = 10 }, .{
            Button(.{ .label = "7", .onclick = pressedKey }),
            Button(.{ .label = "8", .onclick = pressedKey }),
            Button(.{ .label = "9", .onclick = pressedKey }),
            Button(.{ .label = "+", .onclick = pressedKey }),
        })),
        Expanded(Row(.{ .expand = .Fill, .spacing = 10 }, .{
            Button(.{ .label = "4", .onclick = pressedKey }),
            Button(.{ .label = "5", .onclick = pressedKey }),
            Button(.{ .label = "6", .onclick = pressedKey }),
            Button(.{ .label = "-", .onclick = pressedKey }),
        })),
        Expanded(Row(.{ .expand = .Fill, .spacing = 10 }, .{
            Button(.{ .label = "1", .onclick = pressedKey }),
            Button(.{ .label = "2", .onclick = pressedKey }),
            Button(.{ .label = "3", .onclick = pressedKey }),
            Button(.{ .label = "*", .onclick = pressedKey }),
        })),
        Expanded(Row(.{ .expand = .Fill, .spacing = 10 }, .{
            Button(.{ .label = "/", .onclick = pressedKey }),
            Button(.{ .label = "0", .onclick = pressedKey }),
            Button(.{ .label = "CE", .onclick = erase }),
            Button(.{ .label = ".", .onclick = pressedKey }),
        })),
        Expanded(Button(.{ .label = "=", .onclick = compute })),
    }));
    window.resize(400, 500);
    window.setTitle("Calculator");
    window.show();
    capy.runEventLoop();
}
