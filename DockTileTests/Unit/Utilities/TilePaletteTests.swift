//  TilePaletteTests.swift — the colour each renderer draws, per background × style × icon type.
import Foundation
import Testing
@testable import Dock_Tile

@Suite("TilePalette roles")
struct TilePaletteTests {
    private let presets = TintColor.allPresets
    private let customs: [TintColor] = [.custom("#FFFFFF"), .custom("#000000"), .custom("#5F00FF"), .custom("#FFCC00")]

    private func q(_ c: SRGB) -> SRGB {
        SRGB(r: (c.r * 255).rounded() / 255, g: (c.g * 255).rounded() / 255, b: (c.b * 255).rounded() / 255)
    }

    @Test("Mono Light: white→#EFEFF1 tile, symbol clears 3.0 against the darker stop")
    func monoLight() throws {
        for tint in presets + customs {
            for type in [IconType.sfSymbol, .emoji] {
                let r = TilePalette.resolve(tint: tint, background: .mono, style: .defaultStyle, iconType: type)
                #expect(r.top == SRGB(hex: "#FFFFFF"))
                #expect(r.bottom == SRGB(hex: "#EFEFF1"))
                #expect(ToneMap.contrastRatio(q(r.glyph), r.bottom) >= ToneMap.floor, "\(tint)")
            }
        }
    }

    @Test("Dark symbol (Colour or Mono): neutral near-black, SHADED symbol bottom clears 3.0")
    func darkSymbol() throws {
        let shade = try #require(IconDepthMetrics.glyphBottomDarken(style: .dark, iconType: .sfSymbol, nominalSize: 1024))
        for bg in TileBackground.allCases {
            for tint in presets + customs {
                let r = TilePalette.resolve(tint: tint, background: bg, style: .dark, iconType: .sfSymbol)
                #expect(r.top == SRGB(hex: TintColor.darkNeutralTopHex))
                #expect(r.bottom == SRGB(hex: TintColor.darkNeutralBottomHex))
                let shaded = q(r.glyph).darkened(by: Double(shade))
                #expect(ToneMap.contrastRatio(shaded, r.top) >= ToneMap.floor, "\(bg) \(tint)")
            }
        }
    }

    @Test("Mono Dark emoji: neutral near-black (not the darkened tint)")
    func monoDarkEmoji() {
        let r = TilePalette.resolve(tint: .blue, background: .mono, style: .dark, iconType: .emoji)
        #expect(r.top == SRGB(hex: TintColor.darkNeutralTopHex))
    }

    @Test("Colour Dark emoji keeps the darkened-own-tint background (brightness caps 0.22 / 0.13)")
    func colourDarkEmoji() throws {
        let r = TilePalette.resolve(tint: .blue, background: .colour, style: .dark, iconType: .emoji)
        #expect(abs(max(r.top.r, r.top.g, r.top.b) - 0.22) < 1e-9)
        #expect(abs(max(r.bottom.r, r.bottom.g, r.bottom.b) - 0.13) < 1e-9)
        #expect(r.top.b > r.top.r)   // still blue
    }

    @Test("Colour Default: white symbol clears 3.0 against the fill's lighter top; bottom is darker")
    func colourFill() throws {
        for tint in presets + customs {
            let r = TilePalette.resolve(tint: tint, background: .colour, style: .defaultStyle, iconType: .sfSymbol)
            #expect(r.glyph == .white)
            #expect(ToneMap.contrastRatio(.white, q(r.top)) >= ToneMap.floor, "\(tint)")
            // Never lighter at the bottom; strictly darker for every colour that is not already black
            // (a black custom fill has nowhere darker to go — L clamps at 0).
            #expect(ToneMap.relativeLuminance(r.bottom) <= ToneMap.relativeLuminance(r.top), "\(tint) bottom lighter")
            if tint != .custom("#000000") {
                #expect(ToneMap.relativeLuminance(r.bottom) < ToneMap.relativeLuminance(r.top), "\(tint) gradient is flat")
            }
        }
    }

    @Test("Default style is icon-type independent for every background (symbol and emoji share the fill)")
    func defaultIgnoresIconType() {
        for bg in TileBackground.allCases {
            for tint in presets + customs {
                let s = TilePalette.resolve(tint: tint, background: bg, style: .defaultStyle, iconType: .sfSymbol)
                let e = TilePalette.resolve(tint: tint, background: bg, style: .defaultStyle, iconType: .emoji)
                #expect(s.top == e.top && s.bottom == e.bottom, "\(bg) \(tint)")
            }
        }
    }

    @Test("Clear and Tinted ignore background and tint", arguments: [IconStyle.clear, .tinted])
    func greyscaleStylesUnchanged(_ style: IconStyle) {
        let a = TilePalette.resolve(tint: .orange, background: .colour, style: style, iconType: .sfSymbol)
        let b = TilePalette.resolve(tint: .purple, background: .mono, style: style, iconType: .emoji)
        #expect(a == b)
        if style == .tinted {
            #expect(a.glyph == .white)
            #expect(a.top == SRGB(hex: "#8E8E93") && a.bottom == SRGB(hex: "#636366"))
        } else {
            #expect(a.top == SRGB(hex: "#F0F0F2") && a.bottom == SRGB(hex: "#E0E0E4") && a.glyph == SRGB(hex: "#6E6E73"))
        }
    }

    @Test("A malformed custom hex renders the grey preset's tones, never black")
    func malformedCustomFallsBackToGrey() {
        for bad in ["oops", "#12", ""] {
            #expect(TintColor.custom(bad).baseRGB == TintColor.gray.baseRGB, "\(bad)")
        }
    }

    @Test("fillWasDeepened: orange moves, blue (already 4:1 on white) does not")
    func deepenedFlag() {
        #expect(TilePalette.fillWasDeepened(tint: .orange))
        #expect(!TilePalette.fillWasDeepened(tint: .blue))
    }

    @Test("Preset hex tables back the SwiftUI colours (one table, no copies)")
    func presetHexIsTheSource() {
        for p in TintColor.PresetColor.allCases {
            #expect(TintColor.preset(p).baseRGB == SRGB(hex: p.baseHex))
            #expect(TintColor.preset(p).lightRGB == SRGB(hex: p.lightHex))
        }
    }
}
