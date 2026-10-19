//
//  SavedGlyphTests.swift
//  DockTileTests
//
//  Guards the per-type glyph memory (schema v11): a tile remembers its last symbol and its last
//  emoji, each with its own icon size, so switching the Style card away and back restores them
//  instead of seeding the default glyph.
//

import Foundation
import Testing
@testable import Dock_Tile

@Suite("Saved symbol and emoji (schema v11)")
struct SavedGlyphTests {
    private func encoded(_ config: DockTileConfiguration) throws -> [String: Any] {
        let data = try JSONEncoder().encode(config)
        return try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
    }
    private func decode(_ dict: [String: Any]) throws -> DockTileConfiguration {
        try JSONDecoder().decode(DockTileConfiguration.self, from: JSONSerialization.data(withJSONObject: dict))
    }

    @Test("A new tile has nothing saved, and a pre-v11 config loads with nothing saved")
    func defaultsAreEmpty() throws {
        let fresh = DockTileConfiguration(name: "New")
        #expect(fresh.savedSymbol == nil && fresh.savedEmoji == nil)
        var dict = try encoded(DockTileConfiguration(name: "Old", savedSymbol: SavedGlyph(value: "bolt", scale: 16),
                                                     savedEmoji: SavedGlyph(value: "🎬", scale: 20)))
        dict.removeValue(forKey: "savedSymbol")
        dict.removeValue(forKey: "savedEmoji")
        let old = try decode(dict)
        #expect(old.savedSymbol == nil && old.savedEmoji == nil)
        #expect(old.name == "Old")
    }

    @Test("Both memories round-trip through JSON")
    func roundTrips() throws {
        let symbol = SavedGlyph(value: "bolt", scale: 16, background: .mono, tint: .custom("#FF8800"))
        let emoji = SavedGlyph(value: "🎬", scale: 20, background: .colour, tint: .preset(.blue))
        let config = DockTileConfiguration(name: "W", savedSymbol: symbol, savedEmoji: emoji)
        let back = try decode(try encoded(config))
        #expect(back.savedSymbol == symbol)
        #expect(back.savedEmoji == emoji)
        // A glyph saved before background/tint existed still decodes, with both nil.
        var dict = try encoded(config)
        dict["savedSymbol"] = ["value": "bolt", "scale": 16]
        #expect(try decode(dict).savedSymbol == SavedGlyph(value: "bolt", scale: 16))
    }

    @Test("The memory is not part of the Dock icon's signature")
    func notInIconSignature() {
        let plain = DockTileConfiguration(name: "W", iconType: .sfSymbol, iconValue: "bolt", iconFace: .glyph)
        var remembered = plain
        remembered.savedEmoji = SavedGlyph(value: "🎬", scale: 20)
        #expect(plain.iconSignature == remembered.iconSignature)
    }
}
