//
//  IconStyleDisplayPollTests.swift
//  DockTileTests
//
//  Guards the main app's icon-style display poll (issue #22). On macOS 27 no notification is posted
//  when Icon & widget style changes, and UserDefaults KVO on `AppleIconAppearanceTheme` reached the
//  app 1.4 s to 8 min late (or never), so the window's previews poll the key — but ONLY while the
//  app is visible on screen. A poll left running while hidden is the regression these pin.
//

import Testing
@testable import Dock_Tile

@Suite("Icon-style display poll runs only while the app is visible")
@MainActor
struct IconStyleDisplayPollTests {

    @Test("Visible and not polling → start")
    func startsWhenVisible() {
        #expect(IconStyleManager.displayPollAction(appVisible: true, polling: false) == .start)
    }

    @Test("Hidden or covered while polling → stop")
    func stopsWhenNotVisible() {
        #expect(IconStyleManager.displayPollAction(appVisible: false, polling: true) == .stop)
    }

    @Test("No change needed → leave it alone (never restart a running poll, never stop an idle one)")
    func steadyStates() {
        #expect(IconStyleManager.displayPollAction(appVisible: true, polling: true) == .none)
        #expect(IconStyleManager.displayPollAction(appVisible: false, polling: false) == .none)
    }

    @Test("Poll interval is 2 s — responsive within a glance, one cheap read per tick")
    func intervalIsTwoSeconds() {
        #expect(IconStyleManager.displayPollInterval == 2.0)
    }
}
