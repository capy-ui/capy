const std = @import("std");
const capy = @import("capy");
pub usingnamespace capy.cross_platform;

const ListModel = struct {
    /// size is a data wrapper so that we can change it (e.g. implement infinite scrolling)
    size: capy.DataWrapper(usize) = capy.DataWrapper(usize).of(10),
    arena: std.heap.ArenaAllocator = std.heap.ArenaAllocator.init(capy.internal.lasting_allocator),

    pub fn getComponent(self: *ListModel, index: usize) capy.Label_Impl {
        return capy.Label(.{
            .text = std.fmt.allocPrintZ(self.arena.allocator(), "Label #{d}", .{ index + 1 }) catch unreachable,
        });
    }

};

pub fn main() !void {
    try capy.backend.init();

    var hn_list_model = ListModel {};

    var window = try capy.Window.init();
    try window.set(
        capy.Stack(.{
            capy.Rect(.{ .color = capy.Color.comptimeFromString("#f6f6ef") }),
            capy.Column(.{}, .{
                capy.Stack(.{
                    capy.Rect(.{ .color = capy.Color.comptimeFromString("#ff6600") }),
                    capy.Label(.{ .text = "Hacker News" }),
                }),
                capy.ColumnList(.{}, &hn_list_model),
            }),
        }),
    );
    window.setTitle("Hacker News");
    window.show();

    // The last time a new entry was added to the list
    var last_add = std.time.milliTimestamp();
    while (capy.stepEventLoop(.Asynchronous)) {
        if (std.time.milliTimestamp() >= last_add + 1000) {
            hn_list_model.size.set(hn_list_model.size.get() + 1);
            std.log.info("There are now {} items.", .{ hn_list_model.size.get() });
            last_add = std.time.milliTimestamp();
        }
        std.time.sleep(16 * std.time.ns_per_ms);
    }
}
