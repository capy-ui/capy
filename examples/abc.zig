const capy = @import("capy");
const Atom = capy.Atom;

const UserPreference = enum {
    Celsius,
    Fahrenheit,
};
var preference = Atom(UserPreference).of(.Celsius);

pub fn main() !void {
    try capy.init();

    var temperature = Atom(f32).of(297.6); // in °K, the one true unit
    const displayed_temperature = try Atom(f32).derived(
        .{ &preference, &temperature },
        &struct {
            fn a(pref: UserPreference, kelvin: f32) f32 {
                return switch (pref) {
                    .Celsius => kelvin - 273.15,
                    .Fahrenheit => (kelvin - 273.15) * 1.8 + 32,
                };
            }
        }.a,
    );

    var window = try capy.Window.init();
    const format = try capy.FormattedAtom(capy.internal.allocator, "{d:.3}", .{displayed_temperature});
    try window.set(capy.column(.{}, .{
        capy.label(.{})
            .withBinding("text", format),
        capy.button(.{ .label = "set °c", .onclick = @ptrCast(&setCelsius) }),
        capy.button(.{ .label = "set °f", .onclick = @ptrCast(&setFahrenheit) }),
    }));
    window.show();

    capy.runEventLoop();
}

fn setCelsius(button: *capy.Button) anyerror!void {
    _ = button;
    preference.set(.Celsius);
}

fn setFahrenheit(button: *capy.Button) anyerror!void {
    _ = button;
    preference.set(.Fahrenheit);
}
