# Zig URI Parser

A small URI parser that parses URIs after [RFC3986](https://tools.ietf.org/html/rfc3986).

## Usage Example

```zig
var link = try uri.parse("https://github.com/MasterQ32/zig-uri");
// link.scheme == "https"
// link.host   == "github.com"
// link.path   == "/MasterQ32/zig-uri"
```