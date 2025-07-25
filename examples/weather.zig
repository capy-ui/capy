const std = @import("std");
const capy = @import("capy");
const Atom = capy.Atom;

pub usingnamespace capy.cross_platform;

const WeatherData = struct {
    current_temperature: Atom(f32),
    wind_speed: Atom(f32),
    air_pressure: Atom(f32),
};

pub fn main() !void {
    try capy.init();
    defer capy.deinit();

    var arena = std.heap.ArenaAllocator.init(capy.internal.allocator);
    defer arena.deinit();

    var weather: WeatherData = .{
        .current_temperature = Atom(f32).of(17.3),
        .wind_speed = Atom(f32).of(5.2),
        .air_pressure = Atom(f32).of(1015),
    };

    var window = try capy.Window.init();
    try window.set(
        capy.alignment(.{}, capy.column(.{}, .{
            capy.row(.{}, .{
                capy.label(.{ .text = "City Name" }),
                capy.expanded(capy.textField(.{ .text = "Paris, France" })),
            }),
            capy.label(.{ .layout = .{ .font = .{ .size = 20, .family = "IBM Plex Sans" } } })
                .withBinding("text", try capy.FormattedAtom(arena.allocator(), "Current Temperature: {d:.1}°C", .{&weather.current_temperature})),
            capy.row(.{}, .{
                capy.stack(.{
                    capy.rect(.{ .color = capy.Colors.red }),
                    capy.column(.{}, .{
                        capy.label(.{ .text = "wind" }),
                    }),
                }),
                capy.column(.{}, .{
                    capy.label(.{ .text = "humidity", .layout = .{ .font = .{ .family = "IBM Plex Mono", .size = 24 } } }),
                }),
            }),
            capy.row(.{}, .{
                capy.column(.{}, .{
                    capy.label(.{ .text = "air pressure" }),
                }),
                capy.column(.{}, .{
                    capy.label(.{ .text = "uv index" }),
                }),
            }),
        })),
    );
    window.setTitle("Weather");
    window.show();

    weather.current_temperature.animate(window.animation_controller, capy.Easings.InOut, 30.0, 4000);

    capy.runEventLoop();
}
