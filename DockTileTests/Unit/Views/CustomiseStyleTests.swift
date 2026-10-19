import Testing
@testable import Dock_Tile

@Suite("Customise style picker seams")
@MainActor   // nested in a View (main-actor) type, like the sibling suites
struct CustomiseStyleTests {
    @Test("The selected Style card follows the face, then the icon type")
    func styleFromConfig() {
        #expect(CustomiseTileView.TileStyle(face: .apps, iconType: .emoji) == .apps)
        #expect(CustomiseTileView.TileStyle(face: .glyph, iconType: .sfSymbol) == .symbol)
        #expect(CustomiseTileView.TileStyle(face: .glyph, iconType: .emoji) == .emoji)
        #expect(CustomiseTileView.TileStyle.allCases == [.apps, .symbol, .emoji])
    }

    @Test("applyStyle: App Preview keeps the glyph behind it; Symbol/Emoji switch the glyph and clear the face")
    func applyStyle() {
        let items = [AppItem(bundleIdentifier: "com.apple.Safari", name: "Safari")]
        let symbol = DockTileConfiguration(name: "W", tintColor: .preset(.red), iconType: .sfSymbol, iconValue: "bolt",
                                           iconFace: .glyph, appItems: items)
        let apps = CustomiseTileView.applyStyle(.apps, to: symbol)
        #expect(apps.iconFace == .apps)
        #expect(apps.iconType == .sfSymbol && apps.iconValue == "bolt" && apps.tintColor == .preset(.red))
        let back = CustomiseTileView.applyStyle(.symbol, to: apps)
        #expect(back.iconFace == .glyph && back.iconValue == "bolt")
        #expect(CustomiseTileView.applyStyle(.symbol, to: symbol) == symbol)

        let emoji = CustomiseTileView.applyStyle(.emoji, to: symbol)
        #expect(emoji.iconFace == .glyph && emoji.iconType == .emoji)
        #expect(emoji.iconValue == ConfigurationDefaults.symbolEmoji && emoji.symbolEmoji == ConfigurationDefaults.symbolEmoji)

        let emojiTile = DockTileConfiguration(name: "E", iconType: .emoji, iconValue: "🎬", iconFace: .glyph)
        let toSymbol = CustomiseTileView.applyStyle(.symbol, to: emojiTile)
        #expect(toSymbol.iconType == .sfSymbol && toSymbol.iconValue == ConfigurationDefaults.iconValue)
        #expect(CustomiseTileView.applyStyle(.emoji, to: emojiTile) == emojiTile)
    }

    @Test("appsSummary: Shown, Arrangement and the note for 0, 1, 4, 9 and 12 apps")
    func appsSummary() {
        typealias S = CustomiseTileView.AppsSummary
        #expect(CustomiseTileView.appsSummary(count: 1) == S(shown: "1 of 1", arrangement: "Fills the Tile", note: "Shows the only app in this tile."))
        #expect(CustomiseTileView.appsSummary(count: 4) == S(shown: "4 of 4", arrangement: "2 × 2", note: "Shows all 4 apps, in tile order."))
        #expect(CustomiseTileView.appsSummary(count: 9) == S(shown: "9 of 9", arrangement: "3 × 3", note: "Shows all 9 apps, in tile order."))
        #expect(CustomiseTileView.appsSummary(count: 12) == S(shown: "9 of 12", arrangement: "3 × 3", note: "Shows the first 9 of 12 apps, in tile order."))
        #expect(CustomiseTileView.appsSummary(count: 0) == S(shown: "0 of 0", arrangement: "—", note: "No apps yet — choose some with Select Apps."))
        #expect(AppStrings.Label.appsGlass == "A glass folder that follows Light and Dark Mode.")
    }

    @Test("appsSummary counts only what the face draws: missing items are skipped")
    func appsSummarySkipsMissing() {
        typealias S = CustomiseTileView.AppsSummary
        let items = ["a", "gone", "c"].map { AppItem(bundleIdentifier: "com.example.\($0)", name: $0) }
        let installed: (AppItem) -> Bool = { $0.name != "gone" }
        #expect(CustomiseTileView.appsSummary(items: items, isInstalled: installed)
                == S(shown: "2 of 2", arrangement: "2 × 2", note: "Shows all 2 apps, in tile order."))
        // Items exist but none is installed: the face draws the glyph, so the card reads as empty.
        #expect(CustomiseTileView.appsSummary(items: items, isInstalled: { _ in false })
                == S(shown: "0 of 0", arrangement: "—", note: "No apps yet — choose some with Select Apps."))
    }

    @Test("inspectorSections: App Preview has no knobs; Symbol/Emoji re-house today's controls")
    func inspectorSections() {
        typealias I = CustomiseTileView.InspectorSection
        for background in TileBackground.allCases { for type in [IconType.sfSymbol, .emoji] {
            #expect(CustomiseTileView.inspectorSections(face: .apps, background: background, iconType: type) == [.stylePicker, .apps])
        } }
        #expect(CustomiseTileView.inspectorSections(face: .glyph, background: .colour, iconType: .sfSymbol)
                == [I.stylePicker, .background, .colour, .iconSize, .iconWeight, .picker])
        #expect(CustomiseTileView.inspectorSections(face: .glyph, background: .mono, iconType: .sfSymbol)
                == [I.stylePicker, .background, .colour, .iconSize, .iconWeight, .picker])
        #expect(CustomiseTileView.inspectorSections(face: .glyph, background: .colour, iconType: .emoji)
                == [I.stylePicker, .background, .colour, .iconSize, .picker])
        #expect(CustomiseTileView.inspectorSections(face: .glyph, background: .mono, iconType: .emoji)
                == [I.stylePicker, .background, .iconSize, .picker])          // Colour card hidden, not disabled
    }
}
