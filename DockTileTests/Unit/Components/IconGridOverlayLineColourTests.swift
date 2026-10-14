import Testing
@testable import Dock_Tile

struct IconGridOverlayLineColourTests {
    private func top(_ t: TintColor) -> SRGB {
        TilePalette.resolve(tint: t, background: .colour, style: .defaultStyle, iconType: .sfSymbol).top
    }

    @Test("Every preset's drawn fill gets the light grid lines")
    func presetsUseLightLines() {
        for preset in TintColor.PresetColor.allCases {
            #expect(!IconGridOverlay.usesDarkLines(forFillTop: top(.preset(preset))), "\(preset)")
        }
    }

    @Test("A custom white tile is deepened by the palette, so it still gets light lines")
    func whiteCustomUsesLightLines() {
        #expect(!IconGridOverlay.usesDarkLines(forFillTop: top(.custom("#FFFFFF"))))
    }

    @Test("The decision itself flips on a genuinely light fill")
    func lightFillUsesDarkLines() {
        #expect(IconGridOverlay.usesDarkLines(forFillTop: .white))
        #expect(!IconGridOverlay.usesDarkLines(forFillTop: SRGB(r: 0, g: 0, b: 0)))
    }
}
