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
