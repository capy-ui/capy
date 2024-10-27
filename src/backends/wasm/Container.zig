const common = @import("common.zig");
const js = @import("js.zig");
const lib = @import("../../capy.zig");
const GuiWidget = common.GuiWidget;
const Events = common.Events;

const Container = @This();

peer: *GuiWidget,

pub usingnamespace Events(Container);

pub fn create() !Container {
    return Container{
        .peer = try GuiWidget.init(
            Container,
            lib.lasting_allocator,
            "div",
            "container",
        ),
    };
}

pub fn add(self: *Container, peer: *GuiWidget) void {
    js.appendElement(self.peer.element, peer.element);
    self.peer.children.append(peer) catch unreachable;
}

pub fn remove(self: *const Container, peer: *GuiWidget) void {
    _ = peer;
    _ = self;
}

pub fn setTabOrder(self: *Container, peers: []const *GuiWidget) void {
    _ = peers;
    _ = self;
}

pub fn move(self: *const Container, peer: *GuiWidget, x: u32, y: u32) void {
    _ = self;
    js.setPos(peer.element, x, y);
}

pub fn resize(self: *const Container, peer: *GuiWidget, w: u32, h: u32) void {
    _ = self;
    js.setSize(peer.element, w, h);
    if (peer.user.resizeHandler) |handler| {
        handler(w, h, peer.userdata);
    }
}
