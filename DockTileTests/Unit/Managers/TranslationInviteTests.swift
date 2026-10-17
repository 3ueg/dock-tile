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

    @Test("Invite once, and only where the row shows",
          arguments: [("zh-Hans", false, true), ("zh-Hans", true, false), ("en-GB", false, false),
                      ("ja", false, true), ("ja", true, false)])
    func inviteDecision(localization: String, alreadyShown: Bool, invites: Bool) {
        #expect(TranslationInvite.shouldInvite(localization: localization, alreadyShown: alreadyShown) == invites)
    }

    @Test("A Mac the app does not localize (Korean resolves to en-GB) is never invited")
    func unsupportedLanguageResolvesToEnglish() {
        #expect(TranslationInvite.shouldInvite(localization: "en-GB", alreadyShown: false) == false)
        #expect(TranslationInvite.shouldInvite(localization: nil, alreadyShown: false) == false)
    }
}
