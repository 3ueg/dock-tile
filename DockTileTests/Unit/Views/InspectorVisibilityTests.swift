import Foundation
import Testing
@testable import Dock_Tile

/// The Customise inspector shows only while a tile row is selected; the stored flag alone is not enough.
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
}
