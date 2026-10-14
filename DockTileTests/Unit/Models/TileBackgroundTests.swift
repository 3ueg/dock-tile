import Foundation
import Testing
@testable import Dock_Tile

@Suite("TileBackground schema v9")
struct TileBackgroundTests {
    private func encoded(_ config: DockTileConfiguration) throws -> [String: Any] {
        let data = try JSONEncoder().encode(config)
        return try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    private func decode(_ dict: [String: Any]) throws -> DockTileConfiguration {
        try JSONDecoder().decode(DockTileConfiguration.self, from: JSONSerialization.data(withJSONObject: dict))
    }

    @Test("A new tile defaults to Colour")
    func defaultIsColour() {
        #expect(DockTileConfiguration().background == .colour)
    }

    @Test("Mono round-trips through JSON")
    func monoRoundTrips() throws {
        let config = DockTileConfiguration(name: "Media", background: .mono)
        #expect(try decode(try encoded(config)).background == .mono)
    }

    @Test("A pre-v9 config (no background key) loads as Colour")
    func missingKeyIsColour() throws {
        var dict = try encoded(DockTileConfiguration(name: "Old", background: .mono))
        dict.removeValue(forKey: "background")
        #expect(try decode(dict).background == .colour)
    }

    @Test("A future background value loads as Colour instead of failing the whole tile")
    func unknownValueIsColour() throws {
        var dict = try encoded(DockTileConfiguration(name: "Future"))
        dict["background"] = "glass"
        let config = try decode(dict)
        #expect(config.background == .colour)
        #expect(config.name == "Future")
    }
}
