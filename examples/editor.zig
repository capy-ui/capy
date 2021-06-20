usingnamespace @import("zgt");
const std = @import("std");

var area: FlatText_Impl = undefined;

const Color = struct {
    r: f64, g: f64, b: f64
};

const KeywordType = enum {
    /// Type declarations (enum, struct, fn)
    Type,
    /// Basically the rest
    ControlFlow,
    Identifier,
    Value,
    String,
    Comment,
    None,

    pub fn getColor(self: KeywordType) Color {
        return switch (self) {
            .Type        => Color { .r = 0, .g = 0.6, .b = 0.8 },
            .ControlFlow => Color { .r = 1, .g = 0, .b = 0 },
            .Identifier  => Color { .r = 0, .g = 1, .b = 0 },
            else        => Color { .r = 0, .g = 0, .b = 0 }
        };
    }
};

const tagArray = std.enums.directEnumArrayDefault(std.zig.Token.Tag, KeywordType, .None, 0, .{
    .keyword_return = .ControlFlow,
    .keyword_try = .ControlFlow,
    .keyword_if = .ControlFlow,
    .keyword_else = .ControlFlow,
    .keyword_defer = .ControlFlow,
    .keyword_while = .ControlFlow,
    .keyword_switch = .ControlFlow,
    .keyword_catch = .ControlFlow,
    .builtin = .ControlFlow,

    .keyword_pub = .ControlFlow, // TODO: .Modifier ?
    .keyword_usingnamespace = .ControlFlow,

    .keyword_fn = .Type,
    .keyword_struct = .Type,
    .keyword_enum = .Type,

    .keyword_var = .ControlFlow,
    .keyword_const = .ControlFlow,

});

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
        const width = self.getWidth();
        const height = self.getHeight();

        ctx.setColor(1, 1, 1);
        ctx.rectangle(0, 0, width, height);
        ctx.fill();

        var layout = DrawContext.TextLayout.init();
        defer layout.deinit();
        ctx.setColor(0, 0, 0);
        layout.setFont(.{ .face = "Fira Code", .size = 10.0 });

        const source = self.text.get();
        var tokenizer = std.zig.Tokenizer.init(self.text.get());
        var lines = std.mem.split(source, "\n");
        var y: u32 = 0;
        var chars: usize = 0;
        var lastStart: usize = 0;

        // TODO: just use native rendering's api styling
        // as doing it manually can break ligatures and non-Latin scripts

        while (lines.next()) |line| {
            if (y > height) break;
            var x: u32 = 0;
            chars += line.len + 1;
            while (true) {
                var token = tokenizer.next();
                if (token.loc.start >= chars or token.tag == .eof) {
                    tokenizer.index = token.loc.start;
                    break;
                }
                const behindSize = layout.getTextSize(source[lastStart..token.loc.start]);
                ctx.setColor(0, 0, 0);
                ctx.text(x, y, layout, source[lastStart..token.loc.start]);
                x += behindSize.width;

                const tokenSize = layout.getTextSize(source[token.loc.start..token.loc.end]);
                const color = tagArray[@enumToInt(token.tag)].getColor();
                ctx.setColor(color.r, color.g, color.b);
                ctx.text(x, y, layout, source[token.loc.start..token.loc.end]);
                x += tokenSize.width;

                lastStart = token.loc.end;
                while (lastStart < source.len-1 and source[lastStart] == '\n' or source[lastStart] == '\r') {
                    lastStart += 1;
                }
            }
            const size = layout.getTextSize(line);
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
    var textEditor = FlatText_Impl.init(config.text);
    try textEditor.addDrawHandler(FlatText_Impl.draw);
    return textEditor;
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
