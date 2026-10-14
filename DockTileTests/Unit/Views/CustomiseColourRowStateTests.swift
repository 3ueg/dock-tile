import Testing
@testable import Dock_Tile

@Suite("Customise colour row state")
@MainActor   // ColourRowState is nested in a View (main-actor) type
struct CustomiseColourRowStateTests {
    @Test("Colour tile: fills, or deepened when the fill moved — but never 'so the symbol stays clear' for an emoji")
    func colourTile() {
        #expect(CustomiseTileView.colourRowState(background: .colour, iconType: .sfSymbol, fillDeepened: false) == .fillsTile)
        #expect(CustomiseTileView.colourRowState(background: .colour, iconType: .sfSymbol, fillDeepened: true) == .deepened)
        #expect(CustomiseTileView.colourRowState(background: .colour, iconType: .emoji, fillDeepened: true) == .fillsTile)
    }

    @Test("Mono tile: toned for symbols, locked (but not reset) for emoji")
    func monoTile() {
        let symbol = CustomiseTileView.colourRowState(background: .mono, iconType: .sfSymbol, fillDeepened: true)
        #expect(symbol == .toned && !symbol.isDisabled && symbol.usesSymbolLabel)
        let emoji = CustomiseTileView.colourRowState(background: .mono, iconType: .emoji, fillDeepened: false)
        #expect(emoji == .emojiLocked && emoji.isDisabled && emoji.usesSymbolLabel)
    }

    @Test("Only the Mono + emoji state disables the swatches")
    func onlyEmojiLockedDisables() {
        for s in [CustomiseTileView.ColourRowState.fillsTile, .deepened, .toned] { #expect(!s.isDisabled) }
    }
}
