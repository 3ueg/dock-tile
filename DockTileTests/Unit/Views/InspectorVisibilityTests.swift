import Foundation
import Testing
@testable import Dock_Tile

/// The Customise inspector shows only while a tile row is selected; the stored flag alone is not enough.
@Suite("Inspector visibility")
struct InspectorVisibilityTests {
    @Test func storedAndTileShows() {
        #expect(DockTileConfigurationView.inspectorIsPresented(stored: true, selection: .tile(UUID())) == true)
    }

    @Test func settingsPaneHides() {
        #expect(DockTileConfigurationView.inspectorIsPresented(stored: true, selection: .settings(.general)) == false)
    }

    @Test func placeholderHides() {
        #expect(DockTileConfigurationView.inspectorIsPresented(stored: true, selection: .tilesPlaceholder) == false)
    }

    @Test func noSelectionHides() {
        #expect(DockTileConfigurationView.inspectorIsPresented(stored: true, selection: nil) == false)
    }

    @Test func notStoredHides() {
        #expect(DockTileConfigurationView.inspectorIsPresented(stored: false, selection: .tile(UUID())) == false)
    }

    // MARK: - Binding setter (nil = ignore, else the exact value to store)

    @Test func setterIgnoresSettingsPaneDismissal() {
        #expect(DockTileConfigurationView.inspectorSetterWrites(newValue: false, stored: true, selection: .settings(.general)) == nil)
    }

    @Test func setterIgnoresEchoOfOwnWrite() {
        #expect(DockTileConfigurationView.inspectorSetterWrites(newValue: true, stored: true, selection: .tile(UUID())) == nil)
    }

    @Test func setterWritesRealDismissal() {
        #expect(DockTileConfigurationView.inspectorSetterWrites(newValue: false, stored: true, selection: .tile(UUID())) == false)
    }

    @Test func setterWritesOpen() {
        #expect(DockTileConfigurationView.inspectorSetterWrites(newValue: true, stored: false, selection: .tile(UUID())) == true)
    }

    @Test func setterIgnoresPlaceholderEcho() {
        #expect(DockTileConfigurationView.inspectorSetterWrites(newValue: false, stored: false, selection: .tilesPlaceholder) == nil)
    }
}
