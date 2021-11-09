const std = @import("std");
const zgt = @import("zgt");
pub usingnamespace zgt.cross_platform;

var count = zgt.DataWrapper(i64).of(0);
var label = zgt.StringDataWrapper.of("0");

//pub const zgtBackend = zgt.GlBackend;

fn increment(button: *zgt.Button_Impl) !void {
    _ = button;
    count.set(count.get() + 1);
}

// 'updater' functions are executed once a first time in order to know
// on which properties and which objects does it depends on, and
// automatically call this function when needed.
fn buttonEnabled(root: *zgt.Container_Impl) bool {
    const field = root.get("text-field").?.as(zgt.TextField_Impl);
    return field.getText().len > 0;
}

pub fn main() !void {
    try zgt.backend.init();

    var window = try zgt.Window.init();
    
    var format = try zgt.FormatDataWrapper(zgt.internal.lasting_allocator, "{d}", .{ &count });
    defer format.deinit();
    try window.set(
        zgt.Column(.{ .expand = .Fill }, .{
            zgt.Row(.{}, .{
                zgt.Expanded(
                    zgt.TextField(.{})
                        .setName("text-field")
                        .bindText(format)
                ),
                zgt.Button(.{ .label = "Count", .onclick = increment })
                    //.setEnabledUpdater(buttonEnabled)
            })
        })
    );

    window.resize(250, 100);
    window.show();

    // Count to 100 in 2000ms
    count.animate(zgt.Easings.InOut, 100, 2000);

    while (zgt.stepEventLoop(.Asynchronous)) {
        _ = count.update();
        std.time.sleep(16);
    }
}
