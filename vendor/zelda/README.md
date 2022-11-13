<img height="32" src="https://upload.wikimedia.org/wikipedia/commons/8/86/Triforce.svg"></img>

zelda [![License](https://img.shields.io/badge/license-MIT-8FBD08.svg)](https://shields.io/) [![Zig](https://img.shields.io/badge/Made_with-Zig-F7A41D.svg)](https://shields.io/)
====
A short and sweet package for native [Zig](https://ziglang.org) HTTP(s) requests.

Zelda uses [hzzp](https://github.com/truemedian/hzzp) and [zig-libressl](https://github.com/haze/zig-libressl) to provide a simple interface for HTTP 1.1 interactions. There is a lot that goes into retrieving data from a remote server, but sometimes you don't want to spend hours mulling over the details, especially for projects where the transport is only a portion of the story of the larger program.

### Capabilities
- [x] HTTP/1.1
- [x] TLS 1.1, TLS 1.2, TLS 1.3
- [x] Simple One-Shot interface for raw bytes & JSON encoded data

### Linking

```zig
const zelda = @import("path/to/zelda/build.zig");

pub fn build(b: *std.build.Builder) !void {
    const exe = ...
    try zelda.link(b, exe, target, mode, use_system_libressl);
}
```

### Example
```zig
/// Extracted from `examples/whats_my_ip/src/main.zig`
const std = @import("std");
const zelda = @import("zelda");

const IPResponse = struct {
    ip: []const u8,
};

pub fn main() anyerror!void {
    var arena = std.heap.ArenaAllocator.init(std.heap.c_allocator);
    defer arena.deinit();

    try printIPFromRaw(arena.allocator());
    try printIPFromJson(arena.allocator());
}

pub fn printIPFromJson(allocator: std.mem.Allocator) !void {
    const response = try zelda.getAndParseResponse(IPResponse, .{ .allocator = allocator }, allocator, "https://api64.ipify.org/?format=json");
    defer std.json.parseFree(IPResponse, response, .{ .allocator = allocator });

    var stdout = std.io.getStdOut().writer();

    try stdout.print("My ip is {s}\n", .{response.ip});
}

pub fn printIPFromRaw(allocator: std.mem.Allocator) !void {
    var response = try zelda.get(allocator, "http://api64.ipify.org/");
    defer response.deinit();

    var stdout = std.io.getStdOut().writer();

    if (response.body) |body|
        try stdout.print("My ip is {s}\n", .{response.body})
    else
        try stdout.writeAll("Failed to receive body from ipify\n");
}
```

Of course, if this library is missing anything, feel free to open a Pull Request or issue 😊

<sup>
Licensed under either of <a href="LICENSE-APACHE">Apache License, Version
2.0</a> or <a href="LICENSE-MIT">MIT license</a> at your option.
</sup>

<br/>

<sub>
Unless you explicitly state otherwise, any contribution intentionally submitted
for inclusion in this package by you, as defined in the Apache-2.0 license, shall
be dual licensed as above, without any additional terms or conditions.
</sub>
