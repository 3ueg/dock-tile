//  ToneMapTests.swift — guards the pure contrast/lightness seam every tile colour goes through.
import Foundation
import Testing
@testable import Dock_Tile

@Suite("ToneMap contrast fitting")
struct ToneMapTests {
    private func rgb(_ hex: String) throws -> SRGB { try #require(SRGB(hex: hex)) }

    /// What a renderer actually draws: 8-bit channels.
    private func quantised(_ c: SRGB) -> SRGB {
        SRGB(r: (c.r * 255).rounded() / 255, g: (c.g * 255).rounded() / 255, b: (c.b * 255).rounded() / 255)
    }

    @Test("WCAG ratio: white/black is 21:1, a colour against itself is 1:1")
    func contrastEndpoints() throws {
        #expect(abs(ToneMap.contrastRatio(.white, try rgb("#000000")) - 21.0) < 0.001)
        #expect(abs(ToneMap.contrastRatio(try rgb("#FF9500"), try rgb("#FF9500")) - 1.0) < 0.0001)
        // Published value: #767676 on white is 4.54:1.
        #expect(abs(ToneMap.contrastRatio(try rgb("#767676"), .white) - 4.54) < 0.01)
    }

    @Test("A colour that already passes is returned byte-identical")
    func passingColourUnchanged() throws {
        let blue = try rgb("#007AFF")   // 4.0:1 on white
        let out = ToneMap.fit(blue, direction: .darker) { ToneMap.contrastRatio(.white, $0) >= ToneMap.searchTarget }
        #expect(out == blue)
    }

    @Test("Fitting darker against white clears 3.0 after 8-bit quantisation", arguments: [
        "#FF3B30", "#FF9500", "#34C759", "#007AFF", "#AF52DE", "#FF2D55", "#8E8E93",
        "#FFFFFF", "#FFCC00", "#5F00FF", "#0000FF", "#808080"
    ])
    func darkerFitClears(_ hex: String) throws {
        let out = ToneMap.fit(try rgb(hex), direction: .darker) { ToneMap.contrastRatio(.white, $0) >= ToneMap.searchTarget }
        #expect(ToneMap.contrastRatio(.white, quantised(out)) >= ToneMap.floor, "\(hex) → \(out)")
        for c in [out.r, out.g, out.b] { #expect(c >= 0 && c <= 1, "\(hex) out of gamut: \(out)") }
    }

    @Test("Fitting lighter against near-black clears 3.0", arguments: [
        "#000000", "#5F00FF", "#0000FF", "#AF52DE", "#FF3B30", "#1A0533", "#808080"
    ])
    func lighterFitClears(_ hex: String) throws {
        let ground = try rgb("#2C2C2E")
        let out = ToneMap.fit(try rgb(hex), direction: .lighter) { ToneMap.contrastRatio($0, ground) >= ToneMap.searchTarget }
        #expect(ToneMap.contrastRatio(quantised(out), ground) >= ToneMap.floor, "\(hex) → \(out)")
    }

    @Test("Hue is preserved within 3° for chromatic colours", arguments: [
        "#FF3B30", "#FF9500", "#34C759", "#FF2D55", "#5F00FF", "#AF52DE"
    ])
    func huePreserved(_ hex: String) throws {
        let base = try rgb(hex)
        let out = ToneMap.fit(base, direction: .darker) { ToneMap.contrastRatio(.white, $0) >= 4.5 }
        let h0 = try #require(ToneMap.hueDegrees(base))
        let h1 = try #require(ToneMap.hueDegrees(out))
        let drift = min(abs(h0 - h1), 360 - abs(h0 - h1))
        #expect(drift <= 3.0, "\(hex): hue \(h0) → \(h1)")
    }

    @Test("Fit stops at the boundary, not at black: the result is the passing colour closest to the original")
    func fitIsMinimal() throws {
        let orange = try rgb("#FF9500")
        let out = ToneMap.fit(orange, direction: .darker) { ToneMap.contrastRatio(.white, $0) >= ToneMap.searchTarget }
        let ratio = ToneMap.contrastRatio(.white, out)
        #expect(ratio >= ToneMap.searchTarget && ratio < ToneMap.searchTarget + 0.05, "overshot to \(ratio)")
    }

    @Test("Hex parsing: 6 and 8 digits with or without #, nil for anything else")
    func hexParsing() throws {
        #expect(SRGB(hex: "#FF9500") == SRGB(r: 1, g: 149.0 / 255, b: 0))
        #expect(SRGB(hex: "ff9500ff") == SRGB(r: 1, g: 149.0 / 255, b: 0))
        #expect(SRGB(hex: "oops") == nil)
        #expect(SRGB(hex: "#12") == nil)
    }

    @Test("darkened(by:) matches NSColor.darkened(by:)'s blend toward black")
    func darkenedArithmetic() throws {
        let c = SRGB(r: 1, g: 0.5, b: 0.2).darkened(by: 0.1)
        #expect(abs(c.r - 0.9) < 1e-9 && abs(c.g - 0.45) < 1e-9 && abs(c.b - 0.18) < 1e-9)
    }
}
