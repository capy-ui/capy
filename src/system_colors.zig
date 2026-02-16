//! Semantic color system that adapts to the platform's light/dark mode.
//!
//! Canvas-drawn widgets should use these instead of hardcoded RGB values
//! so they look correct in both light and dark mode.
//!
//! Color values are based on Apple Human Interface Guidelines and
//! Material Design, adapted for cross-platform consistency.

const Color = @import("color.zig").Color;
const backend = @import("backend.zig");

/// Returns true if the system is currently in dark mode.
pub fn isDarkMode() bool {
    return backend.isDarkMode();
}

// ── Backgrounds ──────────────────────────────────────────────────────

/// Primary window/view background.
pub fn background() Color {
    return if (isDarkMode())
        Color.fromRGB(0x1C, 0x1C, 0x1E)
    else
        Color.fromRGB(0xFF, 0xFF, 0xFF);
}

/// Secondary background (sidebar, grouped sections, card surfaces).
pub fn secondaryBackground() Color {
    return if (isDarkMode())
        Color.fromRGB(0x2C, 0x2C, 0x2E)
    else
        Color.fromRGB(0xF2, 0xF2, 0xF7);
}

/// Tertiary background (nested elements, elevated surfaces).
pub fn tertiaryBackground() Color {
    return if (isDarkMode())
        Color.fromRGB(0x3A, 0x3A, 0x3C)
    else
        Color.fromRGB(0xFF, 0xFF, 0xFF);
}

// ── Text / Labels ────────────────────────────────────────────────────

/// Primary text color.
pub fn label() Color {
    return if (isDarkMode())
        Color.fromRGB(0xFF, 0xFF, 0xFF)
    else
        Color.fromRGB(0x00, 0x00, 0x00);
}

/// Secondary text color (subtitles, captions).
pub fn secondaryLabel() Color {
    return if (isDarkMode())
        Color.fromRGB(0xAA, 0xAA, 0xB0)
    else
        Color.fromRGB(0x3C, 0x3C, 0x43);
}

/// Disabled / placeholder text.
pub fn tertiaryLabel() Color {
    return if (isDarkMode())
        Color.fromRGB(0x63, 0x63, 0x6B)
    else
        Color.fromRGB(0xAA, 0xAA, 0xAA);
}

// ── Controls ─────────────────────────────────────────────────────────

/// Control background (buttons, segmented controls, menu buttons).
pub fn controlBackground() Color {
    return if (isDarkMode())
        Color.fromRGB(0x3A, 0x3A, 0x3C)
    else
        Color.fromRGB(0xE8, 0xE8, 0xE8);
}

/// Selected segment / active control surface.
pub fn controlAccentBackground() Color {
    return if (isDarkMode())
        Color.fromRGB(0x54, 0x54, 0x58)
    else
        Color.fromRGB(0xFF, 0xFF, 0xFF);
}

/// Control border / outline.
pub fn controlBorder() Color {
    return if (isDarkMode())
        Color.fromRGB(0x54, 0x54, 0x58)
    else
        Color.fromRGB(0xCC, 0xCC, 0xCC);
}

// ── Separators ───────────────────────────────────────────────────────

/// Separator line between content sections.
pub fn separator() Color {
    return if (isDarkMode())
        Color.fromRGB(0x54, 0x54, 0x58)
    else
        Color.fromRGB(0xCC, 0xCC, 0xCC);
}

// ── Interactive states ───────────────────────────────────────────────

/// Hover highlight on interactive rows/items.
pub fn hoverBackground() Color {
    return if (isDarkMode())
        Color.fromARGB(0x30, 0xFF, 0xFF, 0xFF)
    else
        Color.fromARGB(0x18, 0x00, 0x00, 0x00);
}

/// Selected row / item background.
pub fn selectedBackground() Color {
    return if (isDarkMode())
        Color.fromRGB(0x2C, 0x3E, 0x55)
    else
        Color.fromRGB(0xCC, 0xDD, 0xEE);
}

// ── Accent ───────────────────────────────────────────────────────────

/// Accent / tint color for primary actions.
pub fn accent() Color {
    return if (isDarkMode())
        Color.fromRGB(0x0A, 0x84, 0xFF)
    else
        Color.fromRGB(0x33, 0x7A, 0xB7);
}

/// Accent text (white-on-accent).
pub fn accentLabel() Color {
    return Color.fromRGB(0xFF, 0xFF, 0xFF);
}

/// Accent hover / pressed state.
pub fn accentHover() Color {
    return if (isDarkMode())
        Color.fromRGB(0x40, 0x9C, 0xFF)
    else
        Color.fromRGB(0x28, 0x6E, 0xA8);
}

// ── Table / List ─────────────────────────────────────────────────────

/// Table header background.
pub fn tableHeader() Color {
    return if (isDarkMode())
        Color.fromRGB(0x2C, 0x2C, 0x2E)
    else
        Color.fromRGB(0xF0, 0xF0, 0xF0);
}

/// Even row background.
pub fn tableRowEven() Color {
    return background();
}

/// Odd row background (alternating stripe).
pub fn tableRowOdd() Color {
    return if (isDarkMode())
        Color.fromRGB(0x24, 0x24, 0x26)
    else
        Color.fromRGB(0xF8, 0xF8, 0xF8);
}

// ── Overlay / Modal ──────────────────────────────────────────────────

/// Scrim behind modal dialogs / flyout panels.
pub fn scrim() Color {
    return if (isDarkMode())
        Color.fromARGB(0x80, 0x00, 0x00, 0x00)
    else
        Color.fromARGB(0x80, 0x00, 0x00, 0x00);
}

/// Shadow / drop-shadow color.
pub fn shadow() Color {
    return Color.fromARGB(0x30, 0x00, 0x00, 0x00);
}

// ── Progress / Track ─────────────────────────────────────────────────

/// Hovered table row (solid, for direct row background painting).
pub fn tableRowHovered() Color {
    return if (isDarkMode())
        Color.fromRGB(0x38, 0x38, 0x3A)
    else
        Color.fromRGB(0xF0, 0xF5, 0xFA);
}

/// Progress bar / slider track background.
pub fn trackBackground() Color {
    return if (isDarkMode())
        Color.fromRGB(0x3A, 0x3A, 0x3C)
    else
        Color.fromRGB(0xE0, 0xE0, 0xE0);
}
