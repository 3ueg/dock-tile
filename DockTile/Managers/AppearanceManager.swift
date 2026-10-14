//
//  This file no longer defines AppearanceManager/AppearanceMode (deleted 2026-09-01 — dead code
//  embodying the superseded dark-mode design of a grey background + raw-tint glyph, replaced by
//  the current darkened-own-tint treatment, and an overload trap: `TintColor.colors(for:)` /
//  `.nsColors(for:)` existed for both `AppearanceMode` and `IconStyle`, both with a `.dark`
//  case, so a type-inference accident could silently resurrect the old rendering). What remains
//  below — the `NSColor` extension (the hex initialiser, `lighterShade(by:)`, ...) — is live code
//  the current icon rendering depends on. Colour roles now come from `TilePalette`; the old
//  `darkenedForDarkMode` / `liftedForDarkGlyph` helpers and `TintColor.nsColorTop/Bottom/nsColor`
//  were deleted (zero callers) when the adapters were routed through it.
//
import SwiftUI
import AppKit

// MARK: - NSColor Extensions

extension NSColor {
    /// Create a lighter shade of the color by increasing brightness
    /// - Parameter amount: How much to lighten (0.0-1.0), e.g., 0.15 = 15% lighter
    /// - Returns: A lighter version of the color with full opacity
    func lighterShade(by amount: CGFloat) -> NSColor {
        // Convert to HSB color space
        var hue: CGFloat = 0
        var saturation: CGFloat = 0
        var brightness: CGFloat = 0
        var alpha: CGFloat = 0

        // Try to get HSB components
        if let hsbColor = self.usingColorSpace(.deviceRGB) {
            hsbColor.getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: &alpha)

            // Increase brightness, decrease saturation slightly for a "lighter" feel
            let newBrightness = min(1.0, brightness + amount)
            let newSaturation = max(0.0, saturation - (amount * 0.3))  // Slightly less saturated

            return NSColor(
                hue: hue,
                saturation: newSaturation,
                brightness: newBrightness,
                alpha: 1.0  // Always full opacity
            )
        }

        // Fallback: return original color if conversion fails
        return self
    }

    convenience init?(hex: String) {
        var hexSanitized = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        hexSanitized = hexSanitized.replacingOccurrences(of: "#", with: "")

        var rgb: UInt64 = 0
        guard Scanner(string: hexSanitized).scanHexInt64(&rgb) else { return nil }

        let r, g, b, a: CGFloat
        switch hexSanitized.count {
        case 6:
            r = CGFloat((rgb & 0xFF0000) >> 16) / 255.0
            g = CGFloat((rgb & 0x00FF00) >> 8) / 255.0
            b = CGFloat(rgb & 0x0000FF) / 255.0
            a = 1.0
        case 8:
            r = CGFloat((rgb & 0xFF000000) >> 24) / 255.0
            g = CGFloat((rgb & 0x00FF0000) >> 16) / 255.0
            b = CGFloat((rgb & 0x0000FF00) >> 8) / 255.0
            a = CGFloat(rgb & 0x000000FF) / 255.0
        default:
            return nil
        }

        self.init(red: r, green: g, blue: b, alpha: a)
    }
}

// MARK: - SwiftUI Color Initializer from NSColor

extension Color {
    init(_ nsColor: NSColor) {
        self.init(nsColor: nsColor)
    }
}
