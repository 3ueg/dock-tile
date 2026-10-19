import Foundation
import Testing
@testable import Dock_Tile

@Suite("IconFace schema v10")
struct IconFaceTests {
    private func encoded(_ config: DockTileConfiguration) throws -> [String: Any] {
        let data = try JSONEncoder().encode(config)
        return try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
    }
    private func decode(_ dict: [String: Any]) throws -> DockTileConfiguration {
        try JSONDecoder().decode(DockTileConfiguration.self, from: JSONSerialization.data(withJSONObject: dict))
    }

    @Test("newTilesDefaultToApps: ConfigurationDefaults and a fresh configuration are App Preview")
    func newTilesDefaultToApps() {
        #expect(ConfigurationDefaults.iconFace == .apps)
        #expect(DockTileConfiguration().iconFace == .apps)
    }

    /// The test host is the dev app: this creates (and deletes) a real dev tile, like
    /// `ConfigurationManagerTests` does.
    @MainActor
    @Test("createdTilesUseTheDefault: + and Smart Add both create an App Preview tile")
    func createdTilesUseTheDefault() {
        let manager = ConfigurationManager()
        let blank = manager.createConfiguration()
        defer { manager.deleteConfiguration(blank.id) }
        #expect(blank.iconFace == .apps)
        #expect(blank.iconType == .sfSymbol && blank.iconValue == ConfigurationDefaults.iconValue)   // the glyph behind it is still the draft placeholder
    }

    @Test("Apps round-trips through JSON under the key iconFace")
    func appsRoundTrips() throws {
        let dict = try encoded(DockTileConfiguration(name: "Work", iconFace: .apps))
        #expect(dict["iconFace"] as? String == "apps")
        #expect(try decode(dict).iconFace == .apps)
    }

    @Test("missingKeyIsGlyph: a pre-v10 config (no iconFace key) loads as glyph — NOT the new-tile default")
    func missingKeyIsGlyph() throws {
        var dict = try encoded(DockTileConfiguration(name: "Old", iconFace: .apps))
        dict.removeValue(forKey: "iconFace")
        #expect(try decode(dict).iconFace == .glyph)
        #expect(ConfigurationDefaults.iconFace != .glyph)   // the two defaults really differ, so this test can fail
    }

    @Test("A future face value loads as glyph instead of failing the whole tile")
    func unknownValueIsGlyph() throws {
        var dict = try encoded(DockTileConfiguration(name: "Future"))
        dict["iconFace"] = "widgets"
        let config = try decode(dict)
        #expect(config.iconFace == .glyph)
        #expect(config.name == "Future")
    }

    @Test("Switching face keeps every glyph field")
    func glyphFieldsRetained() {
        var config = DockTileConfiguration(name: "Work", tintColor: .custom("#5F00FF"), iconType: .emoji,
                                           iconValue: "🎬", iconScale: 18, iconWeight: .bold, background: .mono)
        config.iconFace = .apps
        #expect(config.tintColor == .custom("#5F00FF") && config.iconType == .emoji && config.iconValue == "🎬")
        #expect(config.iconScale == 18 && config.iconWeight == .bold && config.background == .mono)
    }
}
