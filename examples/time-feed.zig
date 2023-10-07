const std = @import("std");
const capy = @import("capy");
pub usingnamespace capy.cross_platform;

// All time values are in UNIX timestamp
const TimeActivity = struct {
    start: u64,
    end: u64,
    description: []const u8,
};

const ListModel = struct {
    size: capy.Atom(usize) = capy.Atom(usize).of(0),
    arena: std.heap.ArenaAllocator = std.heap.ArenaAllocator.init(capy.internal.lasting_allocator),
    data: std.ArrayList(TimeActivity),

    pub fn add(self: *ListModel, activity: TimeActivity) !void {
        try self.data.append(activity);
        self.size.set(self.size.get() + 1);
    }

    pub fn getComponent(self: *ListModel, index: usize) capy.Container {
        const activity = self.data.items[index];
        const start_epoch = std.time.epoch.EpochSeconds{ .secs = activity.start };
        const start_day = start_epoch.getDaySeconds();

        const end_epoch = std.time.epoch.EpochSeconds{ .secs = activity.end };
        const end_day = end_epoch.getDaySeconds();
        return Card(capy.column(.{}, .{
            capy.label(.{
                .text = std.fmt.allocPrintZ(self.arena.allocator(), "{d:0>2}:{d:0>2} - {d:0>2}:{d:0>2}", .{
                    start_day.getHoursIntoDay(),
                    start_day.getMinutesIntoHour(),
                    end_day.getHoursIntoDay(),
                    end_day.getMinutesIntoHour(),
                }) catch unreachable,
            }),
            capy.label(.{ .text = activity.description }),
            capy.alignment(.{ .x = 1 }, capy.button(.{ .label = "Edit" })),
        })) catch unreachable;
    }
};

pub fn Card(child: anytype) anyerror!capy.Container {
    return try capy.stack(.{
        capy.rect(.{ .color = capy.Color.comptimeFromString("#ffffff") }),
        capy.margin(capy.Rectangle.init(10, 10, 10, 10), try child),
    });
}

var submitDesc = capy.StringAtom.of("");
var submitEnabled = capy.Atom(bool).of(false);
var list_model: ListModel = undefined;

fn onSubmit(_: *anyopaque) !void {
    try list_model.add(.{
        .start = @as(u64, @intCast(std.time.timestamp() - 1000)),
        .end = @as(u64, @intCast(std.time.timestamp())),
        .description = try capy.internal.lasting_allocator.dupe(u8, submitDesc.get()),
    });

    // clear description
    submitDesc.set("");
}

pub fn InsertCard() anyerror!capy.Container {
    submitEnabled.dependOn(.{&submitDesc}, &(struct {
        fn callback(description: []const u8) bool {
            return description.len > 0;
        }
    }.callback)) catch unreachable;

    return try capy.column(.{}, .{
        // TODO: TextArea when it supports data wrappers
        capy.textArea(.{ .name = "description" })
            .bind("text", &submitDesc), // placeholder = "Task description..."
        capy.label(.{ .text = "Going on since.. 00:00:20" }),
        capy.alignment(.{ .x = 1 }, capy.row(.{}, .{
            capy.button(.{ .label = "Submit", .onclick = onSubmit })
                .bind("enabled", &submitEnabled),
            capy.button(.{ .label = "Delete" }), // TODO: icon
        })),
    });
}

pub fn main() !void {
    try capy.backend.init();

    list_model = ListModel{
        .data = std.ArrayList(TimeActivity).init(capy.internal.lasting_allocator),
    };
    var window = try capy.Window.init();
    try window.set(capy.column(.{}, .{
        capy.label(.{ .text = "Feed" }), // TODO: capy.Heading ?
        InsertCard(),
        // TODO: days labels / list categories
        capy.columnList(.{}, &list_model),
    }));

    window.setTitle("Time Feed");
    window.setPreferredSize(250, 100);
    window.show();

    capy.runEventLoop();
}
