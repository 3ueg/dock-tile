//
//  TranslationInvite.swift
//  Dock Tile
//
//  Decides when the app is showing a machine-first translation and should invite a native speaker
//  to review it. Pure seams (guarded by TranslationInviteTests); the manager that shows the alert
//  lives below them.
//

import AppKit

enum TranslationInvite {
    /// The localization macOS chose for this bundle (`Bundle.main.preferredLocalizations.first`),
    /// e.g. "zh-Hans". A Mac whose language the app does not ship resolves to "en-GB" (the
    /// development region), so an unsupported language never sees the invitation.
    nonisolated static var runningLocalization: String? { Bundle.main.preferredLocalizations.first }

    nonisolated static func showsTranslationRow(localization: String?) -> Bool {
        guard let localization, !localization.isEmpty else { return false }
        return !localization.hasPrefix("en")
    }

    nonisolated static func shouldInvite(localization: String?, alreadyShown: Bool) -> Bool {
        !alreadyShown && showsTranslationRow(localization: localization)
    }
}

@MainActor
final class TranslationInviteManager {
    static let shared = TranslationInviteManager()
    private init() {}

    /// Main-app only; the caller (`configureAsMainApp`) already skips it under tests. Runs after the
    /// relocation nudge so a Downloads-run Mac sees the move prompt first.
    func checkOnLaunch() {
        guard !AppEnvironment.isHelper else { return }
        let localization = TranslationInvite.runningLocalization
        let shown = UserDefaults.standard.bool(forKey: UserDefaultsKeys.translationInviteShown)
        guard TranslationInvite.shouldInvite(localization: localization, alreadyShown: shown) else { return }
        UserDefaults.standard.set(true, forKey: UserDefaultsKeys.translationInviteShown)
        let language = localization ?? "unknown"
        DiagnosticsLog.shared.log("translation", "Inviting review of the \(language) translation")
        AnalyticsService.shared.log(.translationInviteShown, ["ui_language": language])

        let alert = NSAlert()
        alert.messageText = AppStrings.Translation.inviteTitle
        alert.informativeText = AppStrings.Translation.inviteMessage
        alert.alertStyle = .informational
        alert.addButton(withTitle: AppStrings.Translation.helpImprove)
        alert.addButton(withTitle: AppStrings.Button.notNow)
        // App-modal like the relocation nudge: it fires from the launch block, before any sheet host.
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        DiagnosticsLog.shared.ui("Translation invite → Help Improve")
        AnalyticsService.shared.log(.translationHelpTapped, ["source": "alert", "ui_language": language])
        NSWorkspace.shared.open(AboutLinks.translationSheet(localization: language))
    }
}
