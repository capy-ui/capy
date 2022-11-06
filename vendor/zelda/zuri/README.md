# zuri
[URI](https://en.wikipedia.org/wiki/Uniform_Resource_Identifier) parser written in [Zig](https://ziglang.org/).

## Example
```Zig
const uri = try Uri.parse("https://ziglang.org/documentation/master/#toc-Introduction");
assert(mem.eql(u8, uri.scheme, "https"));
assert(mem.eql(u8, uri.host, "ziglang.org"));
assert(mem.eql(u8, uri.path, "/documentation/master/"));
assert(mem.eql(u8, uri.fragment, "toc-Introduction"));
```

## Zig version
By default the master branch version requires the latest Zig master version.

For Zig 0.6.0 use commit 89ff8258ccd09d0a4cfda649828cc1c45f2b1f8f.