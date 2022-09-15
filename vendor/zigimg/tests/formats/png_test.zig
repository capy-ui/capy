// const assert = std.debug.assert;
// const testing = std.testing;

const std = @import("std");
const helpers = @import("../helpers.zig");
const png = @import("../../src/formats/png.zig");
const types = @import("../../src/formats/png/types.zig");
const color = @import("../../src/color.zig");
const Image = @import("../../src/Image.zig");
const PixelFormat = @import("../../src/pixel_format.zig").PixelFormat;
const InfoProcessor = @import("../../src/formats/png/InfoProcessor.zig");
const ImageReadError = Image.ReadError;
const expectError = std.testing.expectError;
const magic_header = types.magic_header;

const valid_header_data = magic_header ++ "\x00\x00\x00\x0d" ++ png.Chunks.IHDR.name ++
    "\x00\x00\x00\xff\x00\x00\x00\x75\x08\x06\x00\x00\x01\xf6\x24\x07\xe2";

test "Should error on non PNG images" {
    const file = try helpers.testOpenFile(helpers.fixtures_path ++ "bmp/simple_v4.bmp");
    defer file.close();

    var stream_source = std.io.StreamSource{ .file = file };

    const invalidFile = png.PNG.readImage(helpers.zigimg_test_allocator, &stream_source);

    try helpers.expectError(invalidFile, ImageReadError.InvalidData);
}

test "loadHeader_valid" {
    const expectEqual = std.testing.expectEqual;
    var buffer = valid_header_data.*;
    var stream = Image.Stream{ .buffer = std.io.fixedBufferStream(&buffer) };
    var header = try png.loadHeader(&stream);
    try expectEqual(@as(u32, 0xff), header.width);
    try expectEqual(@as(u32, 0x75), header.height);
    try expectEqual(@as(u8, 8), header.bit_depth);
    try expectEqual(png.ColorType.rgba_color, header.color_type);
    try expectEqual(png.CompressionMethod.deflate, header.compression_method);
    try expectEqual(png.FilterMethod.adaptive, header.filter_method);
    try expectEqual(png.InterlaceMethod.adam7, header.interlace_method);
}

test "PNG loadHeader() should error when data is empty" {
    var buffer: [0]u8 = undefined;
    var stream = Image.Stream{ .buffer = std.io.fixedBufferStream(&buffer) };
    try expectError(Image.ReadError.EndOfStream, png.loadHeader(&stream));
}

test "PNG loadHeader() should error when header signature is invalid" {
    var buffer = "asdsdasdasdsads".*;
    var stream = Image.Stream{ .buffer = std.io.fixedBufferStream(&buffer) };
    try expectError(Image.ReadError.InvalidData, png.loadHeader(&stream));
}

test "PNG loadHeader() should error on bad header chunk" {
    var buffer = (magic_header ++ "\x00\x00\x01\x0d" ++ png.Chunks.IHDR.name ++ "asad").*;
    var stream = Image.Stream{ .buffer = std.io.fixedBufferStream(&buffer) };
    try expectError(Image.ReadError.InvalidData, png.loadHeader(&stream));
}

test "PNG loadHeader() should error when header is too short" {
    var buffer = (magic_header ++ "\x00\x00\x00\x0d" ++ png.Chunks.IHDR.name ++ "asad").*;
    var stream = Image.Stream{ .buffer = std.io.fixedBufferStream(&buffer) };
    try expectError(Image.ReadError.EndOfStream, png.loadHeader(&stream));
}

test "PNG loadHeader() should error on invalid data in header" {
    var buffer = valid_header_data.*;
    var position = magic_header.len + @sizeOf(types.ChunkHeader);

    try testHeaderWithInvalidValue(buffer[0..], position, 0xf0); // width highest bit is 1
    position += 3;
    try testHeaderWithInvalidValue(buffer[0..], position, 0x00); // width is 0
    position += 1;
    try testHeaderWithInvalidValue(buffer[0..], position, 0xf0); // height highest bit is 1
    position += 3;
    try testHeaderWithInvalidValue(buffer[0..], position, 0x00); // height is 0

    position += 1;
    try testHeaderWithInvalidValue(buffer[0..], position, 0x00); // invalid bit depth
    try testHeaderWithInvalidValue(buffer[0..], position, 0x07); // invalid bit depth
    try testHeaderWithInvalidValue(buffer[0..], position, 0x03); // invalid bit depth
    try testHeaderWithInvalidValue(buffer[0..], position, 0x04); // invalid bit depth for rgba color type
    try testHeaderWithInvalidValue(buffer[0..], position, 0x02); // invalid bit depth for rgba color type
    try testHeaderWithInvalidValue(buffer[0..], position, 0x01); // invalid bit depth for rgba color type
    position += 1;
    try testHeaderWithInvalidValue(buffer[0..], position, 0x01); // invalid color type
    try testHeaderWithInvalidValue(buffer[0..], position, 0x05);
    try testHeaderWithInvalidValue(buffer[0..], position, 0x07);
    position += 1;
    try testHeaderWithInvalidValue(buffer[0..], position, 0x01); // invalid compression method
    position += 1;
    try testHeaderWithInvalidValue(buffer[0..], position, 0x01); // invalid filter method
    position += 1;
    try testHeaderWithInvalidValue(buffer[0..], position, 0x02); // invalid interlace method
}

fn testHeaderWithInvalidValue(buf: []u8, position: usize, val: u8) !void {
    var origin = buf[position];
    buf[position] = val;
    var stream = Image.Stream{ .buffer = std.io.fixedBufferStream(buf) };
    try expectError(Image.ReadError.InvalidData, png.loadHeader(&stream));
    buf[position] = origin;
}

test "PNG Official Test Suite" {
    try testWithDir(helpers.fixtures_path ++ "png/", true);
}

// Useful to quickly test everything on full dir of images
pub fn testWithDir(directory: []const u8, testMd5Sig: bool) !void {
    var testdir = std.fs.cwd().openIterableDir(directory, .{ .access_sub_paths = false, .no_follow = true }) catch null;
    if (testdir) |*idir| {
        defer idir.close();
        var it = idir.iterate();
        if (testMd5Sig) std.debug.print("\n", .{});
        while (try it.next()) |entry| {
            if (entry.kind != .File or !std.mem.eql(u8, std.fs.path.extension(entry.name), ".png")) continue;

            if (testMd5Sig) std.debug.print("Testing file {s} ... ", .{entry.name});
            var tst_file = try idir.dir.openFile(entry.name, .{ .mode = .read_only });
            defer tst_file.close();
            var stream = Image.Stream{ .file = tst_file };
            if (entry.name[0] == 'x' and entry.name[2] != 't' and entry.name[2] != 's') {
                try std.testing.expectError(Image.ReadError.InvalidData, png.loadHeader(&stream));
                if (testMd5Sig) std.debug.print("OK\n", .{});
                continue;
            }

            var default_options = png.DefaultOptions{};
            var header = try png.loadHeader(&stream);
            if (entry.name[0] == 'x') {
                var error_result = png.loadWithHeader(&stream, &header, std.testing.allocator, default_options.get());
                try std.testing.expectError(Image.ReadError.InvalidData, error_result);
                if (testMd5Sig) std.debug.print("OK\n", .{});
                continue;
            }

            var result = try png.loadWithHeader(&stream, &header, std.testing.allocator, default_options.get());
            defer result.deinit(std.testing.allocator);

            if (!testMd5Sig) continue;

            var result_bytes = result.asBytes();
            var md5_val: [16]u8 = undefined;
            std.crypto.hash.Md5.hash(result_bytes, &md5_val, .{});

            const len = entry.name.len;
            var tst_data_name: [50]u8 = undefined;
            std.mem.copy(u8, tst_data_name[0 .. len - 3], entry.name[0 .. len - 3]);
            std.mem.copy(u8, tst_data_name[len - 3 .. len], "tsd");

            // Read test data and check with it
            if (idir.dir.openFile(tst_data_name[0..len], .{ .mode = .read_only })) |tdata| {
                defer tdata.close();
                var treader = tdata.reader();
                var expected_md5: [16]u8 = undefined;
                var read_buffer: [50]u8 = undefined;
                var str_format = try treader.readUntilDelimiter(read_buffer[0..], '\n');
                var expected_pixel_format = std.meta.stringToEnum(PixelFormat, str_format).?;
                var str_md5 = try treader.readUntilDelimiterOrEof(read_buffer[0..], '\n');
                _ = try std.fmt.hexToBytes(expected_md5[0..], str_md5.?);
                try std.testing.expectEqual(expected_pixel_format, std.meta.activeTag(result));
                try std.testing.expectEqualSlices(u8, expected_md5[0..], md5_val[0..]); // catch std.debug.print("MD5 Expected: {s} Got {s}\n", .{std.fmt.fmtSliceHexUpper(expected_md5[0..]), std.fmt.fmtSliceHexUpper(md5_val[0..])});
            } else |_| {
                // If there is no test data assume test is correct and write it out
                try writeTestData(idir.dir, tst_data_name[0..len], &result, md5_val[0..]);
            }

            if (testMd5Sig) std.debug.print("OK\n", .{});

            // Write Raw bytes
            // std.mem.copy(u8, tst_data_name[len - 3 .. len + 1], "data");
            // var rawoutput = try idir.dir.createFile(tst_data_name[0 .. len + 1], .{});
            // defer rawoutput.close();
            // try rawoutput.writeAll(result_bytes);
        }
    }
}

fn writeTestData(dir: std.fs.Dir, tst_data_name: []const u8, result: *color.PixelStorage, md5_val: []const u8) !void {
    var toutput = try dir.createFile(tst_data_name, .{});
    defer toutput.close();
    var writer = toutput.writer();
    try writer.print("{s}\n{s}", .{ @tagName(result.*), std.fmt.fmtSliceHexUpper(md5_val) });
}

test "InfoProcessor on Png Test suite" {
    const directory = helpers.fixtures_path ++ "png/";

    var testdir = std.fs.cwd().openIterableDir(directory, .{ .access_sub_paths = false, .no_follow = true }) catch null;
    if (testdir) |*idir| {
        defer idir.close();
        var it = idir.iterate();

        var info_buffer: [16384]u8 = undefined;
        var info_stream = std.io.StreamSource{ .buffer = std.io.fixedBufferStream(info_buffer[0..]) };

        while (try it.next()) |entry| {
            if (entry.kind != .File or !std.mem.eql(u8, std.fs.path.extension(entry.name), ".png")) {
                continue;
            }

            var options = InfoProcessor.PngInfoOptions{
                .processor = InfoProcessor.init(info_stream.writer()),
            };

            var tst_file = try idir.dir.openFile(entry.name, .{ .mode = .read_only });
            defer tst_file.close();
            var stream = Image.Stream{ .file = tst_file };
            if (entry.name[0] == 'x') {
                continue;
            }

            info_stream.buffer.reset();

            var result = try png.load(&stream, std.testing.allocator, options.get());
            defer result.deinit();

            const len = entry.name.len + 1;
            var tst_data_name: [50]u8 = undefined;
            std.mem.copy(u8, tst_data_name[0 .. len - 4], entry.name[0 .. len - 4]);
            std.mem.copy(u8, tst_data_name[len - 4 .. len], "info");

            // Read test data and check with it
            if (idir.dir.openFile(tst_data_name[0..len], .{ .mode = .read_only })) |tdata| {
                defer tdata.close();
                var expected_data_buffer: [16384]u8 = undefined;
                const loaded = try tdata.reader().readAll(expected_data_buffer[0..]);
                try std.testing.expectEqualSlices(u8, expected_data_buffer[0..loaded], info_buffer[0..loaded]);
            } else |_| {
                // If there is no test data assume test is correct and write it out
                var toutput = try idir.dir.createFile(tst_data_name[0..len], .{});
                defer toutput.close();
                var writer = toutput.writer();
                try writer.writeAll(info_buffer[0..info_stream.buffer.pos]);
            }
        }
    }
}
