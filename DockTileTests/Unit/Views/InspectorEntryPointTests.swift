import Foundation
import SwiftUI
import Testing
@testable import Dock_Tile

/// Inspector entry points: the canonical hero while editing and the View menu item's enablement.
@Suite("Inspector entry points")
struct InspectorEntryPointTests {
    @Test func heroIsLiveWhileClosedInLight() {
        #expect(DockTileDetailView.heroForcedStyle(inspectorShown: false, colorScheme: .light) == nil)
    }

    @Test func heroIsLiveWhileClosedInDark() {
        #expect(DockTileDetailView.heroForcedStyle(inspectorShown: false, colorScheme: .dark) == nil)
    }

    @Test func heroIsDefaultWhenOpenInLight() {
        #expect(DockTileDetailView.heroForcedStyle(inspectorShown: true, colorScheme: .light) == .defaultStyle)
    }

    @Test func heroIsDarkWhenOpenInDark() {
        #expect(DockTileDetailView.heroForcedStyle(inspectorShown: true, colorScheme: .dark) == .dark)
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
