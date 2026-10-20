import Foundation
import SwiftUI
import Testing
@testable import Dock_Tile

/// Inspector entry points: the canonical hero while editing and the View menu item's enablement.
@Suite("Inspector entry points")
struct InspectorEntryPointTests {
    @Test func heroIsLiveWhileClosedInLight() {
        #expect(DockTileDetailView.heroForcedStyle(inspectorShown: false, colorScheme: .light, followsAppearance: true) == nil)
    }

    @Test func heroIsLiveWhileClosedInDark() {
        #expect(DockTileDetailView.heroForcedStyle(inspectorShown: false, colorScheme: .dark, followsAppearance: true) == nil)
    }

    @Test func heroIsDefaultWhenOpenInLight() {
        #expect(DockTileDetailView.heroForcedStyle(inspectorShown: true, colorScheme: .light, followsAppearance: true) == .defaultStyle)
    }

    @Test func heroIsDarkWhenOpenInDark() {
        #expect(DockTileDetailView.heroForcedStyle(inspectorShown: true, colorScheme: .dark, followsAppearance: true) == .dark)
    }

    /// macOS 15: the Dock always shows the light render, so the open hero never promises a black tile.
    @Test func heroIsDefaultWhenOpenInDarkWithoutAppearance() {
        #expect(DockTileDetailView.heroForcedStyle(inspectorShown: true, colorScheme: .dark, followsAppearance: false) == .defaultStyle)
    }

    @Test func heroIsLiveWhileClosedInDarkWithoutAppearance() {
        #expect(DockTileDetailView.heroForcedStyle(inspectorShown: false, colorScheme: .dark, followsAppearance: false) == nil)
    }

    @Test func commandEnabledForTile() {
        #expect(DockTileConfigurationView.inspectorCommandIsEnabled(selection: .tile(UUID())) == true)
    }

    @Test func commandDisabledForSettings() {
        #expect(DockTileConfigurationView.inspectorCommandIsEnabled(selection: .settings(.popover)) == false)
    }

    @Test func commandDisabledForPlaceholder() {
        #expect(DockTileConfigurationView.inspectorCommandIsEnabled(selection: .tilesPlaceholder) == false)
    }

    @Test func commandDisabledForNoSelection() {
        #expect(DockTileConfigurationView.inspectorCommandIsEnabled(selection: nil) == false)
    }
}
