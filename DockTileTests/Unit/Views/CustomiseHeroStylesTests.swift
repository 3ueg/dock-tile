import Testing
@testable import Dock_Tile

@Suite("Customise hero styles")
@MainActor   // nested in a View (main-actor) type, like the sibling suites
struct CustomiseHeroStylesTests {
    @Test("Colour follows the live style (one preview) whatever the OS")
    func colour() {
        #expect(CustomiseTileView.heroStyles(background: .colour, followsAppearance: true) == [nil])
        #expect(CustomiseTileView.heroStyles(background: .colour, followsAppearance: false) == [nil])
    }

    @Test("Mono shows Light and Dark only where the icon is compiled per appearance")
    func monoFollowsAppearance() {
        #expect(CustomiseTileView.heroStyles(background: .mono, followsAppearance: true) == [.defaultStyle, .dark])
    }

    @Test("Mono on the macOS 15 legacy bake is one light preview")
    func monoStatic() {
        #expect(CustomiseTileView.heroStyles(background: .mono, followsAppearance: false) == [.defaultStyle])
    }
}
