const std = @import("std");
const buffered_stream_source = @import("../src/buffered_stream_source.zig");
const helpers = @import("helpers.zig");

const TestFileContents = "0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ";

test "BufferedStreamReader should read and seek properly with a file" {
    const TestFilename = "buffered_stream_reader_test.dat";

    var temp_folder = std.testing.tmpDir(.{});
    defer temp_folder.cleanup();

    try temp_folder.dir.writeFile(TestFilename, TestFileContents);

    var read_file = try temp_folder.dir.openFile(TestFilename, .{});
    defer read_file.close();

    var stream_source = std.io.StreamSource{ .file = read_file };
    var buffered_stream = buffered_stream_source.bufferedStreamSourceReaderWithSize(4, &stream_source);

    const reader = buffered_stream.reader();
    const seek_stream = buffered_stream.seekableStream();

    const read_inside_buffer = try reader.readBytesNoEof(3);
    try helpers.expectEq(try seek_stream.getPos(), 3);
    try helpers.expectEqSlice(u8, read_inside_buffer[0..], TestFileContents[0..3]);

    try seek_stream.seekTo(0);

    const read_beginning_again = try reader.readBytesNoEof(3);
    try helpers.expectEqSlice(u8, read_inside_buffer[0..], read_beginning_again[0..]);

    try seek_stream.seekBy(-3);
    try helpers.expectEq(try seek_stream.getPos(), 0);

    try seek_stream.seekBy(5);
    try helpers.expectEq(try seek_stream.getPos(), 5);

    try seek_stream.seekBy(1);
    try helpers.expectEq(try seek_stream.getPos(), 6);

    const end_pos = try seek_stream.getEndPos();
    try helpers.expectEq(end_pos, 36);

    const read_remaining = try reader.readBytesNoEof(30);
    try helpers.expectEq(try seek_stream.getPos(), try seek_stream.getEndPos());
    try helpers.expectEqSlice(u8, read_remaining[0..], TestFileContents[6..]);
}

test "BufferedStreamWriter should read and seek properly with a file" {
    const TestFilename = "buffered_stream_writer_test.dat";

    const DummyThreeBytes = "abc";

    var temp_folder = std.testing.tmpDir(.{});
    defer temp_folder.cleanup();

    {
        var write_file = try temp_folder.dir.createFile(TestFilename, .{});
        defer write_file.close();

        var stream_source = std.io.StreamSource{ .file = write_file };
        var buffered_stream = buffered_stream_source.bufferedStreamSourceWriterWithSize(4, &stream_source);

        const writer = buffered_stream.writer();
        const seek_stream = buffered_stream.seekableStream();

        _ = try writer.write(TestFileContents[0..3]);
        try helpers.expectEq(try seek_stream.getPos(), 3);

        try seek_stream.seekBy(-3);

        _ = try writer.write(DummyThreeBytes[0..]);
        try helpers.expectEq(try seek_stream.getPos(), 3);

        _ = try writer.write(TestFileContents[3..]);
    }

    var read_file = try temp_folder.dir.openFile(TestFilename, .{});
    defer read_file.close();

    const reader = read_file.reader();
    var read_contents = try reader.readAllAlloc(std.testing.allocator, 128);
    defer std.testing.allocator.free(read_contents);

    try helpers.expectEqSlice(u8, read_contents[0..3], DummyThreeBytes[0..]);
    try helpers.expectEqSlice(u8, read_contents[3..], TestFileContents[3..]);
}
