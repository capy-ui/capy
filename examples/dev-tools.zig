const std = @import("std");
const capy = @import("capy");
pub usingnamespace capy.cross_platform;

pub const app_allocator = capy.internal.allocator;
var app_window: capy.Window = undefined;
var dev_protocol_stream: ?std.net.Stream = null;

pub const enable_dev_tools = false;

pub fn main() !void {
    try capy.init();
    defer capy.deinit();

    app_window = try capy.Window.init();
    try app_window.set(
        capy.navigation(.{ .routeName = "Connect" }, .{
            .Connect = capy.alignment(.{}, capy.column(.{}, .{
                capy.label(.{ .text = "Address" }),
                capy.textField(.{ .name = "server-address", .text = "localhost" }),
                capy.label(.{ .text = "Port" }),
                capy.textField(.{ .name = "server-port", .text = "42671" }),
                capy.alignment(.{ .x = 1 }, capy.button(.{ .label = "Connect", .onclick = onConnect })),
            })),
            .@"Dev Tools" = capy.column(.{}, .{
                capy.label(.{ .text = "Dev Tools", .layout = .{ .alignment = .Center } }),
                capy.expanded(capy.tabs(.{
                    capy.tab(
                        .{ .label = "Inspector" },
                        capy.row(.{}, .{
                            capy.expanded(
                                // TODO: widget tree
                                capy.label(.{ .text = "test" }),
                            ),
                            capy.expanded(capy.tabs(.{
                                capy.tab(.{ .label = "Properties" }, capy.column(.{}, .{
                                    capy.label(.{ .text = "Hello" }),
                                })),
                                capy.tab(.{ .label = "Source Code" }, capy.column(.{}, .{
                                    capy.textArea(.{ .text = "capy.row(.{}, .{})" }),
                                })),
                            })),
                        }),
                    ),
                    capy.tab(
                        .{ .label = "tab 2" },
                        capy.button(.{ .label = "Test 2" }),
                    ),
                })),
            }),
        }),
    );

    app_window.setTitle("Capy Dev Tools");
    app_window.setPreferredSize(400, 200);
    app_window.show();

    capy.runEventLoop();
}

fn onConnect(widget: *anyopaque) !void {
    const button = @as(*capy.Button, @ptrCast(@alignCast(widget)));
    const parent = button.getParent().?.getParent().?.as(capy.Container);
    const root = button.getRoot().?.as(capy.Navigation);

    const serverAddress = parent.getChildAs(capy.TextField, "server-address").?;
    const serverPort = parent.getChildAs(capy.TextField, "server-port").?;

    const port = try std.fmt.parseUnsigned(u16, serverPort.get("text"), 10);
    const addressList = try std.net.getAddressList(app_allocator, serverAddress.get("text"), port);
    defer addressList.deinit();

    const address = addressList.addrs[0];
    dev_protocol_stream = try std.net.tcpConnectToAddress(address);
    try root.navigateTo("Dev Tools", .{});

    const writer = dev_protocol_stream.?.writer();
    try writer.writeByte(@intFromEnum(capy.dev_tools.RequestId.get_windows_num));
}
