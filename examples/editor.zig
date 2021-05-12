usingnamespace @import("zgt");
const std = @import("std");

var area: FlatText_Impl = undefined;

pub const FlatText_Impl = struct {
    pub usingnamespace zgtInternal.All(FlatText_Impl);

    peer: ?zgtBackend.Canvas = null,
    handlers: FlatText_Impl.Handlers = undefined,
    text: StringDataWrapper,
    tree: std.zig.ast.Tree = undefined,

    pub fn init(text: []const u8) FlatText_Impl {
        return FlatText_Impl.init_events(FlatText_Impl {
            .text = StringDataWrapper.of(text)
        });
    }

    pub fn draw(self: *FlatText_Impl, ctx: DrawContext) !void {
        const width = 800;
        const height = 400;
        ctx.setColor(1, 1, 1);
        ctx.rectangle(0, 0, width, height);
        ctx.fill();

        var layout = DrawContext.TextLayout.init();
        defer layout.deinit();
        ctx.setColor(0, 0, 0);
        layout.setFont(.{ .face = "Fira Code", .size = 10.0 });
        layout.wrap = width;

        const source = self.text.get();
        var tokenizer = std.zig.Tokenizer.init(self.text.get());
        var lines = std.mem.split(source, "\n");
        var y: f64 = 0;
        var chars: usize = 0;
        var lastStart: usize = 0;
        while (lines.next()) |line| {
            if (y > height) break;
            var x: f64 = 0;
            chars += line.len + 1;
            while (true) {
                var token = tokenizer.next();
                if (token.loc.start >= chars or token.tag == .eof) {
                    tokenizer.index = token.loc.start;
                    break;
                }
                const tokSize = layout.getTextSize(source[lastStart..token.loc.end]);
                ctx.text(x, y, layout, source[lastStart..token.loc.end]);
                x += tokSize.width;

                lastStart = token.loc.end;
                while (lastStart < source.len-1 and source[lastStart] == '\n' or source[lastStart] == '\r') {
                    lastStart += 1;
                }
            }
            const size = layout.getTextSize("abcdefghi");
            y += size.height;
        }
    }

    /// Internal function used at initialization.
    /// It is used to move some pointers so things do not break.
    pub fn pointerMoved(self: *FlatText_Impl) void {
        self.text.updateBinders();
    }

    /// When the text is changed in the StringDataWrapper
    fn wrapperTextChanged(newValue: []const u8, userdata: usize) void {
        const self = @intToPtr(*FlatText_Impl, userdata);
        self.tree = std.zig.parse(std.heap.page_allocator, newValue) catch |err| {
            std.log.err("{s}", .{@errorName(err)});
            if (@errorReturnTrace()) |trace| {
                std.debug.dumpStackTrace(trace.*);
            }
            return;
        };
        self.requestDraw() catch unreachable;
    }

    pub fn show(self: *FlatText_Impl) !void {
        if (self.peer == null) {
            self.peer = try zgtBackend.Canvas.create();
            try self.show_events();

            self.text.userdata = @ptrToInt(&self.peer);
            self.text.onChangeFn = wrapperTextChanged;
            self.text.set(self.text.get());
        }
    }

    pub fn setText(self: *FlatText_Impl, text: []const u8) void {
        self.text.set(text);
    }

    pub fn getText(self: *FlatText_Impl) []const u8 {
        return self.text.get();
    }

    /// Bind the 'text' property to argument.
    pub fn bindText(self: *FlatText_Impl, other: *StringDataWrapper) FlatText_Impl {
        self.text.set(other.get());
        self.text.bind(other);
        return self.*;
    }
};

pub fn FlatText(config: struct { text: []const u8 = "" }) !FlatText_Impl {
    var btn = FlatText_Impl.init(config.text);
    try btn.addDrawHandler(FlatText_Impl.draw);
    return btn;
}

pub fn run() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}) {};
    const allocator = &gpa.allocator;
    defer _ = gpa.deinit();

    var window = try Window.init();

    var file = try std.fs.cwd().openFileZ("examples/editor.zig", .{ .read = true });
    defer file.close();
    const text = try file.readToEndAlloc(allocator, std.math.maxInt(usize));
    defer allocator.free(text);

    area = try FlatText(.{ .text = text });
    try window.set(
        Column(.{}, .{
            Row(.{}, .{
                Button(.{ .label = "Save" }),
                Button(.{ .label = "Run"  })
            }),
            Expanded(&area)
        })
    );

    window.resize(800, 600);
    window.show();
    window.run();
}
