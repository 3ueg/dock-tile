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

    @Test("App Preview caption: the glass sentence only where the icon follows Light and Dark")
    func appsCaption() {
        let note = "Shows 3 apps."
        #expect(CustomiseTileView.appsCaption(note: note, followsAppearance: true) == note + " " + AppStrings.Label.appsGlass)
        #expect(CustomiseTileView.appsCaption(note: note, followsAppearance: false) == note)
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

    @Test("Switching Symbol → Emoji → Symbol restores the symbol and its size, and the emoji and its size")
    func styleSwitchRemembersEachGlyph() {
        let start = DockTileConfiguration(name: "W", iconType: .sfSymbol, iconValue: "bolt", iconScale: 16,
                                          iconFace: .glyph)
        // First visit to Emoji: nothing saved yet, so the default emoji (size carries over, as before).
        var emoji = CustomiseTileView.applyStyle(.emoji, to: start)
        #expect(emoji.iconType == .emoji && emoji.iconValue == ConfigurationDefaults.symbolEmoji)
        #expect(emoji.savedSymbol == SavedGlyph(value: "bolt", scale: 16, background: .colour, tint: ConfigurationDefaults.tintColor))
        // The user picks an emoji and a size, then goes back to Symbol.
        emoji.iconValue = "🎬"; emoji.symbolEmoji = "🎬"; emoji.iconScale = 21
        let symbol = CustomiseTileView.applyStyle(.symbol, to: emoji)
        #expect(symbol.iconType == .sfSymbol && symbol.iconValue == "bolt" && symbol.iconScale == 16)
        #expect(symbol.symbolEmoji == "bolt")
        #expect(symbol.savedEmoji == SavedGlyph(value: "🎬", scale: 21, background: .colour, tint: ConfigurationDefaults.tintColor))
        // And Emoji again restores the picked emoji, not the default.
        let again = CustomiseTileView.applyStyle(.emoji, to: symbol)
        #expect(again.iconType == .emoji && again.iconValue == "🎬" && again.iconScale == 21 && again.symbolEmoji == "🎬")
    }

    @Test("Colour / Mono is local to Symbol and Emoji: each style restores its own background")
    func backgroundIsPerStyle() {
        let start = DockTileConfiguration(name: "W", iconType: .sfSymbol, iconValue: "bolt", iconScale: 16,
                                          background: .colour, iconFace: .glyph)
        // First visit to Emoji keeps the current background (nothing saved yet); the user picks Mono.
        var emoji = CustomiseTileView.applyStyle(.emoji, to: start)
        #expect(emoji.background == .colour)
        #expect(emoji.savedSymbol == SavedGlyph(value: "bolt", scale: 16, background: .colour, tint: ConfigurationDefaults.tintColor))
        emoji.background = .mono
        // Back to Symbol: Symbol's own Colour comes back, Emoji's Mono is saved.
        let symbol = CustomiseTileView.applyStyle(.symbol, to: emoji)
        #expect(symbol.background == .colour)
        #expect(symbol.savedEmoji?.background == .mono)
        // And Emoji again is Mono.
        #expect(CustomiseTileView.applyStyle(.emoji, to: symbol).background == .mono)
    }

    @Test("The tile colour is local to Symbol and Emoji too: each style restores its own colour")
    func tintIsPerStyle() {
        let start = DockTileConfiguration(name: "W", tintColor: .preset(.blue), iconType: .sfSymbol, iconValue: "bolt",
                                          iconFace: .glyph)
        var emoji = CustomiseTileView.applyStyle(.emoji, to: start)
        #expect(emoji.tintColor == .preset(.blue))                  // first visit carries the colour over
        #expect(emoji.savedSymbol?.tint == .preset(.blue))
        emoji.tintColor = .custom("#FF8800")
        let symbol = CustomiseTileView.applyStyle(.symbol, to: emoji)
        #expect(symbol.tintColor == .preset(.blue))                 // Symbol's own colour comes back
        #expect(symbol.savedEmoji?.tint == .custom("#FF8800"))
        #expect(CustomiseTileView.applyStyle(.emoji, to: symbol).tintColor == .custom("#FF8800"))
    }

    @Test("A saved glyph without background/colour (saved before those fields) keeps the current ones")
    func savedGlyphWithoutBackground() {
        let emojiTile = DockTileConfiguration(name: "E", tintColor: .preset(.purple), iconType: .emoji, iconValue: "🎬",
                                              background: .mono, iconFace: .glyph,
                                              savedSymbol: SavedGlyph(value: "bolt", scale: 12))
        let symbol = CustomiseTileView.applyStyle(.symbol, to: emojiTile)
        #expect(symbol.iconValue == "bolt" && symbol.background == .mono && symbol.tintColor == .preset(.purple))
    }

    @Test("App Grid in between keeps both memories: Emoji → App Grid → Symbol restores the saved symbol")
    func appGridRoundTripKeepsMemories() {
        let emojiTile = DockTileConfiguration(name: "E", iconType: .emoji, iconValue: "🎬", iconScale: 20,
                                              iconFace: .glyph, savedSymbol: SavedGlyph(value: "bolt", scale: 12))
        let apps = CustomiseTileView.applyStyle(.apps, to: emojiTile)
        #expect(apps.iconFace == .apps && apps.iconValue == "🎬")
        let symbol = CustomiseTileView.applyStyle(.symbol, to: apps)
        #expect(symbol.iconFace == .glyph && symbol.iconValue == "bolt" && symbol.iconScale == 12)
        #expect(symbol.savedEmoji == SavedGlyph(value: "🎬", scale: 20, background: .colour, tint: ConfigurationDefaults.tintColor))
    }

    @Test("appsSummary: Shown, Arrangement and the note for 0, 1, 4, 9 and 12 apps")
    func appsSummary() {
        typealias S = CustomiseTileView.AppsSummary
        #expect(CustomiseTileView.appsSummary(count: 1) == S(shown: "1 of 1", arrangement: "2 × 2", note: "Shows the only app in this tile."))
        #expect(CustomiseTileView.appsSummary(count: 4) == S(shown: "4 of 4", arrangement: "2 × 2", note: "Shows all 4 apps, in tile order."))
        #expect(CustomiseTileView.appsSummary(count: 9) == S(shown: "9 of 9", arrangement: "3 × 3", note: "Shows all 9 apps, in tile order."))
        #expect(CustomiseTileView.appsSummary(count: 12) == S(shown: "9 of 12", arrangement: "3 × 3", note: "Shows the first 9 of 12 apps, in tile order."))
        #expect(CustomiseTileView.appsSummary(count: 0) == S(shown: "0 of 0", arrangement: "—", note: "No apps yet — use Add under In This Tile."))
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
                == S(shown: "0 of 0", arrangement: "—", note: "No apps yet — use Add under In This Tile."))
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
