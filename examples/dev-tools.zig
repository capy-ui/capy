const std = @import("std");
const capy = @import("capy");
pub usingnamespace capy.cross_platform;

pub const app_allocator = capy.internal.lasting_allocator;
var app_window: capy.Window = undefined;
var dev_protocol_stream: ?std.net.Stream = null;

pub const enable_dev_tools = false;

pub fn main() !void {
    try capy.init();
    defer capy.deinit();

    app_window = try capy.Window.init();
    try app_window.set(
        capy.Navigation(.{ .routeName = "Connect" }, .{
            .Connect = capy.Align(.{}, capy.Column(.{}, .{
                capy.Label(.{ .text = "Address" }),
                capy.TextField(.{ .name = "server-address", .text = "localhost" }),
                capy.Label(.{ .text = "Port" }),
                capy.TextField(.{ .name = "server-port", .text = "42671" }),
                capy.Align(.{ .x = 1 }, capy.Button(.{ .label = "Connect", .onclick = onConnect })),
            })),
            .@"Dev Tools" = capy.Column(.{}, .{
                capy.Label(.{ .text = "Dev Tools", .alignment = .Center }),
                capy.Expanded(capy.Tabs(.{
                    capy.Tab(
                        .{ .label = "Inspector" },
                        capy.Row(.{}, .{
                            capy.Expanded(
                                // TODO: widget tree
                                capy.Label(.{ .text = "test" }),
                            ),
                            capy.Expanded(capy.Tabs(.{
                                capy.Tab(.{ .label = "Properties" }, capy.Column(.{}, .{
                                    capy.Label(.{ .text = "Hello" }),
                                })),
                                capy.Tab(.{ .label = "Source Code" }, capy.Column(.{}, .{
                                    capy.TextArea(.{ .text = "capy.Row(.{}, .{})" }),
                                })),
                            })),
                        }),
                    ),
                    capy.Tab(
                        .{ .label = "Tab 2" },
                        capy.Button(.{ .label = "Test 2" }),
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
    const button = @as(*capy.Button_Impl, @ptrCast(@alignCast(widget)));
    const parent = button.getParent().?.getParent().?.as(capy.Container_Impl);
    const root = button.getRoot().?.as(capy.Navigation_Impl);

    const serverAddress = parent.getChildAs(capy.TextField_Impl, "server-address").?;
    const serverPort = parent.getChildAs(capy.TextField_Impl, "server-port").?;

    const port = try std.fmt.parseUnsigned(u16, serverPort.get("text"), 10);
    const addressList = try std.net.getAddressList(app_allocator, serverAddress.get("text"), port);
    defer addressList.deinit();

    const address = addressList.addrs[0];
    dev_protocol_stream = try std.net.tcpConnectToAddress(address);
    try root.navigateTo("Dev Tools", .{});

    const writer = dev_protocol_stream.?.writer();
    try writer.writeByte(@intFromEnum(capy.dev_tools.RequestId.get_windows_num));
}
