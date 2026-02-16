const std = @import("std");
const capy = @import("capy");

// ── Widget references ───────────────────────────────────────────────────────

var name_field: *capy.TextField = undefined;
var email_field: *capy.TextField = undefined;
var notify_checkbox: *capy.CheckBox = undefined;
var lang_dropdown: *capy.Dropdown = undefined;
var volume_slider: *capy.Slider = undefined;
var volume_label: *capy.Label = undefined;
var status_label: *capy.Label = undefined;
var output_label: *capy.Label = undefined;

// Radio buttons for theme selection
const theme_labels = [_][:0]const u8{ "Light", "Dark", "System" };
var theme_radios: [theme_labels.len]*capy.RadioButton = undefined;

// ── Helpers ─────────────────────────────────────────────────────────────────

var volume_buf: [32]u8 = undefined;

fn volumeText(value: f32) [:0]const u8 {
    return std.fmt.bufPrintZ(&volume_buf, "Volume: {d:.0}", .{value}) catch "Volume: ?";
}

fn selectedTheme() [:0]const u8 {
    for (&theme_radios, 0..) |rb, i| {
        if (rb.checked.get()) return theme_labels[i];
    }
    return "Light";
}

var output_buf: [512]u8 = undefined;

fn formatOutput(name: []const u8, email: []const u8, notifications: bool, language: []const u8, theme: [:0]const u8, volume: f32) [:0]const u8 {
    return std.fmt.bufPrintZ(&output_buf, "Received: {{ name: \"{s}\", email: \"{s}\", notify: {}, lang: \"{s}\", theme: \"{s}\", vol: {d:.0} }}", .{ name, email, notifications, language, theme, volume }) catch "Received: (format error)";
}

// ── Callbacks ───────────────────────────────────────────────────────────────

fn onSliderChanged(new_value: f32, _: ?*anyopaque) void {
    volume_label.text.set(volumeText(new_value));
}

fn onSubmit(_: *anyopaque) !void {
    const name = name_field.text.get();
    const email = email_field.text.get();
    const notifications = notify_checkbox.checked.get();
    const language = lang_dropdown.selected_value.get();
    const theme = selectedTheme();
    const volume = volume_slider.value.get();

    std.debug.print(
        \\
        \\── Form Submitted ──────────
        \\  Name:          {s}
        \\  Email:         {s}
        \\  Notifications: {}
        \\  Language:      {s}
        \\  Theme:         {s}
        \\  Volume:        {d:.0}
        \\────────────────────────────
        \\
    , .{ name, email, notifications, language, theme, volume });

    status_label.text.set("Submitted!");
    output_label.text.set(formatOutput(name, email, notifications, language, theme, volume));
}

fn onReset(_: *anyopaque) !void {
    name_field.text.set("");
    email_field.text.set("");
    notify_checkbox.checked.set(false);
    lang_dropdown.selected_index.set(0);
    // Reset radio buttons: select first
    for (&theme_radios, 0..) |rb, i| {
        rb.checked.set(i == 0);
    }
    volume_slider.value.set(50);
    status_label.text.set("(idle)");
    output_label.text.set("");
}

/// Radio button change listener -- enforce mutual exclusivity.
fn onThemeCheckedChanged(new_value: bool, userdata: ?*anyopaque) void {
    if (!new_value) return; // Only act on selection, not deselection
    const selected: *capy.RadioButton = @ptrCast(@alignCast(userdata));
    for (&theme_radios) |rb| {
        if (rb != selected) rb.checked.set(false);
    }
}

// ── Main ────────────────────────────────────────────────────────────────────

pub fn main() !void {
    try capy.init();
    defer capy.deinit();

    // Create widgets
    name_field = capy.textField(.{ .text = "Ada Lovelace" });
    email_field = capy.textField(.{ .text = "ada@example.com" });
    notify_checkbox = capy.checkBox(.{ .label = "Enable notifications" });
    lang_dropdown = capy.dropdown(.{ .values = &.{ "Zig", "Rust", "C", "Elixir", "Other" } });
    volume_slider = capy.slider(.{ .min = 0, .max = 100, .step = 1, .tick_count = 11, .snap_to_ticks = true });
    volume_label = capy.label(.{ .text = volumeText(50) });
    status_label = capy.label(.{ .text = "(idle)" });
    output_label = capy.label(.{ .text = "" });

    // Create radio buttons and wire up mutual exclusivity
    for (&theme_radios, 0..) |*slot, i| {
        slot.* = capy.radioButton(.{ .label = theme_labels[i], .checked = (i == 0) });
    }
    for (&theme_radios) |rb| {
        _ = try rb.checked.addChangeListener(.{ .function = onThemeCheckedChanged, .userdata = rb });
    }

    // Set initial slider value and listen for changes
    volume_slider.value.set(50);
    _ = try volume_slider.value.addChangeListener(.{ .function = onSliderChanged, .userdata = null });

    // Build window
    var window = try capy.Window.init();
    try window.set(
        capy.margin(capy.Rectangle.init(16, 16, 16, 16), capy.column(.{ .spacing = 8 }, .{
            capy.row(.{ .spacing = 8 }, .{
                capy.label(.{ .text = "Name:" }),
                capy.expanded(name_field),
            }),
            capy.row(.{ .spacing = 8 }, .{
                capy.label(.{ .text = "Email:" }),
                capy.expanded(email_field),
            }),
            notify_checkbox,
            capy.row(.{ .spacing = 8 }, .{
                capy.label(.{ .text = "Language:" }),
                lang_dropdown,
            }),
            capy.row(.{ .spacing = 8 }, .{
                capy.label(.{ .text = "Theme:" }),
                theme_radios[0],
                theme_radios[1],
                theme_radios[2],
            }),
            capy.row(.{ .spacing = 8 }, .{
                volume_label,
                capy.expanded(volume_slider),
            }),
            capy.row(.{ .spacing = 8 }, .{
                capy.button(.{ .label = "Submit", .onclick = onSubmit }),
                capy.button(.{ .label = "Reset", .onclick = onReset }),
                status_label,
            }),
            output_label,
        })),
    );

    window.setTitle("Widget Catalog");
    window.setPreferredSize(600, 800);
    window.show();
    capy.runEventLoop();
}
