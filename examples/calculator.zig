const std = @import("std");
const zgt = @import("zgt");
pub usingnamespace zgt.cross_platform;

// Short names to avoid writing 'zgt.' each time
const Button = zgt.Button;
const Margin = zgt.Margin;
const Expanded = zgt.Expanded;
const Row = zgt.Row;

const Allocator = std.mem.Allocator;

var computationLabel: zgt.Label_Impl = undefined;
var allocator: Allocator = undefined;

pub fn pressedKey(button: *zgt.Button_Impl) !void {
    const buttonLabel = button.getLabel();
    const labelText = computationLabel.getText();

    // Concat the computation label with the first character of the button's label
    var larger = try allocator.allocSentinel(u8, labelText.len + 1, 0); // allocate a null-terminated string one character longer than labelText
    std.mem.copy(u8, larger, labelText); // copy labelText's contents to the newly allocated string
    larger[labelText.len] = buttonLabel[0]; // finally, set the last letter

    computationLabel.setText(larger); // and now we can put that as our new computation label text
    allocator.free(larger);
}

pub fn erase(button: *zgt.Button_Impl) !void {
    _ = button;
    computationLabel.setText("");
}

fn findOperator(computation: []const u8, pos: usize) ?usize {
    return std.mem.indexOfScalarPos(u8, computation, pos, '+')
        orelse std.mem.indexOfScalarPos(u8, computation, pos, '-')
        orelse std.mem.indexOfScalarPos(u8, computation, pos, '*')
        orelse std.mem.indexOfScalarPos(u8, computation, pos, '/');
}

pub fn compute(button: *zgt.Button_Impl) !void {
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
            const end = findOperator(computation, operator+1) orelse computation.len;
            const rightHand = computation[operator+1..end];
            const leftHandNum  = std.fmt.parseFloat(FloatType, leftHand) catch std.math.nan(FloatType);
            const rightHandNum = std.fmt.parseFloat(FloatType, rightHand) catch std.math.nan(FloatType);

            if (pos == 0) result = leftHandNum;

            switch (computation[operator]) {
                '+' => result += rightHandNum,
                '-' => result -= rightHandNum,
                '*' => result *= rightHandNum,
                '/' => result /= rightHandNum,
                else => unreachable
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
}

pub fn main() !void {
    try zgt.backend.init();
    var gpa = std.heap.GeneralPurposeAllocator(.{}) {};
    defer _ = gpa.deinit();
    allocator = gpa.allocator();

    var window = try zgt.Window.init();
    computationLabel = zgt.Label(.{ .text = "", .alignment = .Left });
    try window.set(zgt.Column(.{ .expand = .Fill }, .{
        &computationLabel,
        Expanded(Row(.{ .expand = .Fill }, .{
            Margin(Button(.{ .label = "7", .onclick = pressedKey })),
            Margin(Button(.{ .label = "8", .onclick = pressedKey })),
            Margin(Button(.{ .label = "9", .onclick = pressedKey })),
            Margin(Button(.{ .label = "+", .onclick = pressedKey })),
        })),
        Expanded(Row(.{ .expand = .Fill }, .{
            Margin(Button(.{ .label = "4", .onclick = pressedKey })),
            Margin(Button(.{ .label = "5", .onclick = pressedKey })),
            Margin(Button(.{ .label = "6", .onclick = pressedKey })),
            Margin(Button(.{ .label = "-", .onclick = pressedKey })),
        })),
        Expanded(Row(.{ .expand = .Fill }, .{
            Margin(Button(.{ .label = "1", .onclick = pressedKey })),
            Margin(Button(.{ .label = "2", .onclick = pressedKey })),
            Margin(Button(.{ .label = "3", .onclick = pressedKey })),
            Margin(Button(.{ .label = "*", .onclick = pressedKey })),
        })),
        Expanded(Row(.{ .expand = .Fill }, .{
            Margin(Button(.{ .label = "/" , .onclick = pressedKey })),
            Margin(Button(.{ .label = "0" , .onclick = pressedKey })),
            Margin(Button(.{ .label = "CE", .onclick = erase      })),
            Margin(Button(.{ .label = "." , .onclick = pressedKey }))
        })),
        Expanded(Button(.{ .label = "=", .onclick = compute }))
    }));
    window.resize(400, 500);
    window.show();
    zgt.runEventLoop();
}
