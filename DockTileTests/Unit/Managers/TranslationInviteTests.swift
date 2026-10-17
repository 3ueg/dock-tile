import Testing
@testable import Dock_Tile

@Suite("Translation invite seams")
struct TranslationInviteTests {
    @Test("The About row shows only for a non-English localization",
          arguments: [("zh-Hans", true), ("ja", true), ("de", true), ("en-GB", false), ("en-US", false),
                      ("en", false), ("", false)])
    func rowVisibility(localization: String, shows: Bool) {
        #expect(TranslationInvite.showsTranslationRow(localization: localization) == shows)
    }

    @Test("No localization means no row")
    func nilLocalization() {
        #expect(TranslationInvite.showsTranslationRow(localization: nil) == false)
    }
}
