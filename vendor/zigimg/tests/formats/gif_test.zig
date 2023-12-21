const PixelFormat = zigimg.PixelFormat;
const gif = zigimg.gif;
const color = zigimg.color;
const errors = zigimg.errors;
const zigimg = @import("../../zigimg.zig");
const Image = zigimg.Image;
const std = @import("std");
const testing = std.testing;
const helpers = @import("../helpers.zig");

test "Should error on non GIF images" {
    const file = try helpers.testOpenFile(helpers.fixtures_path ++ "bmp/simple_v4.bmp");
    defer file.close();

    var stream_source = std.io.StreamSource{ .file = file };

    var gif_file = gif.GIF.init(helpers.zigimg_test_allocator);
    defer gif_file.deinit();

    const invalid_file = gif_file.read(&stream_source);
    try helpers.expectError(invalid_file, Image.ReadError.InvalidData);
}

const SingleGifFileTest = false;

test "GIF test suite" {
    if (SingleGifFileTest) {
        return error.SkipZigTest;
    }

    var test_list = std.ArrayList([]const u8).init(helpers.zigimg_test_allocator);
    defer test_list.deinit();

    const test_list_file = try helpers.testOpenFile(helpers.fixtures_path ++ "gif/TESTS");
    defer test_list_file.close();

    var buffered_reader = std.io.bufferedReader(test_list_file.reader());
    var reader = buffered_reader.reader();

    var area_alloc = std.heap.ArenaAllocator.init(helpers.zigimg_test_allocator);
    const area_allocator = area_alloc.allocator();
    defer area_alloc.deinit();

    var read_line_opt = try reader.readUntilDelimiterOrEofAlloc(area_allocator, '\n', std.math.maxInt(u16));

    while (read_line_opt) |read_line| {
        try test_list.append(read_line);
        read_line_opt = try reader.readUntilDelimiterOrEofAlloc(area_allocator, '\n', std.math.maxInt(u16));
    }

    for (test_list.items) |entry| {
        doGifTest(entry) catch |err| {
            std.debug.print("Error: {}\n", .{err});
            continue;
        };

        std.debug.print("OK\n", .{});
    }
}

test "Rotating Earth GIF" {
    const gif_input_file = try helpers.testOpenFile(helpers.fixtures_path ++ "gif/rotating_earth.gif");
    defer gif_input_file.close();

    var stream_source = std.io.StreamSource{ .file = gif_input_file };

    var gif_file = gif.GIF.init(helpers.zigimg_test_allocator);
    defer gif_file.deinit();

    var frames = try gif_file.read(&stream_source);
    defer {
        for (frames.items) |entry| {
            entry.pixels.deinit(gif_file.allocator);
        }
        frames.deinit(gif_file.allocator);
    }

    try helpers.expectEq(gif_file.header.width, 400);
    try helpers.expectEq(gif_file.header.height, 400);

    try helpers.expectEq(frames.items.len, 44);

    try helpers.expectEq(frames.items[0].pixels.indexed8.indices[10], 106);
    try helpers.expectEq(frames.items[0].pixels.indexed8.indices[399 * 400 + 382], 8);
}

test "Iterate on a single GIF file" {
    if (!SingleGifFileTest) {
        return error.SkipZigTest;
    }

    try doGifTest("dispose-restore-previous");
}

const IniFile = struct {
    area_allocator: std.heap.ArenaAllocator,
    sections: std.StringArrayHashMapUnmanaged(SectionEntry) = .{},

    const SectionEntry = struct {
        dict: std.StringArrayHashMapUnmanaged(Value) = .{},

        pub fn getValue(self: SectionEntry, key: []const u8) ?Value {
            return self.dict.get(key);
        }
    };

    const Value = union(enum) {
        number: u32,
        string: []const u8,
    };

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator) Self {
        return .{
            .area_allocator = std.heap.ArenaAllocator.init(allocator),
        };
    }

    pub fn deinit(self: *Self) void {
        for (self.sections.values()) |*entry| {
            entry.dict.deinit(self.area_allocator.allocator());
        }
        self.sections.deinit(self.area_allocator.allocator());
        self.area_allocator.deinit();
    }

    pub fn parse(self: *Self, reader: anytype) !void {
        const allocator = self.area_allocator.allocator();
        var read_line_opt = try reader.readUntilDelimiterOrEofAlloc(allocator, '\n', std.math.maxInt(u16));

        var current_section: []const u8 = "";

        while (read_line_opt) |read_line| {
            if (read_line.len > 0) {
                switch (read_line[0]) {
                    '#' => {
                        // Do nothing
                    },
                    '[' => {
                        const end_bracket_position_opt = std.mem.lastIndexOf(u8, read_line[0..], "]");

                        if (end_bracket_position_opt) |end_bracket_position| {
                            current_section = read_line[1..end_bracket_position];

                            try self.sections.put(allocator, current_section, SectionEntry{});
                        } else {
                            return error.InvalidIniFile;
                        }
                    },
                    else => {
                        const equals_sign_position_opt = std.mem.indexOf(u8, read_line[0..], "=");

                        if (equals_sign_position_opt) |equals_sign_position| {
                            const key_name = std.mem.trimRight(u8, read_line[0..(equals_sign_position - 1)], " ");
                            const string_value = std.mem.trimLeft(u8, read_line[(equals_sign_position + 1)..], " ");

                            if (self.sections.getPtr(current_section)) |section_entry| {
                                const value = blk: {
                                    if (string_value.len > 0 and std.ascii.isDigit(string_value[0])) {
                                        const parsed_number = std.fmt.parseInt(u32, string_value, 10) catch {
                                            break :blk Value{
                                                .string = string_value,
                                            };
                                        };

                                        break :blk Value{
                                            .number = parsed_number,
                                        };
                                    }

                                    break :blk Value{
                                        .string = string_value,
                                    };
                                };
                                try section_entry.dict.put(allocator, key_name, value);
                            }
                        }
                    },
                }
            }

            read_line_opt = try reader.readUntilDelimiterOrEofAlloc(allocator, '\n', std.math.maxInt(u16));
        }
    }

    pub fn getSection(self: Self, section_name: []const u8) ?SectionEntry {
        return self.sections.get(section_name);
    }
};

fn doGifTest(entry_name: []const u8) !void {
    std.debug.print("GIF test {s}... ", .{entry_name});

    var area_alloc = std.heap.ArenaAllocator.init(helpers.zigimg_test_allocator);
    const area_allocator = area_alloc.allocator();
    defer area_alloc.deinit();

    const config_filename = try std.fmt.allocPrint(area_allocator, "{s}.conf", .{entry_name});
    const config_filepath = try std.fs.path.resolve(area_allocator, &[_][]const u8{ helpers.fixtures_path, "gif", config_filename });

    const config_file = try helpers.testOpenFile(config_filepath);
    defer config_file.close();

    var config_ini = IniFile.init(helpers.zigimg_test_allocator);
    defer config_ini.deinit();

    var buffered_reader = std.io.bufferedReader(config_file.reader());

    try config_ini.parse(buffered_reader.reader());

    if (config_ini.getSection("config")) |config_section| {
        const input_filename = config_section.getValue("input") orelse return error.InvalidGifConfigFile;
        const expected_version = config_section.getValue("version") orelse return error.InvalidGifConfigFile;
        const expected_width = config_section.getValue("width") orelse return error.InvalidGifConfigFile;
        const expected_height = config_section.getValue("height") orelse return error.InvalidGifConfigFile;

        const expected_background_color_opt = blk: {
            if (config_section.getValue("background")) |string_background_color| {
                break :blk @as(?color.Rgba32, try color.Rgba32.fromHtmlHex(string_background_color.string));
            }

            break :blk @as(?color.Rgba32, null);
        };

        const expected_loop_count = if (config_section.getValue("loop-count")) |loop_value|
            switch (loop_value) {
                .number => |number| @as(i32, @intCast(number)),
                .string => |string| if (std.mem.eql(u8, string, "infinite")) @as(i32, -1) else return error.InvalidGifConfigFile,
            }
        else
            return error.InvalidGifConfigFile;

        const gif_input_filepath = try std.fs.path.resolve(area_allocator, &[_][]const u8{ helpers.fixtures_path, "gif", input_filename.string });
        const gif_input_file = try helpers.testOpenFile(gif_input_filepath);
        defer gif_input_file.close();

        var stream_source = std.io.StreamSource{ .file = gif_input_file };

        var gif_file = gif.GIF.init(helpers.zigimg_test_allocator);
        defer gif_file.deinit();

        var frames = try gif_file.read(&stream_source);
        defer {
            for (frames.items) |entry| {
                entry.pixels.deinit(gif_file.allocator);
            }
            frames.deinit(gif_file.allocator);
        }

        try helpers.expectEqSlice(u8, gif_file.header.magic[0..], expected_version.string[0..3]);
        try helpers.expectEqSlice(u8, gif_file.header.version[0..], expected_version.string[3..]);
        try helpers.expectEq(gif_file.header.width, @as(u16, @intCast(expected_width.number)));
        try helpers.expectEq(gif_file.header.height, @as(u16, @intCast(expected_height.number)));

        if (expected_background_color_opt) |expected_background_color| {
            try helpers.expectEq(gif_file.global_color_table.data[gif_file.header.background_color_index].toU32Rgba(), expected_background_color.toU32Rgba());
        }

        try helpers.expectEq(gif_file.loopCount(), expected_loop_count);

        if (config_section.getValue("comment")) |comment_value| {
            const first_quote_index = std.mem.indexOfScalar(u8, comment_value.string, '\'') orelse 0;
            const last_quote_index = std.mem.lastIndexOfScalar(u8, comment_value.string, '\'') orelse comment_value.string.len;

            const comment_slice = comment_value.string[(first_quote_index + 1)..(last_quote_index)];

            try std.testing.expect(gif_file.comments.items.len > 0);

            if (std.mem.eql(u8, comment_slice, "\\x00")) {
                try helpers.expectEq(gif_file.comments.items[0].comment[0], 0);
            } else {
                try helpers.expectEqSlice(u8, gif_file.comments.items[0].comment, comment_slice);
            }
        }

        const string_frames = config_section.getValue("frames") orelse return error.InvalidGifConfigFile;

        if (string_frames.string.len > 0) {
            var frame_iterator = std.mem.split(u8, string_frames.string, ",");
            var frame_index: usize = 0;
            while (frame_iterator.next()) |current_frame| {
                if (config_ini.getSection(current_frame)) |frame_section| {
                    const pixels_filename = frame_section.getValue("pixels") orelse return error.InvalidGifConfigFile;
                    const pixels_filepath = try std.fs.path.resolve(area_allocator, &[_][]const u8{ helpers.fixtures_path, "gif", pixels_filename.string });
                    const pixels_file = try helpers.testOpenFile(pixels_filepath);
                    defer pixels_file.close();

                    var pixels_buffred_reader = std.io.bufferedReader(pixels_file.reader());
                    var pixels_reader = pixels_buffred_reader.reader();

                    var pixel_list = std.ArrayList(color.Rgba32).init(area_allocator);
                    defer pixel_list.deinit();

                    var read_buffer: [@sizeOf(color.Rgba32)]u8 = undefined;

                    var read_size = try pixels_reader.readAll(read_buffer[0..]);
                    while (read_size > 0) {
                        const read_color = std.mem.bytesAsValue(color.Rgba32, read_buffer[0..]);
                        try pixel_list.append(read_color.*);

                        read_size = try pixels_reader.readAll(read_buffer[0..]);
                    }

                    var frame_data_iterator = color.PixelStorageIterator.init(&frames.items[frame_index].pixels);

                    const background_color_index = gif_file.header.background_color_index;

                    const gif_background_color = switch (frames.items[frame_index].pixels) {
                        .indexed1 => |pixels| if (background_color_index < pixels.palette.len) pixels.palette[background_color_index] else color.Rgba32.initRgba(0, 0, 0, 0),
                        .indexed2 => |pixels| if (background_color_index < pixels.palette.len) pixels.palette[background_color_index] else color.Rgba32.initRgba(0, 0, 0, 0),
                        .indexed4 => |pixels| if (background_color_index < pixels.palette.len) pixels.palette[background_color_index] else color.Rgba32.initRgba(0, 0, 0, 0),
                        .indexed8 => |pixels| if (background_color_index < pixels.palette.len) pixels.palette[background_color_index] else color.Rgba32.initRgba(0, 0, 0, 0),
                        else => color.Rgba32.initRgba(0, 0, 0, 0),
                    };

                    for (pixel_list.items) |expected_color| {
                        if (frame_data_iterator.next()) |actual_color| {
                            if (expected_color.toU32Rgba() == 0) {
                                try helpers.expectEq(actual_color.toRgba32(), gif_background_color);
                            } else {
                                try helpers.expectEq(actual_color.toRgba32(), expected_color);
                            }
                        }
                    }

                    if (config_section.getValue("delay")) |delay| {
                        const actual_duration: u32 = @intFromFloat(frames.items[frame_index].duration * 100);

                        try helpers.expectEq(actual_duration, delay.number);
                    }
                } else {
                    return error.InvalidGifConfigFile;
                }

                frame_index += 1;
            }

            try helpers.expectEq(frames.items.len, frame_index);
        }
    } else {
        return error.InvalidGifConfigFile;
    }
}
