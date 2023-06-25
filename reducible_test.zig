const std = @import("std");
const TestFunction = struct {
    const Callback = *const fn (usize) void;
    const DrawCallback = *const fn (usize) void;
    text: DataWrapperString = .{ .value = "" },

    pub usingnamespace Everything(TestFunction);
};

pub fn Everything(comptime T: type) type {
    return struct {
        pub const Config = GenerateConfigStruct(T);
    };
}

pub fn GenerateConfigStruct(comptime T: type) type {
    // TODO: .onclick = &.{ handlerOne, handlerTwo }, for other event handlers
    comptime {
        var config_fields: []const std.builtin.Type.StructField = &.{};
        iterateFields(&config_fields, T);

        const default_value: ?T.Callback = null;
        config_fields = config_fields ++ &[1]std.builtin.Type.StructField{.{
            .name = "onclick",
            .type = ?T.Callback,
            .default_value = @ptrCast(?*const anyopaque, &default_value),
            .is_comptime = false,
            .alignment = @alignOf(?T.Callback),
        }};
        config_fields = config_fields ++ &[1]std.builtin.Type.StructField{.{
            .name = "ondraw",
            .type = ?T.DrawCallback,
            .default_value = @ptrCast(?*const anyopaque, &default_value),
            .is_comptime = false,
            .alignment = @alignOf(?T.DrawCallback),
        }};

        const t = @Type(.{ .Struct = .{
            .layout = .Auto,
            .backing_integer = null,
            .fields = config_fields,
            .decls = &.{},
            .is_tuple = false,
        } });
        return t;
    }
}

fn DataWrapper(comptime T: type) type {
    const DataWrapperStr = struct {
        value: T,
        const ValueType = T;
        const Self = @This();

        pub fn getUnsafe(self: *const Self) T {
            return self.value;
        }
    };
    return DataWrapperStr;
}
const DataWrapperString = DataWrapper([]const u8);

fn iterateFields(comptime config_fields: *[]const std.builtin.Type.StructField, comptime T: type) void {
    for (std.meta.fields(T)) |field| {
        const FieldType = field.type;
        const default_value = if (field.default_value) |default| @ptrCast(*const FieldType, @alignCast(@alignOf(FieldType), default)).getUnsafe() else null;
        const has_default_value = field.default_value != null;

        config_fields.* = config_fields.* ++ &[1]std.builtin.Type.StructField{.{
            .name = field.name,
            .type = FieldType.ValueType,
            .default_value = if (has_default_value) @ptrCast(?*const anyopaque, @alignCast(1, &default_value)) else null,
            .is_comptime = false,
            .alignment = @alignOf(FieldType.ValueType),
        }};
    }
}

fn testFunction(config: TestFunction.Config) TestFunction {
    return TestFunction{ .text = .{ .value = config.text } };
}

pub fn main() !void {
    var t = testFunction(.{ .text = "test" });
    _ = t;
    var a = testFunction(.{});
    _ = a;
}
