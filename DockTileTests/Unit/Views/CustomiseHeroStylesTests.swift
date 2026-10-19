import Testing
@testable import Dock_Tile

@Suite("Customise hero styles")
@MainActor   // nested in a View (main-actor) type, like the sibling suites
struct CustomiseHeroStylesTests {
    @Test("Colour follows the live style (one preview) whatever the OS")
    func colour() {
        #expect(CustomiseTileView.heroStyles(background: .colour, followsAppearance: true, iconFace: .glyph) == [nil])
        #expect(CustomiseTileView.heroStyles(background: .colour, followsAppearance: false, iconFace: .glyph) == [nil])
    }

    @Test("Mono shows the stacked Light / Dark pair only where the icon is compiled per appearance")
    func monoFollowsAppearance() {
        #expect(CustomiseTileView.heroStyles(background: .mono, followsAppearance: true, iconFace: .glyph) == [.defaultStyle, .dark])
    }

    @Test("Mono on the macOS 15 legacy bake is one light preview")
    func monoStatic() {
        #expect(CustomiseTileView.heroStyles(background: .mono, followsAppearance: false, iconFace: .glyph) == [.defaultStyle])
    }

    @Test("App Preview is one live hero even on a Mono tile")
    func appsFaceIsOnePreview() {
        #expect(CustomiseTileView.heroStyles(background: .mono, followsAppearance: true, iconFace: .apps) == [nil])
        #expect(CustomiseTileView.heroStyles(background: .colour, followsAppearance: false, iconFace: .apps) == [nil])
    }
}
