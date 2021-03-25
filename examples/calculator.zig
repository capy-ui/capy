const std = @import("std");
usingnamespace @import("zgt");

const Allocator = std.mem.Allocator;

var computationLabel: Label_Impl = undefined;
var allocator: *Allocator = undefined;

pub fn pressedKey(button: *Button_Impl) !void {
    const buttonLabel = button.getLabel();
    const labelText = computationLabel.getText();

    // Concat the computation label with the first character of the button's label
    var larger = try allocator.allocSentinel(u8, labelText.len + 1, 0); // allocate a null-terminated string one character longer than labelText
    std.mem.copy(u8, larger, labelText); // copy labelText's contents to the newly allocated string
    larger[labelText.len] = buttonLabel[0]; // finally, set the last letter

    computationLabel.setText(larger); // and now we can put that as our new computation label text
    allocator.free(larger);
}

pub fn erase(button: *Button_Impl) !void {
    computationLabel.setText("");
}

fn findOperator(computation: []const u8, pos: usize) ?usize {
    return std.mem.indexOfScalarPos(u8, computation, pos, '+')
        orelse std.mem.indexOfScalarPos(u8, computation, pos, '-')
        orelse std.mem.indexOfScalarPos(u8, computation, pos, '*')
        orelse std.mem.indexOfScalarPos(u8, computation, pos, '/');
}

pub fn compute(button: *Button_Impl) !void {
    const rawText = computationLabel.getText();
    const computation = rawText[0..std.mem.lenZ(rawText)];

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
            break;
        }
    }

    const text = try std.fmt.allocPrintZ(allocator, "{d}", .{result});
    computationLabel.setText(text);
}

pub fn run() !void {
    //var gpa = std.heap.GeneralPurposeAllocator(.{}) {};
    //defer _ = gpa.deinit();
    //allocator = &gpa.allocator;
    allocator = std.heap.page_allocator;

    var window = try Window.init();
    computationLabel = Label(.{ .text = "", .alignment = .Left });
    try window.set(try Column(.{ .expand = .Fill }, .{
        &computationLabel,
        try Expanded(try Row(.{ .expand = .Fill }, .{
            try Expanded(Button(.{ .label = "7", .onclick = pressedKey })),
            try Expanded(Button(.{ .label = "8", .onclick = pressedKey })),
            try Expanded(Button(.{ .label = "9", .onclick = pressedKey })),
            try Expanded(Button(.{ .label = "+", .onclick = pressedKey })),
        })),
        try Expanded(try Row(.{ .expand = .Fill }, .{
            try Expanded(Button(.{ .label = "4", .onclick = pressedKey })),
            try Expanded(Button(.{ .label = "5", .onclick = pressedKey })),
            try Expanded(Button(.{ .label = "6", .onclick = pressedKey })),
            try Expanded(Button(.{ .label = "-", .onclick = pressedKey })),
        })),
        try Expanded(try Row(.{ .expand = .Fill }, .{
            try Expanded(Button(.{ .label = "1", .onclick = pressedKey })),
            try Expanded(Button(.{ .label = "2", .onclick = pressedKey })),
            try Expanded(Button(.{ .label = "3", .onclick = pressedKey })),
            try Expanded(Button(.{ .label = "*", .onclick = pressedKey })),
        })),
        try Expanded(try Row(.{ .expand = .Fill }, .{
            try Expanded(Button(.{ .label = "/" , .onclick = pressedKey })),
            try Expanded(Button(.{ .label = "0" , .onclick = pressedKey })),
            try Expanded(Button(.{ .label = "CE", .onclick = erase      })),
            try Expanded(Button(.{ .label = "." , .onclick = pressedKey }))
        })),
        try Expanded(Button(.{ .label = "=", .onclick = compute }))
    }));
    try window.resize(400, 500);
    window.show();
    window.run();
}
