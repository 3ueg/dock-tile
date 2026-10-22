import AppKit
import Testing
@testable import Dock_Tile

/// A new blank tile starts on a random symbol and emoji (owner, 2026-10-22). Failing values: a
/// pool symbol that does not exist on this OS (it would draw nothing — a silent failure), a pool
/// that repeats itself, the old `plus` placeholder creeping back in, or a draw that never varies.
@Suite("Starter glyphs for new tiles")
struct StarterGlyphTests {

    private struct SeededGenerator: RandomNumberGenerator {
        var state: UInt64
        mutating func next() -> UInt64 {
            state &+= 0x9E37_79B9_7F4A_7C15
            var z = state
            z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE5_E9B9
            z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
            return z ^ (z >> 31)
        }
    }

    @Test("Every starter symbol resolves on this OS")
    func symbolsResolve() {
        for name in ConfigurationDefaults.starterSymbols {
            #expect(NSImage(systemSymbolName: name, accessibilityDescription: nil) != nil, "\(name)")
        }
    }

    @Test("Pools are distinct, non-trivial, and exclude the plus placeholder")
    func poolsAreSound() {
        let symbols = ConfigurationDefaults.starterSymbols
        let emoji = ConfigurationDefaults.starterEmoji
        #expect(symbols.count >= 12 && Set(symbols).count == symbols.count)
        #expect(emoji.count >= 12 && Set(emoji).count == emoji.count)
        #expect(!symbols.contains(ConfigurationDefaults.iconValue))
    }

    @Test("A draw comes from the pools and varies across draws")
    func drawsVary() {
        var symbols = Set<String>(), emoji = Set<String>()
        for seed in UInt64(1)...40 {
            var g = SeededGenerator(state: seed)
            let pick = ConfigurationDefaults.starterGlyphs(using: &g)
            #expect(ConfigurationDefaults.starterSymbols.contains(pick.symbol))
            #expect(ConfigurationDefaults.starterEmoji.contains(pick.emoji))
            symbols.insert(pick.symbol); emoji.insert(pick.emoji)
        }
        #expect(symbols.count > 5 && emoji.count > 5)
    }
}
