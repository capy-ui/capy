const std = @import("std");
const math = std.math;
const Allocator = std.mem.Allocator;
const PixelFormat = @import("pixel_format.zig").PixelFormat;
const TypeInfo = std.builtin.TypeInfo;

pub inline fn toIntColor(comptime T: type, value: f32) T {
    const float_value = @round(value * @intToFloat(f32, math.maxInt(T)));
    return @floatToInt(T, math.clamp(float_value, math.minInt(T), math.maxInt(T)));
}

pub inline fn scaleToIntColor(comptime T: type, value: anytype) T {
    const ValueT = @TypeOf(value);
    if (ValueT == comptime_int) return @as(T, value);
    const ValueTypeInfo = @typeInfo(ValueT);
    if (ValueTypeInfo != .Int or ValueTypeInfo.Int.signedness != .unsigned) {
        @compileError("scaleToInColor only accepts unsigned integers as values. Got " ++ @typeName(ValueT) ++ ".");
    }
    const cur_value_bits = @bitSizeOf(ValueT);
    const new_value_bits = @bitSizeOf(T);
    if (cur_value_bits > new_value_bits) {
        return @truncate(T, value >> (cur_value_bits - new_value_bits));
    } else if (cur_value_bits < new_value_bits) {
        const cur_value_max = math.maxInt(ValueT);
        const new_value_max = math.maxInt(T);
        return @truncate(T, (@as(u32, value) * new_value_max + cur_value_max / 2) / cur_value_max);
    } else return @as(T, value);
}

pub inline fn toF32Color(value: anytype) f32 {
    return @intToFloat(f32, value) / @intToFloat(f32, math.maxInt(@TypeOf(value)));
}

pub const Colorf32 = extern struct {
    r: f32 align(1),
    g: f32 align(1),
    b: f32 align(1),
    a: f32 align(1) = 1.0,

    const Self = @This();

    pub fn initRgb(r: f32, g: f32, b: f32) Self {
        return Self{
            .r = r,
            .g = g,
            .b = b,
        };
    }

    pub fn initRgba(r: f32, g: f32, b: f32, a: f32) Self {
        return Self{
            .r = r,
            .g = g,
            .b = b,
            .a = a,
        };
    }

    pub fn fromU32Rgba(value: u32) Self {
        return Self{
            .r = toF32Color(@truncate(u8, value >> 24)),
            .g = toF32Color(@truncate(u8, value >> 16)),
            .b = toF32Color(@truncate(u8, value >> 8)),
            .a = toF32Color(@truncate(u8, value)),
        };
    }

    pub fn toU32Rgba(self: Self) u32 {
        return @as(u32, toIntColor(u8, self.r)) << 24 |
            @as(u32, toIntColor(u8, self.g)) << 16 |
            @as(u32, toIntColor(u8, self.b)) << 8 |
            @as(u32, toIntColor(u8, self.a));
    }

    pub fn fromU64Rgba(value: u64) Self {
        return Self{
            .r = toF32Color(@truncate(u16, value >> 48)),
            .g = toF32Color(@truncate(u16, value >> 32)),
            .b = toF32Color(@truncate(u16, value >> 16)),
            .a = toF32Color(@truncate(u16, value)),
        };
    }

    pub fn toU64Rgba(self: Self) u64 {
        return @as(u64, toIntColor(u16, self.r)) << 48 |
            @as(u64, toIntColor(u16, self.g)) << 32 |
            @as(u64, toIntColor(u16, self.b)) << 16 |
            @as(u64, toIntColor(u16, self.a));
    }

    pub fn toPremultipliedAlpha(self: Self) Self {
        return Self{
            .r = self.r * self.a,
            .g = self.g * self.a,
            .b = self.b * self.a,
            .a = self.a,
        };
    }

    pub fn toRgba(self: Self, comptime T: type) RgbaColor(T) {
        return .{
            .r = toIntColor(T, self.r),
            .g = toIntColor(T, self.g),
            .b = toIntColor(T, self.b),
            .a = toIntColor(T, self.a),
        };
    }

    pub fn toRgba32(self: Self) Rgba32 {
        return self.toRgba(u8);
    }

    pub fn toRgba64(self: Self) Rgba64 {
        return self.toRgba(u16);
    }

    pub fn toArray(self: Self) [4]f32 {
        return @bitCast([4]f32, self);
    }

    pub fn fromArray(value: [4]f32) Self {
        return @bitCast(Self, value);
    }
};

fn isAll8BitColor(comptime red_type: type, comptime green_type: type, comptime blue_type: type, comptime alpha_type: type) bool {
    return red_type == u8 and green_type == u8 and blue_type == u8 and (alpha_type == u8 or alpha_type == void);
}

fn RgbMethods(comptime Self: type) type {
    const has_alpha_type = @hasField(Self, "a");

    return struct {
        const RedT = std.meta.fieldInfo(Self, .r).field_type;
        const GreenT = std.meta.fieldInfo(Self, .g).field_type;
        const BlueT = std.meta.fieldInfo(Self, .b).field_type;
        const AlphaT = if (has_alpha_type) std.meta.fieldInfo(Self, .a).field_type else void;

        pub fn initRgb(r: RedT, g: GreenT, b: BlueT) Self {
            return Self{
                .r = r,
                .g = g,
                .b = b,
            };
        }

        pub fn toColorf32(self: Self) Colorf32 {
            return Colorf32{
                .r = toF32Color(self.r),
                .g = toF32Color(self.g),
                .b = toF32Color(self.b),
                .a = if (has_alpha_type) toF32Color(self.a) else 1.0,
            };
        }

        pub fn fromU32Rgba(value: u32) Self {
            var res = Self{
                .r = scaleToIntColor(RedT, @truncate(u8, value >> 24)),
                .g = scaleToIntColor(GreenT, @truncate(u8, value >> 16)),
                .b = scaleToIntColor(BlueT, @truncate(u8, value >> 8)),
            };
            if (has_alpha_type) {
                res.a = scaleToIntColor(AlphaT, @truncate(u8, value));
            }
            return res;
        }

        pub fn fromU32Rgb(value: u32) Self {
            return Self{
                .r = scaleToIntColor(RedT, @truncate(u8, value >> 16)),
                .g = scaleToIntColor(GreenT, @truncate(u8, value >> 8)),
                .b = scaleToIntColor(BlueT, @truncate(u8, value)),
            };
        }

        pub fn fromU64Rgba(value: u64) Self {
            var res = Self{
                .r = scaleToIntColor(RedT, @truncate(u16, value >> 48)),
                .g = scaleToIntColor(GreenT, @truncate(u16, value >> 32)),
                .b = scaleToIntColor(BlueT, @truncate(u16, value >> 16)),
            };
            if (has_alpha_type) {
                res.a = scaleToIntColor(AlphaT, @truncate(u16, value));
            }
            return res;
        }

        pub fn fromU64Rgb(value: u64) Self {
            return Self{
                .r = scaleToIntColor(RedT, @truncate(u16, value >> 32)),
                .g = scaleToIntColor(GreenT, @truncate(u16, value >> 16)),
                .b = scaleToIntColor(BlueT, @truncate(u16, value)),
            };
        }

        // Only enable fromHtmlHex when all color component type are u8
        pub usingnamespace if (isAll8BitColor(RedT, GreenT, BlueT, AlphaT))
            struct {
                pub fn fromHtmlHex(hex_string: []const u8) !Self {
                    if (hex_string.len == 0) {
                        return error.InvalidHtmlHexString;
                    }

                    if (hex_string[0] != '#') {
                        return error.InvalidHtmlHexString;
                    }

                    if (has_alpha_type) {
                        if (hex_string.len != 4 and hex_string.len != 7 and hex_string.len != 5 and hex_string.len != 9) {
                            return error.InvalidHtmlHexString;
                        }
                    } else {
                        if (hex_string.len != 4 and hex_string.len != 7) {
                            return error.InvalidHtmlHexString;
                        }
                    }

                    if (hex_string.len == 7) {
                        var storage: [3]u8 = undefined;
                        const output = std.fmt.hexToBytes(storage[0..], hex_string[1..]) catch {
                            return error.InvalidHtmlHexString;
                        };

                        return Self{
                            .r = output[0],
                            .g = output[1],
                            .b = output[2],
                        };
                    } else if (has_alpha_type and hex_string.len == 9) {
                        var storage: [4]u8 = undefined;
                        const output = std.fmt.hexToBytes(storage[0..], hex_string[1..]) catch {
                            return error.InvalidHtmlHexString;
                        };

                        return Self{
                            .r = output[0],
                            .g = output[1],
                            .b = output[2],
                            .a = output[3],
                        };
                    } else if (hex_string.len == 4) {
                        const red_digit = std.fmt.charToDigit(hex_string[1], 16) catch {
                            return error.InvalidHtmlHexString;
                        };
                        const green_digit = std.fmt.charToDigit(hex_string[2], 16) catch {
                            return error.InvalidHtmlHexString;
                        };
                        const blue_digit = std.fmt.charToDigit(hex_string[3], 16) catch {
                            return error.InvalidHtmlHexString;
                        };

                        return Self{
                            .r = red_digit | (red_digit << 4),
                            .g = green_digit | (green_digit << 4),
                            .b = blue_digit | (blue_digit << 4),
                        };
                    } else if (has_alpha_type and hex_string.len == 5) {
                        const red_digit = std.fmt.charToDigit(hex_string[1], 16) catch {
                            return error.InvalidHtmlHexString;
                        };
                        const green_digit = std.fmt.charToDigit(hex_string[2], 16) catch {
                            return error.InvalidHtmlHexString;
                        };
                        const blue_digit = std.fmt.charToDigit(hex_string[3], 16) catch {
                            return error.InvalidHtmlHexString;
                        };
                        const alpha_digit = std.fmt.charToDigit(hex_string[4], 16) catch {
                            return error.InvalidHtmlHexString;
                        };

                        return Self{
                            .r = red_digit | (red_digit << 4),
                            .g = green_digit | (green_digit << 4),
                            .b = blue_digit | (blue_digit << 4),
                            .a = alpha_digit | (alpha_digit << 4),
                        };
                    } else {
                        return error.InvalidHtmlHexString;
                    }
                }
            }
        else
            struct {};

        pub fn toU32Rgba(self: Self) u32 {
            return @as(u32, scaleToIntColor(u8, self.r)) << 24 |
                @as(u32, scaleToIntColor(u8, self.g)) << 16 |
                @as(u32, scaleToIntColor(u8, self.b)) << 8 |
                if (@hasField(Self, "a")) scaleToIntColor(u8, self.a) else 0xff;
        }

        pub fn toU32Rgb(self: Self) u32 {
            return @as(u32, scaleToIntColor(u8, self.r)) << 16 |
                @as(u32, scaleToIntColor(u8, self.g)) << 8 |
                scaleToIntColor(u8, self.b);
        }

        pub fn toU64Rgba(self: Self) u64 {
            return @as(u64, scaleToIntColor(u16, self.r)) << 48 |
                @as(u64, scaleToIntColor(u16, self.g)) << 32 |
                @as(u64, scaleToIntColor(u16, self.b)) << 16 |
                if (@hasField(Self, "a")) scaleToIntColor(u16, self.a) else 0xffff;
        }

        pub fn toU64Rgb(self: Self) u64 {
            return @as(u64, scaleToIntColor(u16, self.r)) << 32 |
                @as(u64, scaleToIntColor(u16, self.g)) << 16 |
                scaleToIntColor(u16, self.b);
        }
    };
}

fn RgbaMethods(comptime Self: type) type {
    return struct {
        const T = std.meta.fieldInfo(Self, .r).field_type;
        const comp_bits = @typeInfo(T).Int.bits;

        pub fn initRgba(r: T, g: T, b: T, a: T) Self {
            return Self{
                .r = r,
                .g = g,
                .b = b,
                .a = a,
            };
        }

        pub fn toPremultipliedAlpha(self: Self) Self {
            const max = math.maxInt(T);
            return Self{
                .r = @truncate(T, (@as(u32, self.r) * self.a + max / 2) / max),
                .g = @truncate(T, (@as(u32, self.g) * self.a + max / 2) / max),
                .b = @truncate(T, (@as(u32, self.b) * self.a + max / 2) / max),
                .a = self.a,
            };
        }
    };
}

fn RgbColor(comptime T: type) type {
    return extern struct {
        r: T align(1),
        g: T align(1),
        b: T align(1),

        pub usingnamespace RgbMethods(@This());
    };
}

// Rgb555
// OpenGL: GL_RGB5
// Vulkan: VK_FORMAT_R5G6B5_UNORM_PACK16
// Direct3D/DXGI: n/a
pub const Rgb555 = packed struct {
    r: u5,
    g: u5,
    b: u5,

    pub usingnamespace RgbMethods(@This());
};

// Rgb565
// OpenGL: n/a
// Vulkan: n/a
// Direct3D/DXGI: n/a
pub const Rgb565 = packed struct {
    r: u5,
    g: u6,
    b: u5,

    pub usingnamespace RgbMethods(@This());
};

fn RgbaColor(comptime T: type) type {
    return extern struct {
        r: T align(1),
        g: T align(1),
        b: T align(1),
        a: T align(1) = math.maxInt(T),

        pub usingnamespace RgbMethods(@This());
        pub usingnamespace RgbaMethods(@This());
    };
}

// Rgb24
// OpenGL: GL_RGB
// Vulkan: VK_FORMAT_R8G8B8_UNORM
// Direct3D/DXGI: n/a
pub const Rgb24 = RgbColor(u8);

// Rgba32
// OpenGL: GL_RGBA
// Vulkan: VK_FORMAT_R8G8B8A8_UNORM
// Direct3D/DXGI: DXGI_FORMAT_R8G8B8A8_UNORM
pub const Rgba32 = RgbaColor(u8);

// Rgb48
// OpenGL: GL_RGB16
// Vulkan: VK_FORMAT_R16G16B16_UNORM
// Direct3D/DXGI: n/a
pub const Rgb48 = RgbColor(u16);

// Rgba64
// OpenGL: GL_RGBA16
// Vulkan: VK_FORMAT_R16G16B16A16_UNORM
// Direct3D/DXGI: DXGI_FORMAT_R16G16B16A16_UNORM
pub const Rgba64 = RgbaColor(u16);

fn BgrColor(comptime T: type) type {
    return extern struct {
        b: T align(1),
        g: T align(1),
        r: T align(1),

        pub usingnamespace RgbMethods(@This());
    };
}

fn BgraColor(comptime T: type) type {
    return extern struct {
        b: T align(1),
        g: T align(1),
        r: T align(1),
        a: T = math.maxInt(T),

        pub usingnamespace RgbMethods(@This());
        pub usingnamespace RgbaMethods(@This());
    };
}

// Bgr24
// OpenGL: GL_BGR
// Vulkan: VK_FORMAT_B8G8R8_UNORM
// Direct3D/DXGI: n/a
pub const Bgr24 = BgrColor(u8);

// Bgra32
// OpenGL: GL_BGRA
// Vulkan: VK_FORMAT_B8G8R8A8_UNORM
// Direct3D/DXGI: DXGI_FORMAT_B8G8R8A8_UNORM
pub const Bgra32 = BgraColor(u8);

pub fn IndexedStorage(comptime T: type) type {
    return struct {
        palette: []Rgba32,
        indices: []T,

        pub const PaletteSize = 1 << @bitSizeOf(T);

        const Self = @This();

        pub fn init(allocator: Allocator, pixel_count: usize) !Self {
            var res = Self{
                .indices = try allocator.alloc(T, pixel_count),
                .palette = try allocator.alloc(Rgba32, PaletteSize),
            };

            // Since not all palette entries need to be filled we make sure
            // they are all zero at the start.
            std.mem.set(Rgba32, res.palette, Rgba32.initRgba(0, 0, 0, 0));
            return res;
        }

        pub fn deinit(self: Self, allocator: Allocator) void {
            allocator.free(self.palette);
            allocator.free(self.indices);
        }
    };
}

pub const IndexedStorage1 = IndexedStorage(u1);
pub const IndexedStorage2 = IndexedStorage(u2);
pub const IndexedStorage4 = IndexedStorage(u4);
pub const IndexedStorage8 = IndexedStorage(u8);
pub const IndexedStorage16 = IndexedStorage(u16);

pub fn Grayscale(comptime T: type) type {
    return struct {
        value: T,

        const Self = @This();

        pub fn toColorf32(self: Self) Colorf32 {
            const gray = toF32Color(self.value);
            return Colorf32{
                .r = gray,
                .g = gray,
                .b = gray,
                .a = 1.0,
            };
        }
    };
}

pub fn GrayscaleAlpha(comptime T: type) type {
    return struct {
        value: T,
        alpha: T = math.maxInt(T),

        const Self = @This();

        pub fn toColorf32(self: Self) Colorf32 {
            const gray = toF32Color(self.value);
            return Colorf32{
                .r = gray,
                .g = gray,
                .b = gray,
                .a = toF32Color(self.alpha),
            };
        }
    };
}

pub const Grayscale1 = Grayscale(u1);
pub const Grayscale2 = Grayscale(u2);
pub const Grayscale4 = Grayscale(u4);
pub const Grayscale8 = Grayscale(u8);
pub const Grayscale16 = Grayscale(u16);
pub const Grayscale8Alpha = GrayscaleAlpha(u8);
pub const Grayscale16Alpha = GrayscaleAlpha(u16);

pub const PixelStorage = union(PixelFormat) {
    invalid: void,
    indexed1: IndexedStorage1,
    indexed2: IndexedStorage2,
    indexed4: IndexedStorage4,
    indexed8: IndexedStorage8,
    indexed16: IndexedStorage16,
    grayscale1: []Grayscale1,
    grayscale2: []Grayscale2,
    grayscale4: []Grayscale4,
    grayscale8: []Grayscale8,
    grayscale16: []Grayscale16,
    grayscale8Alpha: []Grayscale8Alpha,
    grayscale16Alpha: []Grayscale16Alpha,
    rgb565: []Rgb565,
    rgb555: []Rgb555,
    rgb24: []Rgb24,
    rgba32: []Rgba32,
    bgr24: []Bgr24,
    bgra32: []Bgra32,
    rgb48: []Rgb48,
    rgba64: []Rgba64,
    float32: []Colorf32,

    const Self = @This();

    pub fn init(allocator: Allocator, format: PixelFormat, pixel_count: usize) !Self {
        return switch (format) {
            .invalid => {
                return Self{
                    .invalid = void{},
                };
            },
            .indexed1 => {
                return Self{
                    .indexed1 = try IndexedStorage(u1).init(allocator, pixel_count),
                };
            },
            .indexed2 => {
                return Self{
                    .indexed2 = try IndexedStorage(u2).init(allocator, pixel_count),
                };
            },
            .indexed4 => {
                return Self{
                    .indexed4 = try IndexedStorage(u4).init(allocator, pixel_count),
                };
            },
            .indexed8 => {
                return Self{
                    .indexed8 = try IndexedStorage(u8).init(allocator, pixel_count),
                };
            },
            .indexed16 => {
                return Self{
                    .indexed16 = try IndexedStorage(u16).init(allocator, pixel_count),
                };
            },
            .grayscale1 => {
                return Self{
                    .grayscale1 = try allocator.alloc(Grayscale1, pixel_count),
                };
            },
            .grayscale2 => {
                return Self{
                    .grayscale2 = try allocator.alloc(Grayscale2, pixel_count),
                };
            },
            .grayscale4 => {
                return Self{
                    .grayscale4 = try allocator.alloc(Grayscale4, pixel_count),
                };
            },
            .grayscale8 => {
                return Self{
                    .grayscale8 = try allocator.alloc(Grayscale8, pixel_count),
                };
            },
            .grayscale8Alpha => {
                return Self{
                    .grayscale8Alpha = try allocator.alloc(Grayscale8Alpha, pixel_count),
                };
            },
            .grayscale16 => {
                return Self{
                    .grayscale16 = try allocator.alloc(Grayscale16, pixel_count),
                };
            },
            .grayscale16Alpha => {
                return Self{
                    .grayscale16Alpha = try allocator.alloc(Grayscale16Alpha, pixel_count),
                };
            },
            .rgb24 => {
                return Self{
                    .rgb24 = try allocator.alloc(Rgb24, pixel_count),
                };
            },
            .rgba32 => {
                return Self{
                    .rgba32 = try allocator.alloc(Rgba32, pixel_count),
                };
            },
            .rgb565 => {
                return Self{
                    .rgb565 = try allocator.alloc(Rgb565, pixel_count),
                };
            },
            .rgb555 => {
                return Self{
                    .rgb555 = try allocator.alloc(Rgb555, pixel_count),
                };
            },
            .bgr24 => {
                return Self{
                    .bgr24 = try allocator.alloc(Bgr24, pixel_count),
                };
            },
            .bgra32 => {
                return Self{
                    .bgra32 = try allocator.alloc(Bgra32, pixel_count),
                };
            },
            .rgb48 => {
                return Self{
                    .rgb48 = try allocator.alloc(Rgb48, pixel_count),
                };
            },
            .rgba64 => {
                return Self{
                    .rgba64 = try allocator.alloc(Rgba64, pixel_count),
                };
            },
            .float32 => {
                return Self{
                    .float32 = try allocator.alloc(Colorf32, pixel_count),
                };
            },
        };
    }

    pub fn deinit(self: Self, allocator: Allocator) void {
        switch (self) {
            .invalid => {},
            .indexed1 => |data| data.deinit(allocator),
            .indexed2 => |data| data.deinit(allocator),
            .indexed4 => |data| data.deinit(allocator),
            .indexed8 => |data| data.deinit(allocator),
            .indexed16 => |data| data.deinit(allocator),
            .grayscale1 => |data| allocator.free(data),
            .grayscale2 => |data| allocator.free(data),
            .grayscale4 => |data| allocator.free(data),
            .grayscale8 => |data| allocator.free(data),
            .grayscale8Alpha => |data| allocator.free(data),
            .grayscale16 => |data| allocator.free(data),
            .grayscale16Alpha => |data| allocator.free(data),
            .rgb24 => |data| allocator.free(data),
            .rgba32 => |data| allocator.free(data),
            .rgb565 => |data| allocator.free(data),
            .rgb555 => |data| allocator.free(data),
            .bgr24 => |data| allocator.free(data),
            .bgra32 => |data| allocator.free(data),
            .rgb48 => |data| allocator.free(data),
            .rgba64 => |data| allocator.free(data),
            .float32 => |data| allocator.free(data),
        }
    }

    pub fn len(self: Self) usize {
        return switch (self) {
            .invalid => 0,
            .indexed1 => |data| data.indices.len,
            .indexed2 => |data| data.indices.len,
            .indexed4 => |data| data.indices.len,
            .indexed8 => |data| data.indices.len,
            .indexed16 => |data| data.indices.len,
            .grayscale1 => |data| data.len,
            .grayscale2 => |data| data.len,
            .grayscale4 => |data| data.len,
            .grayscale8 => |data| data.len,
            .grayscale8Alpha => |data| data.len,
            .grayscale16 => |data| data.len,
            .grayscale16Alpha => |data| data.len,
            .rgb24 => |data| data.len,
            .rgba32 => |data| data.len,
            .rgb565 => |data| data.len,
            .rgb555 => |data| data.len,
            .bgr24 => |data| data.len,
            .bgra32 => |data| data.len,
            .rgb48 => |data| data.len,
            .rgba64 => |data| data.len,
            .float32 => |data| data.len,
        };
    }

    pub fn isIndexed(self: Self) bool {
        return switch (self) {
            .indexed1 => true,
            .indexed2 => true,
            .indexed4 => true,
            .indexed8 => true,
            .indexed16 => true,
            else => false,
        };
    }

    pub fn getPalette(self: Self) ?[]Rgba32 {
        return switch (self) {
            .indexed1 => |data| data.palette,
            .indexed2 => |data| data.palette,
            .indexed4 => |data| data.palette,
            .indexed8 => |data| data.palette,
            .indexed16 => |data| data.palette,
            else => null,
        };
    }

    /// Return the pixel data as a const byte slice
    pub fn asBytes(self: Self) []u8 {
        return switch (self) {
            .invalid => &[_]u8{},
            .indexed1 => |data| std.mem.sliceAsBytes(data.indices),
            .indexed2 => |data| std.mem.sliceAsBytes(data.indices),
            .indexed4 => |data| std.mem.sliceAsBytes(data.indices),
            .indexed8 => |data| std.mem.sliceAsBytes(data.indices),
            .indexed16 => |data| std.mem.sliceAsBytes(data.indices),
            .grayscale1 => |data| std.mem.sliceAsBytes(data),
            .grayscale2 => |data| std.mem.sliceAsBytes(data),
            .grayscale4 => |data| std.mem.sliceAsBytes(data),
            .grayscale8 => |data| std.mem.sliceAsBytes(data),
            .grayscale8Alpha => |data| std.mem.sliceAsBytes(data),
            .grayscale16 => |data| std.mem.sliceAsBytes(data),
            .grayscale16Alpha => |data| std.mem.sliceAsBytes(data),
            .rgb24 => |data| std.mem.sliceAsBytes(data),
            .rgba32 => |data| std.mem.sliceAsBytes(data),
            .rgb565 => |data| std.mem.sliceAsBytes(data),
            .rgb555 => |data| std.mem.sliceAsBytes(data),
            .bgr24 => |data| std.mem.sliceAsBytes(data),
            .bgra32 => |data| std.mem.sliceAsBytes(data),
            .rgb48 => |data| std.mem.sliceAsBytes(data),
            .rgba64 => |data| std.mem.sliceAsBytes(data),
            .float32 => |data| std.mem.sliceAsBytes(data),
        };
    }
};

pub const PixelStorageIterator = struct {
    pixels: *const PixelStorage = undefined,
    current_index: usize = 0,
    end: usize = 0,

    const Self = @This();

    pub fn init(pixels: *const PixelStorage) Self {
        return Self{
            .pixels = pixels,
            .end = pixels.len(),
        };
    }

    pub fn next(self: *Self) ?Colorf32 {
        if (self.current_index >= self.end) {
            return null;
        }

        const result: ?Colorf32 = switch (self.pixels.*) {
            .invalid => Colorf32.initRgb(0.0, 0.0, 0.0),
            .indexed1 => |data| data.palette[data.indices[self.current_index]].toColorf32(),
            .indexed2 => |data| data.palette[data.indices[self.current_index]].toColorf32(),
            .indexed4 => |data| data.palette[data.indices[self.current_index]].toColorf32(),
            .indexed8 => |data| data.palette[data.indices[self.current_index]].toColorf32(),
            .indexed16 => |data| data.palette[data.indices[self.current_index]].toColorf32(),
            .grayscale1 => |data| data[self.current_index].toColorf32(),
            .grayscale2 => |data| data[self.current_index].toColorf32(),
            .grayscale4 => |data| data[self.current_index].toColorf32(),
            .grayscale8 => |data| data[self.current_index].toColorf32(),
            .grayscale8Alpha => |data| data[self.current_index].toColorf32(),
            .grayscale16 => |data| data[self.current_index].toColorf32(),
            .grayscale16Alpha => |data| data[self.current_index].toColorf32(),
            .rgb24 => |data| data[self.current_index].toColorf32(),
            .rgba32 => |data| data[self.current_index].toColorf32(),
            .rgb565 => |data| data[self.current_index].toColorf32(),
            .rgb555 => |data| data[self.current_index].toColorf32(),
            .bgr24 => |data| data[self.current_index].toColorf32(),
            .bgra32 => |data| data[self.current_index].toColorf32(),
            .rgb48 => |data| data[self.current_index].toColorf32(),
            .rgba64 => |data| data[self.current_index].toColorf32(),
            .float32 => |data| data[self.current_index],
        };

        self.current_index += 1;
        return result;
    }
};
