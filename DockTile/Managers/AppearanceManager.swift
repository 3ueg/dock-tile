//
//  This file no longer defines AppearanceManager/AppearanceMode (deleted 2026-09-01 — dead code
//  embodying the superseded dark-mode design of a grey background + raw-tint glyph, replaced by
//  the current darkened-own-tint treatment, and an overload trap: `TintColor.colors(for:)` /
//  `.nsColors(for:)` existed for both `AppearanceMode` and `IconStyle`, both with a `.dark`
//  case, so a type-inference accident could silently resurrect the old rendering). What remains
//  below — the `NSColor` hex initialiser and the `Color(_ nsColor:)` bridge — is live code
//  the current icon rendering depends on. (`NSColor.lighterShade(by:)` was deleted with zero
//  callers; `Color.lighterShade(by:)` in ColorExtensions.swift is the live one.)
//  Colour roles now come from `TilePalette`; the old
//  `darkenedForDarkMode` / `liftedForDarkGlyph` helpers and `TintColor.nsColorTop/Bottom/nsColor`
//  were deleted (zero callers) when the adapters were routed through it.
//
import SwiftUI
import AppKit

// MARK: - NSColor Extensions

extension NSColor {
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
