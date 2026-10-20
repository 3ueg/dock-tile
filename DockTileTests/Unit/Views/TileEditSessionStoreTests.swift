import Foundation
import Testing
@testable import Dock_Tile

/// The missing-apps Remove copies ONLY `appItems` back into the live edit session, so the next
/// debounced save can't resurrect the removed apps, and never clobbers the user's other unsaved edits.
@Suite("Tile edit session store")
@MainActor
struct TileEditSessionStoreTests {
    private let kept = AppItem(bundleIdentifier: "com.apple.Safari", name: "Safari")
    private let missing = AppItem(bundleIdentifier: "com.example.Gone", name: "Gone")

    @Test func syncCopiesStoredAppItemsAndKeepsOtherEdits() {
        let id = UUID()
        let store = TileEditSessionStore()
        let session = store.session(for: DockTileConfiguration(id: id, name: "Work", appItems: [kept, missing]))
        session.config.name = "Unsaved name"

        store.syncAppItems(from: [DockTileConfiguration(id: id, name: "Work", appItems: [kept])])

        #expect(session.config.appItems == [kept])
        #expect(session.config.name == "Unsaved name")
    }

    @Test func syncIgnoresOtherTiles() {
        let store = TileEditSessionStore()
        let session = store.session(for: DockTileConfiguration(id: UUID(), name: "Work", appItems: [kept, missing]))

        store.syncAppItems(from: [DockTileConfiguration(id: UUID(), name: "Other", appItems: [])])

        #expect(session.config.appItems == [kept, missing])
    }
}
