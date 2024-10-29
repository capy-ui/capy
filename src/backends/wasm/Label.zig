const std = @import("std");
const common = @import("common.zig");
const js = @import("js.zig");
const lib = @import("../../capy.zig");
const GuiWidget = common.GuiWidget;
const Events = common.Events;

const Label = @This();

peer: *GuiWidget,
/// The text returned by getText(), it's invalidated everytime setText is called
temp_text: ?[]const u8 = null,

pub usingnamespace Events(Label);

pub fn create() !Label {
    return Label{ .peer = try GuiWidget.init(
        Label,
        lib.lasting_allocator,
        "span",
        "label",
    ) };
}

pub fn setAlignment(_: *Label, _: f32) void {}

pub fn setFont(self: *Label, font: lib.Font) void {
    if (font.family) |family| {
        js.setStyle(self.peer.element, "fontFamily", family);
    } else {
        js.removeAttribute(self.peer.element, "fontFamily");
    }
    if (font.size) |size| {
        var buf: [100]u8 = undefined;
        js.setStyle(
            self.peer.element,
            "fontSize",
            std.fmt.bufPrint(&buf, "{d}pt", .{size}) catch unreachable,
        );
    } else {
        js.removeAttribute(self.peer.element, "fontSize");
    }
}

pub fn setText(self: *Label, text: []const u8) void {
    js.setText(self.peer.element, text.ptr, text.len);
    if (self.temp_text) |slice| {
        lib.lasting_allocator.free(slice);
        self.temp_text = null;
    }
}

pub fn getText(self: *Label) []const u8 {
    if (self.temp_text) |text| {
        return text;
    } else {
        const len = js.getTextLen(self.peer.element);
        const text = lib.lasting_allocator.allocSentinel(u8, len, 0) catch unreachable;
        js.getText(self.peer.element, text.ptr);
        self.temp_text = text;

        return text;
    }
}
