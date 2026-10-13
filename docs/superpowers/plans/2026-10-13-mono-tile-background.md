# Mono Tile Background Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a per-tile **Background** choice (Colour | Mono) where Mono is white in Light Mode and near-black in Dark Mode with the tile's colour on the symbol, and tone-map every tile's colours to a 3:1 symbol/background contrast floor.

**Architecture:** One pure colour seam (`ToneMap` + `TilePalette`, plain sRGB values, no AppKit/SwiftUI) decides every colour; the existing `TintColor.colors(for:)` / `.nsColors(for:)` / `.badgeColors(for:)` become thin adapters over it with a REQUIRED `background:` parameter, so every renderer (macOS 26 `.icon`, glyph PNGs, fallback `.icns`, macOS 15 bake, live preview, sidebar badges) reads the same values. A Mono symbol tile's `.icon` gains a third, tinted-only glyph layer.

**Tech Stack:** Swift 6, SwiftUI + AppKit, Swift Testing, Icon Composer `.icon` → vendored `docktile-actool` (Rust).

**Spec:** [docs/superpowers/specs/2026-10-13-mono-tile-background-design.md](../specs/2026-10-13-mono-tile-background-design.md)

## Global Constraints

- Deployment target macOS 15.0; anything macOS 26-only is `#available`-gated with a fallback. The macOS 15 CI leg (`test-macos-15`) must stay green.
- Contrast promise: **3:1** (WCAG 2.2 SC 1.4.11). Searches aim at `ToneMap.floor + ToneMap.margin` = 3.1 so 8-bit quantisation and colour-space conversion can never land a rendered pair below 3.0. Increase Contrast changes nothing.
- `TileBackground` cases are exactly `colour` and `mono`; default `.colour`; unknown raw value decodes to `.colour`.
- Mono backgrounds: Light `#FFFFFF → #EFEFF1`; Dark `#2C2C2E → #1C1C1E` (`TintColor.darkNeutralTopHex` / `darkNeutralBottomHex`). Clear and Tinted styles are unchanged greyscale for every background.
- No `background:` default on any colour-path function (`TilePalette.resolve`, `colors`, `nsColors`, `generateIcon`, `generateIcns`, `generateGlyphLayerPNG`, `generateFallbackIcns`, `DockTileIconPreview`'s full initializer). Omission must be a compile error.
- All user-facing strings via `AppStrings` + `Localizable.xcstrings` (en-GB/en-AU "Colour", en-US "Color"). Insert xcstrings entries textually; never re-dump the file.
- New **app-target** Swift files need `project.pbxproj` entries; new `DockTileTests/` files auto-join.
- Tests never write `UserDefaults.standard`. Prefer `#require`; assert exact values.
- Work on branch `feat/mono-tile` in a worktree (superpowers:using-git-worktrees). Commits are their own Bash call (the commit hook rejects any command containing `git commit` plus a bare `-n`). When the worktree is removed, delete its `DerivedData/DockTile-<hash>`.
- Test command, referred to below as **TEST(<Suite>)**:
  `xcodebuild test -project DockTile.xcodeproj -scheme DockTile -configuration Debug -destination 'platform=macOS' -only-testing:DockTileTests/<Suite> CODE_SIGNING_ALLOWED=NO`
  and **TEST(all)** = the same with `-only-testing:DockTileTests`.

## Review Focus

1. **Extreme custom colours** — `#FFFFFF`, `#000000`, `#808080`, a fully saturated `#0000FF` in every role: the fit must terminate, return a valid in-gamut colour and clear 3.0 (white on a Colour tile becomes a mid grey; black in Mono Dark becomes a light grey). Pinned in Task 1 + Task 3.
2. **Malformed custom hex** in an old config (`.custom("oops")`, `.custom("#12")`) — must render the grey preset's tones, never crash or draw black. Pinned in Task 3.
3. **Config round-trips across versions** — a pre-v9 config loads as `.colour`; a config carrying a future `"background": "glass"` loads as `.colour` instead of failing the whole tile list. Pinned in Task 2.
4. **Mono + emoji** — switching a Mono tile to an emoji disables the colour row but keeps `tintColor`; switching back re-enables it with the same colour. Pinned in Task 8 (`colourRowState` seam).
5. **Tinted / Clear appearance of a Mono symbol tile** — the tinted rendition starts from the WHITE light gradient (vendored compiler), so the star must still read clearly. Decided empirically by Task 3b's spike before any document change; pinned afterwards by Task 4/5's layer tests for the chosen variant and Task 9's Dock check.
6. **A fixed system icon style (Dark / Clear / Tinted, not Automatic)** — the Customise chips and the Mono Light/Dark hero must still show two different canonical tiles. Pinned in Task 6 (`forcedStyleWins`) + Task 8's hands-on check.

---

### Task 1: `ToneMap` — contrast + hue-preserving lightness fit

**Files:**
- Create: `DockTile/Utilities/TilePalette.swift` (this task adds `SRGB` + `ToneMap`; Task 3 appends `TilePalette`)
- Modify: `DockTile.xcodeproj/project.pbxproj` (4 entries, below)
- Test: `DockTileTests/Unit/Utilities/ToneMapTests.swift`

**Interfaces:**
- Produces: `struct SRGB { r, g, b: Double; init?(hex:); init(r:g:b:); static let white; func darkened(by:) -> SRGB; func lighterShade(by:) -> SRGB; func cappingBrightness(_:) -> SRGB }`; `enum ToneMap { enum Direction { darker, lighter }; static let floor = 3.0; static let margin = 0.1; static var searchTarget: Double; static func relativeLuminance(_:) -> Double; static func contrastRatio(_:_:) -> Double; static func fit(_:direction:passes:) -> SRGB; static func shiftingLightness(_:by:) -> SRGB; static func hueDegrees(_:) -> Double? }`

- [ ] **Step 0: Worktree + spec commit**

Create the worktree on `feat/mono-tile` (superpowers:using-git-worktrees), run `./Scripts/build-compiler.sh` there if `Vendor/actool/target/release/docktile-actool` is absent, then:

```bash
git add docs/superpowers/specs/2026-10-13-mono-tile-background-design.md docs/superpowers/plans/2026-10-13-mono-tile-background.md
```
```bash
git commit -m "docs: mono tile background spec and plan"
```

- [ ] **Step 1: Write the failing tests**

```swift
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
```

- [ ] **Step 2: Run to verify it fails**

Run: TEST(ToneMapTests). Expected: build failure — `cannot find 'SRGB' in scope`.

- [ ] **Step 3: Implement**

Create `DockTile/Utilities/TilePalette.swift`:

```swift
//
//  TilePalette.swift
//  DockTile
//
//  The single source of every tile colour. `ToneMap` fits a colour to a contrast floor while
//  holding its hue (OKLCH lightness bisection, chroma reduced to stay in sRGB gamut, the real
//  WCAG 2 ratio measured at every step — Adobe Leonardo's approach). `TilePalette` (below) maps a
//  tile's one stored colour to its role per background × style. Plain sRGB values only — no
//  AppKit/SwiftUI — so every rule is unit-testable. Renderers read it through the thin
//  `TintColor.colors/nsColors/badgeColors` adapters in IconStyleManager.swift.
//
//  Swift 6 - Strict Concurrency
//

import Foundation

/// A gamma-encoded sRGB colour, components 0…1.
struct SRGB: Hashable, Sendable {
    var r: Double
    var g: Double
    var b: Double

    nonisolated static let white = SRGB(r: 1, g: 1, b: 1)

    nonisolated init(r: Double, g: Double, b: Double) {
        self.r = r; self.g = g; self.b = b
    }

    /// `#RRGGBB` / `RRGGBB`; an 8-digit `RRGGBBAA` ignores alpha. Nil for anything else.
    nonisolated init?(hex: String) {
        var s = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.hasPrefix("#") { s.removeFirst() }
        guard s.count == 6 || s.count == 8, let v = UInt64(s, radix: 16) else { return nil }
        let rgb = s.count == 8 ? v >> 8 : v
        self.init(r: Double((rgb >> 16) & 0xFF) / 255,
                  g: Double((rgb >> 8) & 0xFF) / 255,
                  b: Double(rgb & 0xFF) / 255)
    }

    /// Blend toward black by `fraction` — the arithmetic `NSColor.darkened(by:)` applies to the
    /// glyph's shaded bottom, so contrast checks measure what is actually drawn.
    nonisolated func darkened(by fraction: Double) -> SRGB {
        SRGB(r: r * (1 - fraction), g: g * (1 - fraction), b: b * (1 - fraction))
    }

    /// HSB lighten: brightness + amount, saturation − amount × 0.3. Pure mirror of
    /// `NSColor.lighterShade(by:)` (custom colours' lighter gradient stop).
    nonisolated func lighterShade(by amount: Double) -> SRGB {
        let (h, s, v) = hsv
        return SRGB.fromHSV(h: h, s: max(0, s - amount * 0.3), v: min(1, v + amount))
    }

    /// HSB brightness cap with hue and saturation held — pure mirror of
    /// `NSColor.darkenedForDarkMode(maxBrightness:)`. Scaling every channel keeps H and S.
    nonisolated func cappingBrightness(_ cap: Double) -> SRGB {
        let v = max(r, g, b)
        guard v > cap, v > 0 else { return self }
        let k = cap / v
        return SRGB(r: r * k, g: g * k, b: b * k)
    }

    private nonisolated var hsv: (h: Double, s: Double, v: Double) {
        let mx = max(r, g, b), mn = min(r, g, b), d = mx - mn
        let s = mx == 0 ? 0 : d / mx
        var h = 0.0
        if d > 0 {
            if mx == r { h = ((g - b) / d).truncatingRemainder(dividingBy: 6) }
            else if mx == g { h = (b - r) / d + 2 }
            else { h = (r - g) / d + 4 }
            h /= 6
            if h < 0 { h += 1 }
        }
        return (h, s, mx)
    }

    private nonisolated static func fromHSV(h: Double, s: Double, v: Double) -> SRGB {
        let i = floor(h * 6), f = h * 6 - i
        let p = v * (1 - s), q = v * (1 - f * s), t = v * (1 - (1 - f) * s)
        switch Int(i) % 6 {
        case 0: return SRGB(r: v, g: t, b: p)
        case 1: return SRGB(r: q, g: v, b: p)
        case 2: return SRGB(r: p, g: v, b: t)
        case 3: return SRGB(r: p, g: q, b: v)
        case 4: return SRGB(r: t, g: p, b: v)
        default: return SRGB(r: v, g: p, b: q)
        }
    }
}

/// Contrast measurement and hue-preserving lightness fitting.
enum ToneMap {
    enum Direction { case darker, lighter }

    /// The promise: symbol vs background ≥ 3:1 (WCAG 2.2 SC 1.4.11 non-text contrast). A Dock icon
    /// is compiled once and cannot react to Increase Contrast, so this is the only target.
    nonisolated static let floor = 3.0
    /// Search headroom so 8-bit quantisation and colour-space conversion never land a rendered
    /// pair below `floor`.
    nonisolated static let margin = 0.1
    nonisolated static var searchTarget: Double { floor + margin }

    nonisolated static func relativeLuminance(_ c: SRGB) -> Double {
        0.2126 * linear(c.r) + 0.7152 * linear(c.g) + 0.0722 * linear(c.b)
    }

    nonisolated static func contrastRatio(_ a: SRGB, _ b: SRGB) -> Double {
        let la = relativeLuminance(a), lb = relativeLuminance(b)
        return (max(la, lb) + 0.05) / (min(la, lb) + 0.05)
    }

    /// The colour closest to `colour` (same OKLCH hue) that satisfies `passes`, moving lightness
    /// in `direction`. Returns `colour` unchanged when it already passes. `passes` tests the pair
    /// the renderer really draws (e.g. a shaded glyph bottom), which is why it is a predicate.
    nonisolated static func fit(_ colour: SRGB, direction: Direction, passes: (SRGB) -> Bool) -> SRGB {
        if passes(colour) { return colour }
        let start = OKLCH(colour)
        let endL = direction == .darker ? 0.0 : 1.0
        let end = start.withL(endL).inGamut()
        guard passes(end) else { return end }   // unreachable for a 3:1 target; never loops
        var failing = start.L, passing = endL
        for _ in 0..<24 {
            let mid = (failing + passing) / 2
            if passes(start.withL(mid).inGamut()) { passing = mid } else { failing = mid }
        }
        return start.withL(passing).inGamut()
    }

    /// The same hue and chroma with OKLCH lightness moved by `delta` (clamped to 0…1).
    nonisolated static func shiftingLightness(_ colour: SRGB, by delta: Double) -> SRGB {
        let c = OKLCH(colour)
        return c.withL(min(max(c.L + delta, 0), 1)).inGamut()
    }

    /// OKLCH hue in degrees, or nil for a near-grey (hue undefined below chroma 0.02).
    nonisolated static func hueDegrees(_ c: SRGB) -> Double? {
        let o = OKLCH(c)
        guard o.C >= 0.02 else { return nil }
        let d = o.h * 180 / .pi
        return d < 0 ? d + 360 : d
    }

    // MARK: sRGB transfer

    nonisolated static func linear(_ c: Double) -> Double {
        c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)
    }

    nonisolated static func encoded(_ c: Double) -> Double {
        c <= 0.0031308 ? 12.92 * c : 1.055 * pow(c, 1 / 2.4) - 0.055
    }
}

/// OKLab in polar form (Björn Ottosson's matrices).
private struct OKLCH {
    var L: Double
    var C: Double
    var h: Double   // radians

    nonisolated init(L: Double, C: Double, h: Double) { self.L = L; self.C = C; self.h = h }

    nonisolated init(_ c: SRGB) {
        let r = ToneMap.linear(c.r), g = ToneMap.linear(c.g), b = ToneMap.linear(c.b)
        let l = cbrt(0.4122214708 * r + 0.5363325363 * g + 0.0514459929 * b)
        let m = cbrt(0.2119034982 * r + 0.6806995451 * g + 0.1073969566 * b)
        let s = cbrt(0.0883024619 * r + 0.2817188376 * g + 0.6299787005 * b)
        let L = 0.2104542553 * l + 0.7936177850 * m - 0.0040720468 * s
        let A = 1.9779984951 * l - 2.4285922050 * m + 0.4505937099 * s
        let B = 0.0259040371 * l + 0.7827717662 * m - 0.8086757660 * s
        self.init(L: L, C: (A * A + B * B).squareRoot(), h: atan2(B, A))
    }

    nonisolated func withL(_ newL: Double) -> OKLCH { OKLCH(L: newL, C: C, h: h) }

    /// Linear-light RGB, unclamped.
    nonisolated func linearRGB(chroma: Double) -> (Double, Double, Double) {
        let A = chroma * cos(h), B = chroma * sin(h)
        let l = pow(L + 0.3963377774 * A + 0.2158037573 * B, 3)
        let m = pow(L - 0.1055613458 * A - 0.0638541728 * B, 3)
        let s = pow(L - 0.0894841775 * A - 1.2914855480 * B, 3)
        return (4.0767416621 * l - 3.3077115913 * m + 0.2309699292 * s,
                -1.2684380046 * l + 2.6097574011 * m - 0.3413193965 * s,
                -0.0041960863 * l - 0.7034186147 * m + 1.7076147010 * s)
    }

    /// The sRGB colour at this L and h, with chroma reduced (bisected) until it is in gamut.
    nonisolated func inGamut() -> SRGB {
        func fits(_ c: Double) -> Bool {
            let (r, g, b) = linearRGB(chroma: c)
            let e = 1e-6
            return [r, g, b].allSatisfy { $0 >= -e && $0 <= 1 + e }
        }
        var chroma = C
        if !fits(chroma) {
            var lo = 0.0, hi = C
            for _ in 0..<24 {
                let mid = (lo + hi) / 2
                if fits(mid) { lo = mid } else { hi = mid }
            }
            chroma = lo
        }
        let (r, g, b) = linearRGB(chroma: chroma)
        func enc(_ v: Double) -> Double { ToneMap.encoded(min(max(v, 0), 1)) }
        return SRGB(r: enc(r), g: enc(g), b: enc(b))
    }
}
```

Add to `DockTile.xcodeproj/project.pbxproj` (mirror the `AAIDM001`/`AAIDM002` lines for `IconDepthMetrics.swift`):
1. In `PBXBuildFile`: `		AATPL001 /* TilePalette.swift in Sources */ = {isa = PBXBuildFile; fileRef = AATPL002 /* TilePalette.swift */; };`
2. In `PBXFileReference`: `		AATPL002 /* TilePalette.swift */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = TilePalette.swift; sourceTree = "<group>"; };`
3. In the `AAU00003 /* Utilities */` group children, after `AAIDM002 /* IconDepthMetrics.swift */,`: `				AATPL002 /* TilePalette.swift */,`
4. In the app Sources build phase, after `AAIDM001 /* IconDepthMetrics.swift in Sources */,`: `				AATPL001 /* TilePalette.swift in Sources */,`

- [ ] **Step 4: Run to verify it passes**

Run: TEST(ToneMapTests). Expected: all pass. If `fitIsMinimal` overshoots, the bisection bounds are inverted — fix the code, never widen the tolerance.

- [ ] **Step 5: Commit**

```bash
git add DockTile/Utilities/TilePalette.swift DockTile.xcodeproj/project.pbxproj DockTileTests/Unit/Utilities/ToneMapTests.swift
```
```bash
git commit -m "feat(icons): ToneMap contrast seam (OKLCH lightness fit, WCAG ratio)"
```

---

### Task 2: `TileBackground` model field (schema v9)

**Files:**
- Modify: `DockTile/Models/ConfigurationModels.swift` (struct fields, init, decoder, CodingKeys; new enum after `IconWeight`)
- Modify: `DockTile/Models/ConfigurationSchema.swift`
- Modify: `DockTile/Views/DockTileDetailView.swift:78-92` (`contentSignature`)
- Test: `DockTileTests/Unit/Models/TileBackgroundTests.swift`; extend `DockTileTests/Unit/Managers/DockActionResolutionTests.swift`

**Interfaces:**
- Produces: `enum TileBackground: String, Codable, CaseIterable, Hashable { case colour, mono }`; `DockTileConfiguration.background: TileBackground`; `ConfigurationDefaults.background`; init parameter `background: TileBackground = ConfigurationDefaults.background` (a model default, like every other field — the no-default rule applies to colour-path functions).

- [ ] **Step 1: Write the failing tests**

`DockTileTests/Unit/Models/TileBackgroundTests.swift`:

```swift
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
```

Append to `DockActionResolutionTests` (inside its suite):

```swift
    @Test("Changing the background dirties the tile (contentSignature)")
    func backgroundChangesSignature() {
        let colour = DockTileConfiguration(name: "Media", background: .colour)
        var mono = colour
        mono.background = .mono
        #expect(DockTileDetailView.contentSignature(of: colour) != DockTileDetailView.contentSignature(of: mono))
    }
```

- [ ] **Step 2: Run to verify they fail**

Run: TEST(TileBackgroundTests). Expected: build failure — `cannot find type 'TileBackground'` / `extra argument 'background'`.

- [ ] **Step 3: Implement**

In `ConfigurationModels.swift`, after the `IconWeight` enum:

```swift
// MARK: - Tile Background

/// Where a tile's one colour goes (v9). `.colour` fills the tile (white symbol); `.mono` is white
/// in Light Mode and near-black in Dark Mode with the colour on the symbol. The concrete tones come
/// from `TilePalette` — never stored, so tuning the tone map re-renders every tile consistently.
enum TileBackground: String, Codable, CaseIterable, Hashable {
    case colour
    case mono

    /// Tolerant decode, same reason as `IconWeight`: a key that is present with an unknown value
    /// would otherwise fail the ENTIRE configuration decode. Fall back to the default.
    init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = TileBackground(rawValue: raw) ?? .colour
    }
}
```

In `DockTileConfiguration`:
- add stored property after `iconWeight`: `var background: TileBackground  // v9: Colour fill or Mono (white/near-black)`
- add init parameter after `iconWeight`: `background: TileBackground = ConfigurationDefaults.background,` and assign `self.background = background`
- in `init(from:)` after the v7 block:
  ```swift
          // v9 fields - tile background (old configs are Colour tiles)
          background = try container.decodeIfPresent(TileBackground.self, forKey: .background)
              ?? ConfigurationDefaults.background
  ```
- in `CodingKeys` after `case iconWeight`: `        // v9 fields` / `        case background`

In `ConfigurationSchema.swift` after the v7 default:

```swift
    // v9: Tile background — existing tiles stay Colour
    static let background: TileBackground = .colour
```

In `DockTileDetailView.contentSignature(of:)` after `hasher.combine(config.iconWeight)`: `        hasher.combine(config.background)`

- [ ] **Step 4: Run to verify they pass**

Run: TEST(TileBackgroundTests), then TEST(DockActionResolutionTests), then TEST(DockTileConfigurationTests) (the suite inside `ConfigurationModelsTests.swift`). Expected: all pass, and each run reports a non-zero test count.

- [ ] **Step 5: Commit**

```bash
git add DockTile/Models/ConfigurationModels.swift DockTile/Models/ConfigurationSchema.swift DockTile/Views/DockTileDetailView.swift DockTileTests/Unit/Models/TileBackgroundTests.swift DockTileTests/Unit/Managers/DockActionResolutionTests.swift
```
```bash
git commit -m "feat(model): TileBackground field (schema v9, tolerant decode)"
```

---

### Task 3: `TilePalette` — every colour role, one rule

**Files:**
- Modify: `DockTile/Utilities/TilePalette.swift` (append)
- Modify: `DockTile/Models/ConfigurationModels.swift` (`PresetColor` gains `baseHex` / `lightHex`; `colorTop`/`colorBottom` read them)
- Test: `DockTileTests/Unit/Utilities/TilePaletteTests.swift`

**Interfaces:**
- Consumes: `SRGB`, `ToneMap` (Task 1); `TileBackground` (Task 2); `IconStyle`; `IconDepthMetrics.glyphBottomDarken(style:iconType:nominalSize:)`; `TintColor.darkNeutralTopHex` / `darkNeutralBottomHex`.
- Produces: `TintColor.PresetColor.baseHex: String`, `.lightHex: String`; `TintColor.baseRGB: SRGB`, `TintColor.lightRGB: SRGB`; `enum TilePalette { struct Roles: Equatable { top, bottom, glyph: SRGB }; static func resolve(tint: TintColor, background: TileBackground, style: IconStyle, iconType: IconType) -> Roles; static func resolve(base: SRGB, light: SRGB, background: TileBackground, style: IconStyle, iconType: IconType) -> Roles; static func fillWasDeepened(tint: TintColor) -> Bool }` and constants `lightTop, lightBottom, darkTop, darkBottom`.

- [ ] **Step 1: Write the failing tests**

```swift
//  TilePaletteTests.swift — the colour each renderer draws, per background × style × icon type.
import Foundation
import Testing
@testable import Dock_Tile

@Suite("TilePalette roles")
struct TilePaletteTests {
    private let presets = TintColor.allPresets
    private let customs: [TintColor] = [.custom("#FFFFFF"), .custom("#000000"), .custom("#5F00FF"), .custom("#FFCC00")]

    private func q(_ c: SRGB) -> SRGB {
        SRGB(r: (c.r * 255).rounded() / 255, g: (c.g * 255).rounded() / 255, b: (c.b * 255).rounded() / 255)
    }

    @Test("Mono Light: white→#EFEFF1 tile, symbol clears 3.0 against the darker stop")
    func monoLight() throws {
        for tint in presets + customs {
            for type in [IconType.sfSymbol, .emoji] {
                let r = TilePalette.resolve(tint: tint, background: .mono, style: .defaultStyle, iconType: type)
                #expect(r.top == SRGB(hex: "#FFFFFF"))
                #expect(r.bottom == SRGB(hex: "#EFEFF1"))
                #expect(ToneMap.contrastRatio(q(r.glyph), r.bottom) >= ToneMap.floor, "\(tint)")
            }
        }
    }

    @Test("Dark symbol (Colour or Mono): neutral near-black, SHADED symbol bottom clears 3.0")
    func darkSymbol() throws {
        let shade = try #require(IconDepthMetrics.glyphBottomDarken(style: .dark, iconType: .sfSymbol, nominalSize: 1024))
        for bg in TileBackground.allCases {
            for tint in presets + customs {
                let r = TilePalette.resolve(tint: tint, background: bg, style: .dark, iconType: .sfSymbol)
                #expect(r.top == SRGB(hex: TintColor.darkNeutralTopHex))
                #expect(r.bottom == SRGB(hex: TintColor.darkNeutralBottomHex))
                let shaded = q(r.glyph).darkened(by: Double(shade))
                #expect(ToneMap.contrastRatio(shaded, r.top) >= ToneMap.floor, "\(bg) \(tint)")
            }
        }
    }

    @Test("Mono Dark emoji: neutral near-black (not the darkened tint)")
    func monoDarkEmoji() {
        let r = TilePalette.resolve(tint: .blue, background: .mono, style: .dark, iconType: .emoji)
        #expect(r.top == SRGB(hex: TintColor.darkNeutralTopHex))
    }

    @Test("Colour Dark emoji keeps the darkened-own-tint background (brightness caps 0.22 / 0.13)")
    func colourDarkEmoji() throws {
        let r = TilePalette.resolve(tint: .blue, background: .colour, style: .dark, iconType: .emoji)
        #expect(abs(max(r.top.r, r.top.g, r.top.b) - 0.22) < 1e-9)
        #expect(abs(max(r.bottom.r, r.bottom.g, r.bottom.b) - 0.13) < 1e-9)
        #expect(r.top.b > r.top.r)   // still blue
    }

    @Test("Colour Default: white symbol clears 3.0 against the fill's lighter top; bottom is darker")
    func colourFill() throws {
        for tint in presets + customs {
            let r = TilePalette.resolve(tint: tint, background: .colour, style: .defaultStyle, iconType: .sfSymbol)
            #expect(r.glyph == .white)
            #expect(ToneMap.contrastRatio(.white, q(r.top)) >= ToneMap.floor, "\(tint)")
            // Never lighter at the bottom; strictly darker for every colour that is not already black
            // (a black custom fill has nowhere darker to go — L clamps at 0).
            #expect(ToneMap.relativeLuminance(r.bottom) <= ToneMap.relativeLuminance(r.top), "\(tint) bottom lighter")
            if tint != .custom("#000000") {
                #expect(ToneMap.relativeLuminance(r.bottom) < ToneMap.relativeLuminance(r.top), "\(tint) gradient is flat")
            }
        }
    }

    @Test("Default style is icon-type independent for every background (symbol and emoji share the fill)")
    func defaultIgnoresIconType() {
        for bg in TileBackground.allCases {
            for tint in presets + customs {
                let s = TilePalette.resolve(tint: tint, background: bg, style: .defaultStyle, iconType: .sfSymbol)
                let e = TilePalette.resolve(tint: tint, background: bg, style: .defaultStyle, iconType: .emoji)
                #expect(s.top == e.top && s.bottom == e.bottom, "\(bg) \(tint)")
            }
        }
    }

    @Test("Clear and Tinted ignore background and tint", arguments: [IconStyle.clear, .tinted])
    func greyscaleStylesUnchanged(_ style: IconStyle) {
        let a = TilePalette.resolve(tint: .orange, background: .colour, style: style, iconType: .sfSymbol)
        let b = TilePalette.resolve(tint: .purple, background: .mono, style: style, iconType: .emoji)
        #expect(a == b)
        if style == .tinted {
            #expect(a.glyph == .white)
            #expect(a.top == SRGB(hex: "#8E8E93") && a.bottom == SRGB(hex: "#636366"))
        } else {
            #expect(a.top == SRGB(hex: "#F0F0F2") && a.bottom == SRGB(hex: "#E0E0E4") && a.glyph == SRGB(hex: "#6E6E73"))
        }
    }

    @Test("A malformed custom hex renders the grey preset's tones, never black")
    func malformedCustomFallsBackToGrey() {
        for bad in ["oops", "#12", ""] {
            #expect(TintColor.custom(bad).baseRGB == TintColor.gray.baseRGB, "\(bad)")
        }
    }

    @Test("fillWasDeepened: orange moves, blue (already 4:1 on white) does not")
    func deepenedFlag() {
        #expect(TilePalette.fillWasDeepened(tint: .orange))
        #expect(!TilePalette.fillWasDeepened(tint: .blue))
    }

    @Test("Preset hex tables back the SwiftUI colours (one table, no copies)")
    func presetHexIsTheSource() {
        for p in TintColor.PresetColor.allCases {
            #expect(TintColor.preset(p).baseRGB == SRGB(hex: p.baseHex))
            #expect(TintColor.preset(p).lightRGB == SRGB(hex: p.lightHex))
        }
    }
}
```

- [ ] **Step 2: Run to verify they fail**

Run: TEST(TilePaletteTests). Expected: build failure — `cannot find 'TilePalette' in scope`.

- [ ] **Step 3: Implement**

In `ConfigurationModels.swift`, inside `PresetColor`, replace the bodies of `colorTop` / `colorBottom` with a single hex table:

```swift
        /// Lighter stop (the gradient top before tone-mapping; still the Colour+Dark+emoji source).
        var lightHex: String {
            switch self {
            case .red: return "#FF6B6B"
            case .orange: return "#FFA94D"
            case .green: return "#6BCF7F"
            case .blue: return "#4DABF7"
            case .purple: return "#B197FC"
            case .pink: return "#FF6B9D"
            case .gray: return "#ADB5BD"
            }
        }

        /// The saturated base every tone is derived from (`TilePalette`).
        var baseHex: String {
            switch self {
            case .red: return "#FF3B30"
            case .orange: return "#FF9500"
            case .green: return "#34C759"
            case .blue: return "#007AFF"
            case .purple: return "#AF52DE"
            case .pink: return "#FF2D55"
            case .gray: return "#8E8E93"
            }
        }

        /// Primary color for icon background gradient (top) - lighter shade
        var colorTop: Color { Color(hex: lightHex) }

        /// Secondary color for icon background gradient (bottom) - darker/saturated shade
        var colorBottom: Color { Color(hex: baseHex) }
```

Append to `TilePalette.swift`:

```swift
// MARK: - Tint inputs

extension TintColor {
    /// The saturated base (preset bottom stop / custom hex). A malformed custom hex falls back to
    /// the grey preset — never black (an old hand-edited config must not bake a black tile).
    nonisolated var baseRGB: SRGB {
        switch self {
        case .preset(let p): return SRGB(hex: p.baseHex)!
        case .custom(let hex): return SRGB(hex: hex) ?? SRGB(hex: PresetColor.gray.baseHex)!
        }
    }

    /// The lighter stop, used only by the Colour + Dark + emoji darkened-own-tint background.
    nonisolated var lightRGB: SRGB {
        switch self {
        case .preset(let p): return SRGB(hex: p.lightHex)!
        case .custom: return baseRGB.lighterShade(by: 0.15)
        }
    }
}

// MARK: - TilePalette

/// Every tile colour, per background × style × icon type. See the spec's role table:
/// docs/superpowers/specs/2026-10-13-mono-tile-background-design.md
enum TilePalette {
    struct Roles: Equatable, Sendable {
        let top: SRGB
        let bottom: SRGB
        let glyph: SRGB
    }

    nonisolated static let lightTop = SRGB(hex: "#FFFFFF")!
    nonisolated static let lightBottom = SRGB(hex: "#EFEFF1")!
    nonisolated static let darkTop = SRGB(hex: TintColor.darkNeutralTopHex)!
    nonisolated static let darkBottom = SRGB(hex: TintColor.darkNeutralBottomHex)!
    private nonisolated static let clear = Roles(top: SRGB(hex: "#F0F0F2")!, bottom: SRGB(hex: "#E0E0E4")!, glyph: SRGB(hex: "#6E6E73")!)
    private nonisolated static let tinted = Roles(top: SRGB(hex: "#8E8E93")!, bottom: SRGB(hex: "#636366")!, glyph: .white)
    /// OKLCH lightness step from a Colour fill's top stop to its bottom stop.
    nonisolated static let colourFillBottomStep = -0.06

    nonisolated static func resolve(
        tint: TintColor, background: TileBackground, style: IconStyle, iconType: IconType
    ) -> Roles {
        resolve(base: tint.baseRGB, light: tint.lightRGB, background: background, style: style, iconType: iconType)
    }

    /// Raw-colour form (sidebar Settings badges carry a `Color`, not a `TintColor`).
    nonisolated static func resolve(
        base: SRGB, light: SRGB, background: TileBackground, style: IconStyle, iconType: IconType
    ) -> Roles {
        switch style {
        case .clear:
            return clear
        case .tinted:
            return tinted
        case .defaultStyle:
            switch background {
            case .colour:
                let top = colourFill(base)
                return Roles(top: top, bottom: ToneMap.shiftingLightness(top, by: colourFillBottomStep), glyph: .white)
            case .mono:
                return Roles(top: lightTop, bottom: lightBottom, glyph: monoLightGlyph(base))
            }
        case .dark:
            if background == .colour && iconType == .emoji {
                // An emoji can't be recoloured, so a Colour emoji tile keeps its own hue, darkened.
                return Roles(top: light.cappingBrightness(0.22), bottom: base.cappingBrightness(0.13), glyph: .white)
            }
            return Roles(top: darkTop, bottom: darkBottom, glyph: darkGlyph(base))
        }
    }

    /// Whether a Colour tile's fill had to move to clear the floor (drives the "Deepened" hint).
    nonisolated static func fillWasDeepened(tint: TintColor) -> Bool {
        colourFill(tint.baseRGB) != tint.baseRGB
    }

    // MARK: Fits — each tests the weakest pair the renderer actually draws

    /// White symbol against the fill's LIGHTER (top) stop.
    private nonisolated static func colourFill(_ base: SRGB) -> SRGB {
        ToneMap.fit(base, direction: .darker) { ToneMap.contrastRatio(.white, $0) >= ToneMap.searchTarget }
    }

    /// Unshaded symbol top against the tile's DARKER (bottom) stop.
    private nonisolated static func monoLightGlyph(_ base: SRGB) -> SRGB {
        ToneMap.fit(base, direction: .darker) { ToneMap.contrastRatio($0, lightBottom) >= ToneMap.searchTarget }
    }

    /// The symbol's SHADED bottom against the tile's LIGHTER (top) stop.
    private nonisolated static func darkGlyph(_ base: SRGB) -> SRGB {
        let shade = Double(IconDepthMetrics.glyphBottomDarken(style: .dark, iconType: .sfSymbol, nominalSize: 1024) ?? 0)
        return ToneMap.fit(base, direction: .lighter) {
            ToneMap.contrastRatio($0.darkened(by: shade), darkTop) >= ToneMap.searchTarget
        }
    }
}
```

If the compiler reports `IconStyle`/`IconDepthMetrics` as main-actor isolated when called from a `nonisolated` context, mark the called members `nonisolated` at their declaration (they are pure value functions) — do not drop `nonisolated` here.

- [ ] **Step 4: Run to verify they pass**

Run: TEST(TilePaletteTests), then TEST(TintColorExtendedTests). Expected: all pass (the hex refactor keeps every existing `colorTop`/`colorBottom` value).

- [ ] **Step 5: Commit**

```bash
git add DockTile/Utilities/TilePalette.swift DockTile/Models/ConfigurationModels.swift DockTileTests/Unit/Utilities/TilePaletteTests.swift
```
```bash
git commit -m "feat(icons): TilePalette — one colour rule per background × style"
```

---

### Task 3b: Spike — how does a Mono symbol tile render under Tinted and Clear? (throwaway)

**Why:** the vendored compiler builds the Tintable rendition on the LIGHT gradient (`Vendor/actool/src/icon_bundle.rs:1591-1610`), so a Mono tile's tinted pass starts from WHITE. icon-system.md V1 says the system's Tinted pass reads relief from layer alpha. Neither a 2-layer document (coloured light glyph reused for tinted) nor a 3-layer one (white tinted-only glyph) is proven. The spec says "no new document structure"; keep a third layer only if 2 layers fail. Decided with Karthik 2026-10-13.

**Files:** scratchpad only — nothing in the repo changes, nothing is committed. No dev or prod tile, Dock plist or helper is touched.

- [ ] **Step 1: Build three documents** in `<scratchpad>/tinted-spike/` from `docs/icon-spike-fixtures/devtile-fix.icon` (copy it three times):
  - `colour.icon` — baseline: orange fill (`#FF9500 → #E08000`), white `glyph-light`, orange-lifted `glyph-dark`, 2 layers (fixture model).
  - `mono2.icon` — fill `#FFFFFF → #EFEFF1`, dark specialization `#2C2C2E → #1C1C1E`, tinted `#8E8E93 → #636366`; `glyph-light.png` = `star.fill` in `#B35F00`, `glyph-dark.png` in `#FFB35C`; 2 layers, hidden-specializations exactly as the fixture.
  - `mono3.icon` — as `mono2` plus `glyph-tinted.png` (white) and the 3-entry hidden-specializations from Task 4's `monoTintedLayerPartitionsAppearances` test.
  Render the PNGs with a scratchpad Swift script that draws `NSImage(systemSymbolName: "star.fill")` at 1024×1024 into an explicit-pixel `NSBitmapImageRep` filled with the colour (transparent elsewhere).
- [ ] **Step 2: Compile** each with the bundled compiler, using the app's exact arguments:
  `Vendor/actool/target/release/docktile-actool <doc>.icon --compile <out> --app-icon <name> --output-partial-info-plist <out>/partial.plist --platform macosx --target-device mac --minimum-deployment-target 15.0`
  then `assetutil --info <out>/Assets.car` must list Aqua, DarkAqua and Tintable stacks for each.
- [ ] **Step 3: Render each appearance** without the Dock: wrap each car in `<scratchpad>/tinted-spike/<name>.app` (`Contents/Info.plist` with `CFBundleIdentifier com.docktile.dev.spike.<name>`, `CFBundlePackageType APPL`, `CFBundleIconName AppIcon`; `Contents/Resources/Assets.car`), register it with a scratchpad Swift script calling `LSRegisterURL(url, true)`, and save `NSWorkspace.shared.icon(forFile:)` at 512 px to PNG. Ask Karthik to switch System Settings → Appearance → Icon & widget style to **Tinted**, then **Clear** (light and dark), re-running the render after each switch (`killall iconservicesagent` between switches if the render does not change).
- [ ] **Step 4: Decide.** Look at the PNGs (Read the files) and measure the glyph-vs-background luminance difference at the glyph centre vs a background point. **2 layers pass** if `mono2`'s Tinted and Clear renders show the star with relief at least as visible as the `colour` baseline's. Then:
  - **2 layers pass →** in Task 4 skip every step and code block marked **[3-layer]**, and in Task 5 skip the `.sfSymbol where config.background == .mono` case and the `monoTintedLayerIsWhite` test (keep `colourTintedEqualsLight`, and add the same byte-identity assertion for `.mono`: with 2 layers the tinted layer must equal the light one). Update the spec sentence "IconDocumentBuilder's interface is unchanged" as confirmed.
  - **2 layers fail, 3 pass →** build Task 4/5 as written and amend the spec's Renderers section to say a Mono symbol `.icon` has three glyph layers, with the spike's PNGs as the evidence (describe them; do not commit images).
  - **Both fail →** stop and report to Karthik with the PNGs; do not start Task 4.
- [ ] **Step 5: Clean up** — delete the spike `.app` bundles (Launch Services forgets a deleted bundle on its next scan). Record the outcome and the decisive measurements in one paragraph in the Task 9 icon-system.md update.

---

### Task 4: Route the colour adapters through the palette; `.icon` tinted-only layer

**Files:**
- Modify: `DockTile/Managers/IconStyleManager.swift:540-690` (`colors`, `nsColors`, `badgeColors`; delete `darkGlyphLuminanceFloor` if orphaned)
- Modify: `DockTile/Utilities/DeclarativeIconPipeline.swift:30-118` (`LayerSpec.Exclusive.tinted`, `layerDict`) **[3-layer]**
- Modify: `DockTile/Views/DockTileSidebarView.swift:142,153` (badge call sites unchanged in shape; verify)
- Modify: `Vendor/actool/src/icon_bundle.rs` (test only) **[3-layer]**
- Modify (compile fixes, `background: .colour`): every caller of `colors(for:` / `nsColors(for:` listed by `grep -rn "colors(for:\|nsColors(for:" DockTile DockTileTests`
- Test: `DockTileTests/Unit/Models/TintColorTests.swift` (rewrite `DarkGlyphTreatmentTests`, `BadgeColorMappingTests`), `DockTileTests/Unit/Utilities/IconDocumentBuilderTests.swift`, `DockTileTests/Unit/Utilities/GlyphLayerRenderTests.swift:82-90` (`appearanceDrivesGlyphColour` still asserts the 0.55 floor at :85 — rewrite to the 3:1 rule, below)

Items marked **[3-layer]** are built only if Task 3b's spike chose three layers.

**Interfaces:**
- Consumes: `TilePalette.resolve` (Task 3).
- Produces: `TintColor.colors(for: IconStyle, iconType: IconType = .sfSymbol, background: TileBackground) -> (backgroundTop: Color, backgroundBottom: Color, foreground: Color)`; `TintColor.nsColors(for:iconType:background:)` (same shape, `NSColor`); `TintColor.badgeColors(for:tint:)` unchanged signature; `SRGB.color: Color`, `SRGB.nsColor: NSColor` (declared in IconStyleManager.swift — `TilePalette.swift` stays framework-free); **[3-layer]** `IconDocumentBuilder.LayerSpec.Exclusive.tinted`.

- [ ] **Step 1: Write the failing tests**

Replace the body of `DarkGlyphTreatmentTests` in `TintColorTests.swift` (the `liftedForDarkGlyph` cases go: the 3:1 palette rule replaces the luminance floor, and `TilePaletteTests.darkSymbol` now owns that guarantee). Keep the suite name; new content:

```swift
@Suite("Dark-style tinted-glyph rendering")
struct DarkGlyphTreatmentTests {

    @Test("Dark + SF Symbol: neutral near-black background AND a 3:1 tinted glyph (#5F00FF regression)")
    func darkSymbolUsesNeutralBackgroundAndVisibleGlyph() throws {
        let result = TintColor.custom("#5F00FF").nsColors(for: .dark, iconType: .sfSymbol, background: .colour)
        let top = try #require(result.backgroundTop.usingColorSpace(.sRGB))
        let expected = try #require(SRGB(hex: TintColor.darkNeutralTopHex))
        #expect(abs(top.redComponent - expected.r) < 0.002)
        let fg = try #require(result.foreground.usingColorSpace(.sRGB))
        let glyph = SRGB(r: fg.redComponent, g: fg.greenComponent, b: fg.blueComponent)
        #expect(ToneMap.contrastRatio(glyph.darkened(by: 0.10), expected) >= ToneMap.floor)
        #expect(fg.blueComponent > fg.greenComponent)   // still violet
    }

    @Test("SwiftUI colors(for:) mirrors nsColors(for:) for every background × style × icon type")
    func swiftUIMirrorsNSColors() throws {
        let tints: [TintColor] = [.custom("#5F00FF"), .preset(.blue), .preset(.orange)]
        for background in TileBackground.allCases {
            for style in IconStyle.allCases {
                for iconType in [IconType.sfSymbol, .emoji] {
                    for tint in tints {
                        let ns = tint.nsColors(for: style, iconType: iconType, background: background)
                        let sw = tint.colors(for: style, iconType: iconType, background: background)
                        let label = "\(background) / \(style) / \(iconType) / \(tint)"
                        try expectSameColour(ns.foreground, sw.foreground, "foreground \(label)")
                        try expectSameColour(ns.backgroundTop, sw.backgroundTop, "backgroundTop \(label)")
                        try expectSameColour(ns.backgroundBottom, sw.backgroundBottom, "backgroundBottom \(label)")
                    }
                }
            }
        }
    }

    private func expectSameColour(
        _ ns: NSColor, _ swiftUI: Color, _ label: String,
        sourceLocation: SourceLocation = #_sourceLocation
    ) throws {
        let a = try #require(ns.usingColorSpace(.sRGB), "\(label): NSColor not convertible", sourceLocation: sourceLocation)
        let b = try #require(NSColor(swiftUI).usingColorSpace(.sRGB), "\(label): Color not convertible", sourceLocation: sourceLocation)
        #expect(abs(a.redComponent - b.redComponent) < 0.002, "\(label) red", sourceLocation: sourceLocation)
        #expect(abs(a.greenComponent - b.greenComponent) < 0.002, "\(label) green", sourceLocation: sourceLocation)
        #expect(abs(a.blueComponent - b.blueComponent) < 0.002, "\(label) blue", sourceLocation: sourceLocation)
    }

    @Test("Non-Dark styles ignore iconType through the adapter too (Default fill is shared)")
    func nonDarkStylesIgnoreIconType() throws {
        for background in TileBackground.allCases {
            let symbol = TintColor.preset(.purple).nsColors(for: .defaultStyle, iconType: .sfSymbol, background: background)
            let emoji = TintColor.preset(.purple).nsColors(for: .defaultStyle, iconType: .emoji, background: background)
            let s = try #require(symbol.backgroundTop.usingColorSpace(.sRGB))
            let e = try #require(emoji.backgroundTop.usingColorSpace(.sRGB))
            #expect(abs(s.redComponent - e.redComponent) < 0.001)
            #expect(abs(s.greenComponent - e.greenComponent) < 0.001)
            #expect(abs(s.blueComponent - e.blueComponent) < 0.001)
        }
    }

    @Test("Adapters are the palette: nsColors equals TilePalette.resolve exactly")
    func adapterIsThePalette() throws {
        let tint = TintColor.preset(.green)
        let roles = TilePalette.resolve(tint: tint, background: .mono, style: .defaultStyle, iconType: .sfSymbol)
        let fg = try #require(tint.nsColors(for: .defaultStyle, iconType: .sfSymbol, background: .mono).foreground.usingColorSpace(.sRGB))
        #expect(abs(fg.redComponent - roles.glyph.r) < 1e-6)
        #expect(abs(fg.greenComponent - roles.glyph.g) < 1e-6)
        #expect(abs(fg.blueComponent - roles.glyph.b) < 1e-6)
    }
}
```

Replace `BadgeColorMappingTests.darkStyleLiftsTint` and `.defaultStyleKeepsTint` with:

```swift
    @Test("Dark style: neutral near-black background, glyph from the palette's 3:1 rule")
    func darkStyleUsesPalette() throws {
        let badge = TintColor.badgeColors(for: .dark, tint: Color(hex: "#1A0533"))
        let top = try #require(NSColor(badge.top).usingColorSpace(.sRGB))
        #expect(abs(top.redComponent - TilePalette.darkTop.r) < 0.002)
        let fg = try #require(NSColor(badge.foreground).usingColorSpace(.sRGB))
        let glyph = SRGB(r: fg.redComponent, g: fg.greenComponent, b: fg.blueComponent)
        #expect(ToneMap.contrastRatio(glyph.darkened(by: 0.10), TilePalette.darkTop) >= ToneMap.floor)
    }

    @Test("Default style: the Colour-tile fill rule with a white glyph")
    func defaultStyleUsesColourFill() throws {
        let badge = TintColor.badgeColors(for: .defaultStyle, tint: Color(hex: "#FF9500"))
        let expected = TilePalette.resolve(base: SRGB(hex: "#FF9500")!, light: SRGB(hex: "#FF9500")!,
                                           background: .colour, style: .defaultStyle, iconType: .sfSymbol)
        let top = try #require(NSColor(badge.top).usingColorSpace(.sRGB))
        #expect(abs(top.redComponent - expected.top.r) < 0.002 && abs(top.greenComponent - expected.top.g) < 0.002)
        let fg = try #require(NSColor(badge.foreground).usingColorSpace(.sRGB))
        #expect(fg.redComponent > 0.99 && fg.greenComponent > 0.99 && fg.blueComponent > 0.99)
    }
```

In `grayscaleStylesMatchTileMapping`, change `TintColor.blue.colors(for: style, iconType: .sfSymbol)` to `TintColor.blue.colors(for: style, iconType: .sfSymbol, background: .colour)`. (`darkEmojiKeepsDarkenedTint` is dropped with the old suite body — `TilePaletteTests.colourDarkEmoji` owns it; `nonDarkStylesIgnoreIconType` is kept above, extended to both backgrounds.)

In `GlyphLayerRenderTests.appearanceDrivesGlyphColour`, replace lines 82–85 (the `expected` / `unlifted` lines and the `darkGlyphLuminanceFloor` expectation) with:

```swift
        let foreground = violet.nsColors(for: .dark, iconType: .sfSymbol, background: .colour).foreground
        let expected = Self.perceivedLuminance(foreground)
        let unlifted = Self.perceivedLuminance(try #require(NSColor(hex: "#5F00FF")))
        let fg = try #require(foreground.usingColorSpace(.sRGB))
        // The seam lifted at all: the shaded glyph bottom clears 3:1 on the near-black tile.
        #expect(ToneMap.contrastRatio(SRGB(r: fg.redComponent, g: fg.greenComponent, b: fg.blueComponent).darkened(by: 0.10),
                                      TilePalette.darkTop) >= ToneMap.floor)
```

and update its `generateGlyphLayerPNG` call and comments ("lift" → "tone map"); lines 86–97 stay. Rename the `perceivedLuminance` doc comment's `liftedForDarkGlyph` reference to "the old luminance lift (replaced by `TilePalette`)".

**[3-layer]** Append to `IconDocumentBuilderTests`:

```swift
    @Test("Mono symbol model: three layers, each visible in exactly one appearance")
    func monoTintedLayerPartitionsAppearances() throws {
        let json = makeJSON(layers: [
            .init(name: "glyph-light", imageName: "glyph-light.png", exclusiveTo: .light),
            .init(name: "glyph-dark", imageName: "glyph-dark.png", exclusiveTo: .dark),
            .init(name: "glyph-tinted", imageName: "glyph-tinted.png", exclusiveTo: .tinted)
        ])
        let groups = try #require(json["groups"] as? [[String: Any]])
        let layers = try #require(groups.first?["layers"] as? [[String: Any]])
        func hidden(_ i: Int) throws -> [String: Bool] {
            let specs = try #require(layers[i]["hidden-specializations"] as? [[String: Any]])
            var out: [String: Bool] = [:]
            for s in specs { out[(s["appearance"] as? String) ?? "default"] = s["value"] as? Bool }
            return out
        }
        #expect(try hidden(0) == ["default": false, "dark": true, "tinted": true])
        #expect(try hidden(1) == ["default": true, "dark": false, "tinted": true])
        #expect(try hidden(2) == ["default": true, "dark": true, "tinted": false])
    }

    @Test("Colour symbol model is unchanged: no tinted entries when no layer is tinted-exclusive")
    func colourDocumentHasNoTintedEntries() throws {
        let json = makeJSON(layers: [
            .init(name: "glyph-light", imageName: "glyph-light.png", exclusiveTo: .light),
            .init(name: "glyph-dark", imageName: "glyph-dark.png", exclusiveTo: .dark)
        ])
        let groups = try #require(json["groups"] as? [[String: Any]])
        let layers = try #require(groups.first?["layers"] as? [[String: Any]])
        for layer in layers {
            let specs = try #require(layer["hidden-specializations"] as? [[String: Any]])
            #expect(specs.count == 2)
            #expect(!specs.contains { ($0["appearance"] as? String) == "tinted" })
        }
    }
```

**[3-layer]** Add to the `#[cfg(test)]` module of `Vendor/actool/src/icon_bundle.rs`, after `hidden_specializations_partition_the_stacks`. (This pins only stack partitioning; whether the Tintable rendition LOOKS right was Task 3b's job.)

```rust
    /// Dock Tile's Mono symbol tiles add a THIRD, tinted-exclusive layer (the light glyph is
    /// coloured; the tinted appearance needs a white one). Each stack must hold exactly one.
    #[test]
    fn tinted_hidden_specialization_gets_its_own_stack() {
        let dir = tempfile::TempDir::new().expect("tempdir");
        let assets = dir.path().join("Assets");
        std::fs::create_dir_all(&assets).unwrap();
        for name in ["glyph-light.png", "glyph-dark.png", "glyph-tinted.png"] {
            let img = image::RgbaImage::from_pixel(8, 8, image::Rgba([255, 255, 255, 255]));
            img.save(assets.join(name)).expect("write png");
        }
        let parsed: crate::icon_json::IconJson = serde_json::from_value(serde_json::json!({
            "fill": "automatic",
            "groups": [{"layers": [
                {"name": "glyph-light", "image-name": "glyph-light.png", "hidden-specializations": [
                    {"value": false}, {"appearance": "dark", "value": true}, {"appearance": "tinted", "value": true}]},
                {"name": "glyph-dark", "image-name": "glyph-dark.png", "hidden-specializations": [
                    {"value": true}, {"appearance": "dark", "value": false}, {"appearance": "tinted", "value": true}]},
                {"name": "glyph-tinted", "image-name": "glyph-tinted.png", "hidden-specializations": [
                    {"value": true}, {"appearance": "dark", "value": true}, {"appearance": "tinted", "value": false}]}
            ]}]
        }))
        .expect("parse icon.json");
        let stem = |layers: &[StackLayer]| -> Vec<String> {
            layers.iter().map(|l| l.source.file_stem().and_then(|s| s.to_str()).unwrap_or_default().to_string()).collect()
        };
        use crate::icon_effects::Appearance;
        assert_eq!(stem(&collect_stack_layers(dir.path(), &parsed, Appearance::Light)), vec!["glyph-light".to_string()]);
        assert_eq!(stem(&collect_stack_layers(dir.path(), &parsed, Appearance::Dark)), vec!["glyph-dark".to_string()]);
        assert_eq!(stem(&collect_stack_layers(dir.path(), &parsed, Appearance::Tinted)), vec!["glyph-tinted".to_string()]);
    }
```

- [ ] **Step 2: Run to verify they fail**

**[3-layer]** Run: `cargo test --manifest-path Vendor/actool/Cargo.toml tinted_hidden_specialization` — Expected: PASS already (the compiler resolves every appearance generically; this pins it). If it FAILS, stop and report back.
Run: TEST(DarkGlyphTreatmentTests). Expected: build failure — `extra argument 'background' in call`. **[3-layer]** TEST(IconDocumentBuilderTests): build failure — `type 'Exclusive' has no member 'tinted'`.

- [ ] **Step 3: Implement**

**[3-layer]** `DeclarativeIconPipeline.swift` — replace `enum Exclusive { case light, dark }` and its doc comment with:

```swift
        /// The ONE appearance a layer is exclusive to. `.tinted` exists for Mono symbol tiles,
        /// whose light glyph is coloured while the tinted appearance needs a white one. A document
        /// with a `.tinted` layer emits an explicit `tinted` entry on EVERY exclusive layer, so no
        /// layer is ever hidden in every appearance; a document without one keeps the two-entry
        /// form (tinted inherits the light layer — the Colour tile model, byte-identical JSON).
        enum Exclusive { case light, dark, tinted }
```

and in `iconJSON` replace `"groups": [["layers": layers.map(layerDict)]],` with:

```swift
            "groups": [["layers": layers.map { layerDict($0, separatesTinted: separatesTinted) }]],
```

adding before the `return`: `        let separatesTinted = layers.contains { $0.exclusiveTo == .tinted }`. Change `layerDict`:

```swift
    private static func layerDict(_ layer: LayerSpec, separatesTinted: Bool) -> [String: Any] {
        var dict: [String: Any] = [
            "name": layer.name,
            "image-name": layer.imageName,
            "fill": "none",
            "position": [
                "scale": 1.0,
                "translation-in-points": [0, 0]
            ]
        ]
        if let exclusiveTo = layer.exclusiveTo {
            // Polarity: hidden unless this IS the layer for that appearance.
            var specs: [[String: Any]] = [
                ["value": exclusiveTo != .light],
                ["appearance": IconAppearance.dark.rawValue, "value": exclusiveTo != .dark]
            ]
            if separatesTinted {
                specs.append(["appearance": IconAppearance.tinted.rawValue, "value": exclusiveTo != .tinted])
            }
            dict["hidden-specializations"] = specs
        }
        return dict
    }
```

`IconStyleManager.swift` — replace the three function bodies (keep `darkNeutralTopHex` / `darkNeutralBottomHex`; keep each doc comment's first line, replace the rest with "Thin adapter over `TilePalette.resolve` — no colour logic here."):

```swift
    func colors(for style: IconStyle, iconType: IconType = .sfSymbol, background: TileBackground)
        -> (backgroundTop: Color, backgroundBottom: Color, foreground: Color) {
        let r = TilePalette.resolve(tint: self, background: background, style: style, iconType: iconType)
        return (r.top.color, r.bottom.color, r.glyph.color)
    }

    static func badgeColors(for style: IconStyle, tint: Color) -> (top: Color, bottom: Color, foreground: Color) {
        let ns = NSColor(tint).usingColorSpace(.sRGB) ?? NSColor(srgbRed: 0.557, green: 0.557, blue: 0.576, alpha: 1)
        let base = SRGB(r: ns.redComponent, g: ns.greenComponent, b: ns.blueComponent)
        let r = TilePalette.resolve(base: base, light: base, background: .colour, style: style, iconType: .sfSymbol)
        return (r.top.color, r.bottom.color, r.glyph.color)
    }

    func nsColors(for style: IconStyle, iconType: IconType = .sfSymbol, background: TileBackground)
        -> (backgroundTop: NSColor, backgroundBottom: NSColor, foreground: NSColor) {
        let r = TilePalette.resolve(tint: self, background: background, style: style, iconType: iconType)
        return (r.top.nsColor, r.bottom.nsColor, r.glyph.nsColor)
    }
```

Add to `IconStyleManager.swift` (it already imports SwiftUI and AppKit; `TilePalette.swift` stays framework-free as its header promises), just above the `extension TintColor` that holds `colors`/`nsColors`:

```swift
// MARK: - TilePalette → framework colours

extension SRGB {
    var color: Color { Color(.sRGB, red: r, green: g, blue: b, opacity: 1) }
    var nsColor: NSColor { NSColor(srgbRed: r, green: g, blue: b, alpha: 1) }
}
```

Fix every resulting compile error by adding `background: .colour` — in this task ONLY the call sites that have no tile config (tests; `IconGenerator`/`DockTileIconPreview`/`HelperBundleManager` call sites will get the real value in Tasks 5–6, so pass `.colour` there for now and leave a `// Task 5/6 threads config.background` comment that those tasks delete).

Then delete orphans you created: run `grep -rn "liftedForDarkGlyph\|darkGlyphLuminanceFloor" DockTile DockTileTests`; delete `NSColor.liftedForDarkGlyph`, `Color.liftedForDarkGlyph` and `TintColor.darkGlyphLuminanceFloor` if the grep shows no remaining callers. Do the same for `darkenedForDarkMode` (both) and `nsColorTop` / `nsColorBottom` / `nsColor` (`AppearanceManager.swift`). Update the header comment of `AppearanceManager.swift` to list only what remains.

- [ ] **Step 4: Run to verify they pass**

Run: TEST(IconDocumentBuilderTests), TEST(DarkGlyphTreatmentTests), TEST(BadgeColorMappingTests), TEST(TilePaletteTests). Expected: pass.
Then TEST(all). Expected: failures ONLY in tests that pin today's Colour Default fill or the 0.55 lift (e.g. pixel colour checks in `IconGeneratorTests` / `IconGeneratorContentTests`). For each: confirm the failure is the intended deepening (new value == `TilePalette.resolve(...)`), then update the expectation to the palette value. Never loosen a tolerance to make it pass.

- [ ] **Step 5: Commit**

```bash
git add -A DockTile DockTileTests Vendor/actool/src/icon_bundle.rs
```
```bash
git commit -m "feat(icons): colour adapters read TilePalette; .icon tinted-only layer"
```

---

### Task 5: Renderers thread `background` (declarative, fallback, macOS 15 bake)

**Files:**
- Modify: `DockTile/Utilities/IconGenerator.swift` — `generateIcon` (51), legacy `generateIcon(tintColor:symbol:size:)` (200), the two `generateIcns` overloads (832, 904), the two `generatePreview` overloads (940, 961), `generateGlyphLayerPNG` (1012), `generateFallbackIcns` (1095), `fallbackIcon` (1116)
- Modify: `DockTile/Managers/HelperBundleManager.swift` — `installDeclarativeIcon` (889; fills move into a new pure seam), `declarativeLayerSpecs` (956), the legacy branch's `IconGenerator.generateIcns(` call (search for it in `generateHelperBundle`)
- Test: `DockTileTests/Unit/Utilities/GlyphLayerRenderTests.swift`, `DockTileTests/Unit/Utilities/IconGeneratorContentTests.swift`, `DockTileTests/Unit/Utilities/IconDocumentBuilderTests.swift`; compile fixes in `IconGeneratorTests`, `LegacyIcnsMarginTests`, `LegacyIcnsDockFixtureTests`, `IconCompilerTests`, `HelperBundleLifecycleTests`

**Interfaces:**
- Consumes: `nsColors(for:iconType:background:)` (Task 4), **[3-layer]** `LayerSpec.Exclusive.tinted` (Task 4).
- Produces: `IconGenerator.generateIcon(tintColor:iconType:iconValue:iconScale:iconWeight:background:size:iconStyle:)`, `generateIcns(…, background: …)`, `generatePreview(…, background: …)`, `generateGlyphLayerPNG(appearance:tintColor:background:iconType:iconValue:iconScale:iconWeight:canvas:)`, `generateFallbackIcns(tintColor:background:iconType:iconValue:iconScale:iconWeight:outputURL:)` — `background` has no default in any of them; `HelperBundleManager.declarativeFillsP3(for: DockTileConfiguration) throws -> DeclarativeFills` (`nonisolated static`, internal) where `struct DeclarativeFills { let lightTop, lightBottom, darkTop, darkBottom, tintedTop, tintedBottom: (r: Double, g: Double, b: Double) }`.

- [ ] **Step 1: Write the failing tests**

Append to `GlyphLayerRenderTests` (inside the suite; it already has PNG-decoding helpers — reuse its existing helper for "the colour of the most opaque pixel"; if none exists, add this one):

```swift
    /// Average colour of the pixels whose alpha is ≥ 0.9 (the glyph body).
    private func glyphBodyColour(_ png: Data) throws -> SRGB {
        let rep = try #require(NSBitmapImageRep(data: png))
        var sum = (r: 0.0, g: 0.0, b: 0.0), n = 0.0
        for y in stride(from: 0, to: rep.pixelsHigh, by: 4) {
            for x in stride(from: 0, to: rep.pixelsWide, by: 4) {
                guard let c = rep.colorAt(x: x, y: y)?.usingColorSpace(.sRGB), c.alphaComponent >= 0.9 else { continue }
                sum.r += c.redComponent; sum.g += c.greenComponent; sum.b += c.blueComponent; n += 1
            }
        }
        try #require(n > 0, "no opaque glyph pixels")
        return SRGB(r: sum.r / n, g: sum.g / n, b: sum.b / n)
    }

    /// **[3-layer]** — with 2 layers, replace this test by asserting `layer(.tinted) == layer(.light)` for `.mono` too.
    @Test("Mono symbol: light layer is the coloured tone, tinted layer is white")
    func monoTintedLayerIsWhite() throws {
        func layer(_ a: IconAppearance) throws -> Data {
            try IconGenerator.generateGlyphLayerPNG(
                appearance: a, tintColor: .preset(.orange), background: .mono,
                iconType: .sfSymbol, iconValue: "star.fill", iconScale: 14, iconWeight: .medium, canvas: 256)
        }
        let light = try glyphBodyColour(try layer(.light))
        let tinted = try glyphBodyColour(try layer(.tinted))
        #expect(tinted.r > 0.8 && tinted.g > 0.8 && tinted.b > 0.8, "tinted glyph not white: \(tinted)")
        #expect(light.r > light.b + 0.2, "light glyph lost the orange: \(light)")
        // Contrast of the fitted tone is TilePaletteTests' job; this test pins only which layer gets which colour.
    }

    @Test("Colour symbol: tinted layer stays byte-identical to light (the two-layer document)")
    func colourTintedEqualsLight() throws {
        func layer(_ a: IconAppearance) throws -> Data {
            try IconGenerator.generateGlyphLayerPNG(
                appearance: a, tintColor: .preset(.orange), background: .colour,
                iconType: .sfSymbol, iconValue: "star.fill", iconScale: 14, iconWeight: .medium, canvas: 256)
        }
        #expect(try layer(.light) == layer(.tinted))
    }
```

Append to `IconGeneratorContentTests`:

```swift
    @Test("macOS 15 bake: a Mono Default tile's background is white, its Dark variant near-black")
    func legacyMonoBackgrounds() throws {
        func centreEdge(_ style: IconStyle) throws -> NSColor {
            let image = IconGenerator.generateIcon(
                tintColor: .preset(.blue), iconType: .sfSymbol, iconValue: "star.fill",
                iconScale: 10, iconWeight: .medium, background: .mono,
                size: CGSize(width: 256, height: 256), iconStyle: style)
            let rep = try #require(image.representations.first as? NSBitmapImageRep)
            // Inside the inset shape, left of the (small, scale-10) glyph.
            return try #require(rep.colorAt(x: 64, y: 128)?.usingColorSpace(.sRGB))
        }
        let light = try centreEdge(.defaultStyle)
        #expect(light.redComponent > 0.9 && light.greenComponent > 0.9 && light.blueComponent > 0.9)
        let dark = try centreEdge(.dark)
        #expect(dark.redComponent < 0.25 && dark.greenComponent < 0.25 && dark.blueComponent < 0.25)
    }
```

Append to `IconDocumentBuilderTests` (spec row: a Mono `icon.json` must carry the light gradient by default and the dark neutrals for `dark`). Expectations are computed independently in the test from the hex constants, not from the seam:

```swift
    private func p3(_ hex: String) throws -> String {
        let s = try #require(SRGB(hex: hex))
        let c = try #require(NSColor(srgbRed: s.r, green: s.g, blue: s.b, alpha: 1).usingColorSpace(.displayP3))
        return String(format: "display-p3:%.5f,%.5f,%.5f,1.00000", c.redComponent, c.greenComponent, c.blueComponent)
    }

    @Test("Mono icon.json: default fill is #FFFFFF→#EFEFF1, dark is #2C2C2E→#1C1C1E, tinted unchanged")
    func monoFills() throws {
        let fills = try HelperBundleManager.declarativeFillsP3(for: DockTileConfiguration(name: "Media", tintColor: .blue, background: .mono))
        let json = IconDocumentBuilder.iconJSON(
            fillTopP3: fills.lightTop, fillBottomP3: fills.lightBottom,
            darkFillTopP3: fills.darkTop, darkFillBottomP3: fills.darkBottom,
            tintedFillTopP3: fills.tintedTop, tintedFillBottomP3: fills.tintedBottom, layers: [])
        let specs = try #require(json["fill-specializations"] as? [[String: Any]])
        func stops(_ i: Int) throws -> [String] {
            let value = try #require(specs[i]["value"] as? [String: Any])
            return try #require(value["linear-gradient"] as? [String])
        }
        #expect(try stops(0) == [p3("#FFFFFF"), p3("#EFEFF1")])
        #expect(try stops(1) == [p3("#2C2C2E"), p3("#1C1C1E")])
        #expect(try stops(2) == [p3("#8E8E93"), p3("#636366")])
    }
```

(Add `import AppKit` to `IconDocumentBuilderTests.swift` if it is not already imported.)

- [ ] **Step 2: Run to verify they fail**

Run: TEST(GlyphLayerRenderTests). Expected: build failure — `extra argument 'background'`.

- [ ] **Step 3: Implement**

`IconGenerator.swift`:
- `generateIcon` (51): add parameter `background: TileBackground,` after `iconWeight`; line 114 becomes `let colors = tintColor.nsColors(for: iconStyle, iconType: iconType, background: background)`.
- Legacy `generateIcon(tintColor:symbol:size:)` (200): pass `background: .colour` (it has no tile).
- Both `generateIcns` overloads (832, 904) and both `generatePreview` overloads (940, 961): add `background: TileBackground,` after `iconWeight` (or after `iconValue` where there is no weight) and pass it to every `generateIcon(` call inside; their callers get `config.background` where a config exists, `.colour` otherwise.
- `generateGlyphLayerPNG`: add `background: TileBackground,` after `tintColor`; replace line 1052 with:
  ```swift
          // The tinted appearance's glyph is the TINTED style's colour (white — the system tints
          // what we supply) while its depth stays the light treatment. For a Colour tile this is
          // the same white as light, so the tinted layer stays byte-identical to light; for a Mono
          // tile the light glyph is coloured and the tinted one must not be.
          let colourStyle: IconStyle = (appearance == .tinted && iconType != .emoji) ? .tinted : style
          let colors = tintColor.nsColors(for: colourStyle, iconType: iconType, background: background)
  ```
  and update the doc comment's "`.light`/`.tinted` → white" sentence to "`.light` → the palette's light glyph (white for Colour, the fitted tone for Mono), `.tinted` → white, `.dark` → the palette's dark glyph".
- `generateFallbackIcns` / `fallbackIcon`: add `background: TileBackground,` after `tintColor`, thread it through; line 1156 becomes `let colors = tintColor.nsColors(for: .defaultStyle, iconType: iconType, background: background)`.

`HelperBundleManager.swift`:
- `installDeclarativeIcon`: move lines 895–905's colour reads into a pure, testable seam and call it:
  ```swift
      struct DeclarativeFills {
          let lightTop, lightBottom, darkTop, darkBottom, tintedTop, tintedBottom: (r: Double, g: Double, b: Double)
      }

      /// The `.icon` background fills for a tile, Display-P3 — read from `TilePalette` through
      /// `nsColors`, so the compiled icon, the fallback `.icns` and the preview cannot drift.
      nonisolated static func declarativeFillsP3(for config: DockTileConfiguration) throws -> DeclarativeFills {
          let light = config.tintColor.nsColors(for: .defaultStyle, iconType: config.iconType, background: config.background)
          let dark = config.tintColor.nsColors(for: .dark, iconType: config.iconType, background: config.background)
          let tinted = config.tintColor.nsColors(for: .tinted, iconType: config.iconType, background: config.background)
          return DeclarativeFills(
              lightTop: try p3Components(light.backgroundTop), lightBottom: try p3Components(light.backgroundBottom),
              darkTop: try p3Components(dark.backgroundTop), darkBottom: try p3Components(dark.backgroundBottom),
              tintedTop: try p3Components(tinted.backgroundTop), tintedBottom: try p3Components(tinted.backgroundBottom))
      }
  ```
  and `installDeclarativeIcon` builds its JSON from `let fills = try Self.declarativeFillsP3(for: config)`. The `generateFallbackIcns(` call passes `background: config.background`.
- `declarativeLayerSpecs`: `layerPNG` passes `background: config.background`; **[3-layer]** replace the `.sfSymbol` case with:
  ```swift
          case .sfSymbol where config.background == .mono:
              // Mono: the light glyph is coloured, so tinted needs its own white layer.
              return (
                  [
                      .init(name: "glyph-light", imageName: "glyph-light.png", exclusiveTo: .light),
                      .init(name: "glyph-dark", imageName: "glyph-dark.png", exclusiveTo: .dark),
                      .init(name: "glyph-tinted", imageName: "glyph-tinted.png", exclusiveTo: .tinted)
                  ],
                  [
                      "glyph-light.png": try layerPNG(.light),
                      "glyph-dark.png": try layerPNG(.dark),
                      "glyph-tinted.png": try layerPNG(.tinted)
                  ]
              )
          case .sfSymbol:
  ```
  and extend the function's doc comment: "THREE layers for a Mono symbol tile (light coloured, dark, tinted white)."
- Legacy branch `IconGenerator.generateIcns(`: pass `background: config.background`.

Delete the temporary `// Task 5/6 threads config.background` comments from Task 4 in these files. Fix remaining test compile errors with `background: .colour`.

- [ ] **Step 4: Run to verify they pass**

Run: TEST(GlyphLayerRenderTests), TEST(IconGeneratorContentTests), TEST(IconDocumentBuilderTests), TEST(IconCompilerTests), then TEST(all). Expected: all pass.

- [ ] **Step 5: Commit**

```bash
git add -A DockTile DockTileTests
```
```bash
git commit -m "feat(icons): renderers thread the tile background (3-layer Mono .icon)"
```

---

### Task 6: Live preview, sidebar and grid overlay follow the background

**Files:**
- Modify: `DockTile/Components/DockTileIconPreview.swift` (stored property, full initializer, `styleColors`, `fromConfig`, `#Preview`s)
- Modify: `DockTile/Views/DockTileDetailView.swift:349` (pass `editedConfig.background`)
- Modify: `DockTile/Views/SmartAddSheet.swift:62,162` (only if they use the full initializer: pass `.colour`)
- Test: `DockTileTests/Unit/Components/IconPreviewGeometryTests.swift` (compile fix) + new `DockTileTests/Unit/Components/IconPreviewBackgroundTests.swift`

**Interfaces:**
- Consumes: `colors(for:iconType:background:)`.
- Produces: `DockTileIconPreview.init(tintColor:iconType:iconValue:iconScale:iconWeight:background:size:)` (no default on `background`; the two legacy initializers set `.colour`); `DockTileIconPreview.fromConfig` passes `config.background`; `let tileBackground: TileBackground` readable on the view. (Named `tileBackground`, not `background`: a stored `background` on a `View` collides with SwiftUI's `.background(_:)` modifier.) Plus `var forcedStyle: IconStyle? = nil`, `func forcing(_ style: IconStyle?) -> Self`, and the pure seam `nonisolated static func displayStyle(forced: IconStyle?, raw: RawStyleToken, colorScheme: ColorScheme) -> IconStyle` — the Background chips and the Mono Light/Dark hero ALWAYS show canonical Default/Dark whatever the user's system icon style (decided with Karthik 2026-10-13: they explain what Mono means; under a fixed Dark/Clear/Tinted style the pair would otherwise render identically).

- [ ] **Step 1: Write the failing test**

```swift
import Testing
@testable import Dock_Tile

@Suite("Preview background threading")
@MainActor
struct IconPreviewBackgroundTests {
    @Test("fromConfig carries the tile's background (sidebar rows show Mono tiles as Mono)")
    func fromConfigCarriesBackground() {
        let config = DockTileConfiguration(name: "Media", background: .mono)
        #expect(DockTileIconPreview.fromConfig(config, size: 24).tileBackground == .mono)
    }

    @Test("Legacy initializers (no config) are Colour")
    func legacyInitIsColour() {
        #expect(DockTileIconPreview(tintColor: .blue, iconType: .sfSymbol, iconValue: "star", size: 24).tileBackground == .colour)
    }

    @Test("A forced style wins over a fixed system icon style (canonical Light/Dark previews)")
    func forcedStyleWins() {
        // ClearAutomatic would render Clear in both schemes — the forced pair must still differ.
        let raw = RawStyleToken.value("ClearAutomatic")
        #expect(DockTileIconPreview.displayStyle(forced: .defaultStyle, raw: raw, colorScheme: .dark) == .defaultStyle)
        #expect(DockTileIconPreview.displayStyle(forced: .dark, raw: raw, colorScheme: .light) == .dark)
        #expect(DockTileIconPreview.displayStyle(forced: nil, raw: raw, colorScheme: .light) == .clear)
    }
}
```

(Confirm `RawStyleToken`'s case name for a present string value by reading its declaration — `grep -rn "enum RawStyleToken" DockTile` — and use it verbatim.)

- [ ] **Step 2: Run to verify it fails**

Run: TEST(IconPreviewBackgroundTests). Expected: build failure — `value of type 'DockTileIconPreview' has no member 'tileBackground'`.

- [ ] **Step 3: Implement**

In `DockTileIconPreview`:
- add `let tileBackground: TileBackground` after `iconWeight`;
- the two legacy initializers set `self.tileBackground = .colour`;
- the full initializer gains `background: TileBackground,` after `iconWeight` (no default) and assigns `self.tileBackground = background`;
- `styleColors` becomes `tintColor.colors(for: iconStyle, iconType: iconType, background: tileBackground)`;
- add `var forcedStyle: IconStyle? = nil` beside `rawStyleOverride`, and route `iconStyle` through a pure seam:
  ```swift
      /// A forced style (Customise's canonical Light/Dark previews) wins; otherwise the live
      /// system style resolved against this view's colour scheme.
      nonisolated static func displayStyle(forced: IconStyle?, raw: RawStyleToken, colorScheme: ColorScheme) -> IconStyle {
          forced ?? IconStyle.forDisplay(raw: raw, colorScheme: colorScheme, fallback: .defaultStyle)
      }

      private var iconStyle: IconStyle {
          Self.displayStyle(forced: forcedStyle, raw: rawStyleOverride ?? iconStyleManager.rawStyle, colorScheme: colorScheme)
      }
  ```
  (If `IconStyle.forDisplay` is main-actor isolated, mark it `nonisolated` — it is a pure function.)
- add the call-site helper used by Customise (Task 8):
  ```swift
      /// Copy of this preview pinned to `style` (`nil` = follow the live system style).
      func forcing(_ style: IconStyle?) -> Self {
          var copy = self
          copy.forcedStyle = style
          return copy
      }
  ```
- `fromConfig` passes `background: config.background`;
- the `#Preview` blocks that use the full initializer pass `background: .colour` (add one `#Preview("Mono")` showing `.mono` beside `.colour` for the same tint).

`DockTileDetailView.swift:349`: pass `background: editedConfig.background`. `SmartAddSheet.swift`: pass `background: .colour` where the compiler requires it. (`CustomiseTileView` is rewritten in Task 8.) For `CustomiseTileView.swift:123` pass `background: editedConfig.background` now so the build stays green.

- [ ] **Step 4: Run to verify it passes**

Run: TEST(IconPreviewBackgroundTests), TEST(IconPreviewGeometryTests). Expected: pass. Build the app (`xcodebuild -project DockTile.xcodeproj -scheme DockTile -configuration Debug build`) — expected: BUILD SUCCEEDED.

- [ ] **Step 5: Commit**

```bash
git add -A DockTile DockTileTests
```
```bash
git commit -m "feat(ui): icon previews render the tile background"
```

---

### Task 7: Strings

**Files:**
- Modify: `DockTile/Constants/AppStrings.swift` (inside `enum Label`, after `colour`)
- Modify: `DockTile/Resources/Localizable.xcstrings` (textual insert before `"label.iconSize": {`)
- Test: `DockTileTests/Unit/Constants/AppStringsTests.swift`

**Interfaces:**
- Produces: `AppStrings.Label.background`, `.backgroundColour`, `.backgroundMono`, `.backgroundHintColour`, `.backgroundHintMono`, `.backgroundColourAccessibility`, `.backgroundMonoAccessibility`, `.symbolColour`, `.colourHintFills`, `.colourHintDeepened`, `.colourHintToned`, `.colourHintEmoji`, `.previewLight`, `.previewDark`.

| Swift name | key | en-GB / en-AU | en-US |
|---|---|---|---|
| background | label.background | Background | Background |
| backgroundColour | label.background.colour | Colour | Color |
| backgroundMono | label.background.mono | Mono | Mono |
| backgroundHintColour | label.background.hint.colour | Filled with your colour | Filled with your color |
| backgroundHintMono | label.background.hint.mono | White in Light Mode, black in Dark Mode | White in Light Mode, black in Dark Mode |
| backgroundColourAccessibility | label.background.colour.accessibility | Colour, filled with your colour | Color, filled with your color |
| backgroundMonoAccessibility | label.background.mono.accessibility | Mono, white in Light Mode and black in Dark Mode | (same) |
| symbolColour | label.symbolColour | Symbol Colour | Symbol Color |
| colourHintFills | label.colour.hint.fills | Fills the tile | Fills the tile |
| colourHintDeepened | label.colour.hint.deepened | Deepened slightly so the symbol stays clear | (same) |
| colourHintToned | label.colour.hint.toned | Toned for Light and Dark | (same) |
| colourHintEmoji | label.colour.hint.emoji | Emoji keep their own colours | Emoji keep their own colors |
| previewLight | label.preview.light | Light | Light |
| previewDark | label.preview.dark | Dark | Dark |

- [ ] **Step 1: Write the failing tests**

Append to `AppStringsTests` (its `localizedString(for:locale:)` helper parses the xcstrings file):

```swift
    @Test("Mono tile strings: every key exists in all three locales")
    func monoTileKeysExist() {
        let keys = ["label.background", "label.background.colour", "label.background.mono",
                    "label.background.hint.colour", "label.background.hint.mono",
                    "label.background.colour.accessibility", "label.background.mono.accessibility",
                    "label.symbolColour", "label.colour.hint.fills", "label.colour.hint.deepened",
                    "label.colour.hint.toned", "label.colour.hint.emoji",
                    "label.preview.light", "label.preview.dark"]
        for key in keys {
            for locale in ["en-GB", "en-US", "en-AU"] {
                // The helper returns "Key '…' not found for locale '…'" on a miss — never "".
                #expect(!localizedString(for: key, locale: locale).hasPrefix("Key '"), "\(key) missing in \(locale)")
            }
        }
        // Exact copy for the strings the user reads first.
        #expect(localizedString(for: "label.background", locale: "en-GB") == "Background")
        #expect(localizedString(for: "label.background.hint.mono", locale: "en-GB") == "White in Light Mode, black in Dark Mode")
        #expect(localizedString(for: "label.symbolColour", locale: "en-US") == "Symbol Color")
        #expect(localizedString(for: "label.preview.dark", locale: "en-AU") == "Dark")
    }

    @Test("Mono tile strings spell colour per locale")
    func monoTileSpelling() {
        for key in ["label.symbolColour", "label.background.hint.colour", "label.colour.hint.emoji",
                    "label.background.colour", "label.background.colour.accessibility"] {
            #expect(localizedString(for: key, locale: "en-US").localizedCaseInsensitiveContains("color"), "\(key) en-US")
            #expect(!localizedString(for: key, locale: "en-US").localizedCaseInsensitiveContains("colour"), "\(key) en-US")
            #expect(localizedString(for: key, locale: "en-GB").localizedCaseInsensitiveContains("colour"), "\(key) en-GB")
            #expect(localizedString(for: key, locale: "en-AU").localizedCaseInsensitiveContains("colour"), "\(key) en-AU")
        }
        #expect(!AppStrings.Label.symbolColour.isEmpty)
        #expect(!AppStrings.Label.previewDark.isEmpty)
    }
```

- [ ] **Step 2: Run to verify they fail**

Run: TEST(AppStringsTests). Expected: build failure — `type 'AppStrings.Label' has no member 'symbolColour'`.

- [ ] **Step 3: Implement**

In `AppStrings.Label`, after `colour`, one accessor per table row, in the existing form:

```swift
        static let background = NSLocalizedString(
            "label.background",
            value: "Background",
            comment: "Customise Tile: label for the Colour/Mono background choice"
        )
```

(…and the other 13, each with its key, en-GB value as `value:`, and a one-line comment naming where it appears.)

Insert the xcstrings entries with a scratchpad script (never commit it) that reads the file as TEXT, builds each entry in the file's exact style, and inserts EACH entry immediately before the first existing top-level key that sorts after it (case-insensitive), so Xcode's next save does not reorder the file:

```python
import json, pathlib, sys
path = pathlib.Path(sys.argv[1])
rows = [  # key, comment, en-GB/en-AU, en-US
    ("label.background", "Customise Tile: background row label", "Background", "Background"),
    ("label.background.colour", "Customise Tile: Colour background chip", "Colour", "Color"),
    ("label.background.mono", "Customise Tile: Mono background chip", "Mono", "Mono"),
    ("label.background.hint.colour", "Customise Tile: hint under Background when Colour", "Filled with your colour", "Filled with your color"),
    ("label.background.hint.mono", "Customise Tile: hint under Background when Mono", "White in Light Mode, black in Dark Mode", "White in Light Mode, black in Dark Mode"),
    ("label.background.colour.accessibility", "VoiceOver label for the Colour chip", "Colour, filled with your colour", "Color, filled with your color"),
    ("label.background.mono.accessibility", "VoiceOver label for the Mono chip", "Mono, white in Light Mode and black in Dark Mode", "Mono, white in Light Mode and black in Dark Mode"),
    ("label.symbolColour", "Customise Tile: colour row label for a Mono tile", "Symbol Colour", "Symbol Color"),
    ("label.colour.hint.fills", "Customise Tile: colour hint, Colour tile", "Fills the tile", "Fills the tile"),
    ("label.colour.hint.deepened", "Customise Tile: colour hint when the fill was darkened for contrast", "Deepened slightly so the symbol stays clear", "Deepened slightly so the symbol stays clear"),
    ("label.colour.hint.toned", "Customise Tile: colour hint, Mono tile", "Toned for Light and Dark", "Toned for Light and Dark"),
    ("label.colour.hint.emoji", "Customise Tile: colour hint, Mono emoji tile (row disabled)", "Emoji keep their own colours", "Emoji keep their own colors"),
    ("label.preview.light", "Customise Tile: caption under the Light Mode preview", "Light", "Light"),
    ("label.preview.dark", "Customise Tile: caption under the Dark Mode preview", "Dark", "Dark"),
]
def unit(v): return '          "stringUnit": {\n            "state": "translated",\n            "value": %s\n          }' % json.dumps(v, ensure_ascii=False)
def entry(k, c, gb, us):
    return ('    %s: {\n      "comment": %s,\n      "extractionState": "manual",\n      "localizations": {\n'
            '        "en-AU": {\n%s\n        },\n        "en-GB": {\n%s\n        },\n        "en-US": {\n%s\n        }\n      }\n    },\n'
            % (json.dumps(k), json.dumps(c), unit(gb), unit(gb), unit(us)))
import re
text = path.read_text()
assert '"label.background"' not in text
for row in sorted(rows, key=lambda r: r[0].casefold(), reverse=True):
    existing = re.findall(r'^    "([^"\n]+)": \{$', text, flags=re.M)
    after = next((k for k in existing if k.casefold() > row[0].casefold()), None)
    assert after is not None, row[0]
    anchor = '    %s: {\n' % json.dumps(after)
    assert text.count(anchor) == 1, after
    text = text.replace(anchor, entry(*row) + anchor)
json.loads(text)
path.write_text(text)
```

Run it with `python3 -I <scratchpad>/insert_mono_strings.py DockTile/Resources/Localizable.xcstrings`, then confirm `git diff --stat DockTile/Resources/Localizable.xcstrings` shows only insertions (≈ 14 × 24 lines). Check placement against Xcode's own order: open the catalog in Xcode, add and remove a dummy string, save, and `git diff` must show no moved blocks (revert the dummy).

- [ ] **Step 4: Run to verify they pass**

Run: TEST(AppStringsTests). Expected: pass.

- [ ] **Step 5: Commit**

```bash
git add DockTile/Constants/AppStrings.swift DockTile/Resources/Localizable.xcstrings DockTileTests/Unit/Constants/AppStringsTests.swift
```
```bash
git commit -m "feat(strings): mono tile background copy (en-GB/en-US/en-AU)"
```

---

### Task 8: Customise Tile UI — Background row, colour row states, two-up hero, title band

**Files:**
- Modify: `DockTile/Views/CustomiseTileView.swift` (title band, studio canvas, inspector card, colour section, new background section + chip, diagnostics)
- Modify: `DockTile/Views/DockTileConfigurationView.swift:371-536` (`paneTitleItem`, `PaneTitleLabel`, `PaneTitleBand`, `paneTitleBand`)
- Modify: `DockTile/Views/DockTileDetailView.swift:594-598` (analytics param)
- Test: `DockTileTests/Unit/Views/CustomiseColourRowStateTests.swift`

**Interfaces:**
- Consumes: `TileBackground`, `TilePalette.fillWasDeepened(tint:)`, `AppStrings.Label.*` (Task 7), `DockTileIconPreview(... background:size:)` (Task 6).
- Produces: `CustomiseTileView.ColourRowState { fillsTile, deepened, toned, emojiLocked }` with `.isDisabled: Bool`, `.usesSymbolLabel: Bool`; `nonisolated static func colourRowState(background:iconType:fillDeepened:) -> ColourRowState`; `View.paneTitleBand(_ title: String, subtitle: String? = nil)`.

- [ ] **Step 1: Write the failing test**

```swift
import Testing
@testable import Dock_Tile

@Suite("Customise colour row state")
@MainActor   // ColourRowState is nested in a View (main-actor) type
struct CustomiseColourRowStateTests {
    @Test("Colour tile: fills, or deepened when the fill moved — but never 'so the symbol stays clear' for an emoji")
    func colourTile() {
        #expect(CustomiseTileView.colourRowState(background: .colour, iconType: .sfSymbol, fillDeepened: false) == .fillsTile)
        #expect(CustomiseTileView.colourRowState(background: .colour, iconType: .sfSymbol, fillDeepened: true) == .deepened)
        #expect(CustomiseTileView.colourRowState(background: .colour, iconType: .emoji, fillDeepened: true) == .fillsTile)
    }

    @Test("Mono tile: toned for symbols, locked (but not reset) for emoji")
    func monoTile() {
        let symbol = CustomiseTileView.colourRowState(background: .mono, iconType: .sfSymbol, fillDeepened: true)
        #expect(symbol == .toned && !symbol.isDisabled && symbol.usesSymbolLabel)
        let emoji = CustomiseTileView.colourRowState(background: .mono, iconType: .emoji, fillDeepened: false)
        #expect(emoji == .emojiLocked && emoji.isDisabled && emoji.usesSymbolLabel)
    }

    @Test("Only the Mono + emoji state disables the swatches")
    func onlyEmojiLockedDisables() {
        for s in [CustomiseTileView.ColourRowState.fillsTile, .deepened, .toned] { #expect(!s.isDisabled) }
    }
}
```

- [ ] **Step 2: Run to verify it fails**

Run: TEST(CustomiseColourRowStateTests). Expected: build failure — `type 'CustomiseTileView' has no member 'colourRowState'`.

- [ ] **Step 3: Implement**

**Title band** (`DockTileConfigurationView.swift`): give `paneTitleItem`, `PaneTitleLabel` and `PaneTitleBand` an optional `subtitle: String?` and render it inside the SAME title item (one `VStack`, so the macOS 26 `.sharedBackgroundVisibility(.hidden)` treatment and the single-`.toolbar` spacer rule are untouched):

```swift
@ToolbarContentBuilder
private func paneTitleItem(title: String, subtitle: String? = nil) -> some ToolbarContent {
    if #available(macOS 26.0, *) {
        ToolbarItem(placement: .navigation) { PaneTitleLabel(title: title, subtitle: subtitle) }
            .sharedBackgroundVisibility(.hidden)   // no Liquid Glass capsule around a title
    } else {
        ToolbarItem(placement: .navigation) { PaneTitleLabel(title: title, subtitle: subtitle) }
    }
}

private struct PaneTitleLabel: View {
    let title: String
    var subtitle: String? = nil
    static let leadingAdjustment: CGFloat = 12   // (keep the existing doc comment above this)

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .accessibilityAddTraits(.isHeader)
            if let subtitle {
                Text(subtitle)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(.leading, Self.leadingAdjustment)
    }
}
```

`PaneTitleBand` gains `var subtitle: String? = nil` passed to `paneTitleItem`; `PaneTitleBandWithActions` passes nothing (unchanged). `paneTitleBand(_ title: String, subtitle: String? = nil)` forwards it. Every other pane is unchanged because the default is `nil`.

**CustomiseTileView** — add the pure seam (inside the struct):

```swift
    enum ColourRowState: Equatable {
        case fillsTile, deepened, toned, emojiLocked
        var isDisabled: Bool { self == .emojiLocked }
        var usesSymbolLabel: Bool { self == .toned || self == .emojiLocked }
    }

    /// Colour row copy + enablement. Mono + emoji locks the swatches (an emoji can't take a colour)
    /// but never resets `tintColor` — switching back to a symbol restores the same colour.
    nonisolated static func colourRowState(background: TileBackground, iconType: IconType, fillDeepened: Bool) -> ColourRowState {
        switch background {
        case .mono: return iconType == .emoji ? .emojiLocked : .toned
        // The "Deepened … so the symbol stays clear" copy names a symbol; an emoji tile has none.
        case .colour: return (fillDeepened && iconType == .sfSymbol) ? .deepened : .fillsTile
        }
    }

    private var colourRow: ColourRowState {
        Self.colourRowState(background: editedConfig.background, iconType: editedConfig.iconType,
                            fillDeepened: TilePalette.fillWasDeepened(tint: editedConfig.tintColor))
    }
```

Title: replace `.paneTitleBand(AppStrings.Navigation.customiseTile)` with
`.paneTitleBand(configManager.displayName(for: editedConfig.id), subtitle: AppStrings.Navigation.customiseTile)`.

Studio canvas: replace the body of `studioCanvas` with

```swift
        HStack(alignment: .top, spacing: 28) {
            switch editedConfig.background {
            case .colour:
                heroTile(style: nil, caption: nil, symbol: nil)
            case .mono:
                heroTile(style: .defaultStyle, caption: AppStrings.Label.previewLight, symbol: "sun.max")
                heroTile(style: .dark, caption: AppStrings.Label.previewDark, symbol: "moon")
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.bottom, 12)
        .padding(.top, 4) // Tight offset to clear the toolbar area
        .background(StudioCanvasBackgroundView().ignoresSafeArea(edges: .top))
```

(the tile name below the preview is removed — it now heads the title band) and add:

```swift
    /// One hero preview. `style` forces canonical Default/Dark for the Mono pair — whatever the
    /// user's system icon style — so the two always explain what Mono means; `nil` follows the
    /// live style (Colour tiles show one preview, as before).
    @ViewBuilder
    private func heroTile(style: IconStyle?, caption: String?, symbol: String?) -> some View {
        VStack(spacing: 8) {
            ZStack {
                DockTileIconPreview(
                    tintColor: editedConfig.tintColor,
                    iconType: editedConfig.iconType,
                    iconValue: editedConfig.iconValue,
                    iconScale: editedConfig.iconScale,
                    iconWeight: editedConfig.iconWeight,
                    background: editedConfig.background,
                    size: 100
                )
                .forcing(style)
                if editedConfig.background == .mono {
                    IconGridOverlay(size: 100, lineColor: style == .dark ? .white.opacity(0.25) : .black.opacity(0.15))
                } else {
                    IconGridOverlay(size: 100, backgroundColor: editedConfig.tintColor)
                }
            }
            if let caption, let symbol {
                Label(caption, systemImage: symbol)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
            }
        }
    }
```

Inspector card: insert `backgroundSection` + a separator (the same `Rectangle().fill(Color(nsColor: .quinaryLabel)).frame(height: 1)`) BEFORE `colourSection`. Add:

```swift
    // MARK: - Background Section

    private var backgroundSection: some View {
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 2) {
                Text(AppStrings.Label.background)
                    .font(.system(size: 13))
                    .foregroundColor(.primary)
                Text(editedConfig.background == .colour ? AppStrings.Label.backgroundHintColour : AppStrings.Label.backgroundHintMono)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            HStack(spacing: 16) {
                ForEach(TileBackground.allCases, id: \.self) { option in
                    BackgroundChip(option: option, config: editedConfig, isSelected: editedConfig.background == option) {
                        editedConfig.background = option
                    }
                }
            }
        }
        .frame(height: 76)
    }
```

and, at file scope:

```swift
/// A 44pt tile thumbnail for the Background choice. Colour shows the tile filled; Mono is split
/// on the diagonal into its Light and Dark renders, so the one chip explains "follows the system".
private struct BackgroundChip: View {
    let option: TileBackground
    let config: DockTileConfiguration
    let isSelected: Bool
    let action: () -> Void

    private let side: CGFloat = 44

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                thumbnail
                    .frame(width: side, height: side)
                    .overlay {
                        // 2pt ring, 2pt gap: the 2pt stroke is centred on a path 3pt outside the tile.
                        RoundedRectangle(cornerRadius: side * 0.225 + 3, style: .continuous)
                            .stroke(isSelected ? Color.accentColor : .clear, lineWidth: 2)
                            .padding(-3)
                    }
                Text(option == .colour ? AppStrings.Label.backgroundColour : AppStrings.Label.backgroundMono)
                    .font(.system(size: 11, weight: isSelected ? .semibold : .regular))
                    .foregroundStyle(isSelected ? .primary : .secondary)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(option == .colour ? AppStrings.Label.backgroundColourAccessibility : AppStrings.Label.backgroundMonoAccessibility)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    /// Canonical styles (forced), never the live system style: under a fixed Clear/Tinted system
    /// style the two chips would otherwise be indistinguishable.
    @ViewBuilder
    private var thumbnail: some View {
        let preview = { (style: IconStyle) in
            DockTileIconPreview(
                tintColor: config.tintColor, iconType: config.iconType, iconValue: config.iconValue,
                iconScale: config.iconScale, iconWeight: config.iconWeight, background: option, size: side
            )
            .forcing(style)
        }
        switch option {
        case .colour:
            preview(.defaultStyle)
        case .mono:
            ZStack {
                preview(.defaultStyle).clipShape(DiagonalHalf(upperLeading: true))
                preview(.dark).clipShape(DiagonalHalf(upperLeading: false))
            }
        }
    }
}

/// The triangle above (or below) the top-trailing → bottom-leading diagonal.
private struct DiagonalHalf: Shape {
    let upperLeading: Bool
    func path(in rect: CGRect) -> Path {
        var p = Path()
        if upperLeading {
            p.move(to: CGPoint(x: rect.minX, y: rect.minY))
            p.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
            p.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        } else {
            p.move(to: CGPoint(x: rect.maxX, y: rect.minY))
            p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
            p.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        }
        p.closeSubpath()
        return p
    }
}
```

Colour section: replace `colourSection` with

```swift
    private var colourSection: some View {
        let state = colourRow
        return HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 2) {
                Text(state.usesSymbolLabel ? AppStrings.Label.symbolColour : AppStrings.Label.colour)
                    .font(.system(size: 13))
                    .foregroundColor(.primary)
                Text(colourHint(state))
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            // `.disabled` on the swatches only; the ROW carries the fade and the tooltip —
            // `.help` never fires inside a disabled subtree (development.md).
            colourPickerStrip
                .disabled(state.isDisabled)
        }
        .frame(height: 56)
        .opacity(state.isDisabled ? 0.45 : 1)
        .help(state.isDisabled ? AppStrings.Label.colourHintEmoji : "")
    }

    private func colourHint(_ state: ColourRowState) -> String {
        switch state {
        case .fillsTile: return AppStrings.Label.colourHintFills
        case .deepened: return AppStrings.Label.colourHintDeepened
        case .toned: return AppStrings.Label.colourHintToned
        case .emojiLocked: return AppStrings.Label.colourHintEmoji
        }
    }
```

Diagnostics — add beside the other `.onChange` handlers:

```swift
        .onChange(of: editedConfig.background) { _, newValue in
            DiagnosticsLog.shared.ui("Customise → Background \(newValue.rawValue) for '\(editedConfig.name)'")
        }
```

Analytics — `DockTileDetailView.swift:594-598` adds `"background": configToSave.background.rawValue` to the dictionary.

- [ ] **Step 4: Run to verify it passes**

Run: TEST(CustomiseColourRowStateTests), then TEST(all). Expected: all pass. Then rebuild SIGNED (no `CODE_SIGNING_ALLOWED=NO`) and gate on `codesign --verify "<DerivedData>/Build/Products/Debug/Dock Tile Dev.app"` before launching (driving-the-dev-build.md).

Hands-on in the dev app (capture by window ID via `Scripts/dev-capture.sh`, never a screen rect):
- Customise a symbol tile → Background shows Colour selected, colour row reads "Colour / Fills the tile" (or "Deepened…" for orange).
- Pick Mono → two hero tiles (Light/Dark captions), row reads "Symbol Colour / Toned for Light and Dark", sidebar icon turns white.
- Switch to an emoji → row fades, swatches don't respond, hovering the row shows "Emoji keep their own colours"; back to a symbol → same colour still selected.
- Title band reads the tile name with "Customise Tile" beneath; Tile Detail / Settings panes' titles are unchanged. Runnable check (driving-the-dev-build.md single-`to` form): `osascript -e 'tell application "System Events" to tell (first process whose unix id is <PID>) to get value of every static text of toolbar 1 of window 1'` must list the tile name and "Customise Tile" on the Customise pane, and only the pane title on General.
- Set System Settings → Appearance → Icon & widget style to **Clear**: the Mono hero still shows a white "Light" tile and a near-black "Dark" tile, and the two Background chips still differ.
- VoiceOver (⌘F5) on the chips reads "Mono, white in Light Mode and black in Dark Mode, selected".

- [ ] **Step 5: Commit**

```bash
git add -A DockTile DockTileTests
```
```bash
git commit -m "feat(ui): Customise Tile background choice, colour row states, two-up hero"
```

---

### Task 9: Dock verification, docs and rules

**Files:**
- Modify: `.claude/rules/icon-system.md` (Dark-style table row; new "Tile background (Mono) and tone map" section)
- Modify: `.claude/rules/testing.md` (seam list: add `ToneMap.fit`/`.contrastRatio`, `TilePalette.resolve`, `CustomiseTileView.colourRowState`; replace the `liftedForDarkGlyph` entry)
- Modify: `.claude/skills/icon-rendering/SKILL.md` (seam table row for `TilePalette`; "three layers for Mono symbol tiles" under the appearance authoring model)

- [ ] **Step 1: Dock check on macOS 26 (manual, dev build)**

Add to Dock one tile each: symbol/Colour (orange), symbol/Mono (blue), emoji/Mono, brand glyph/Mono. For each, switch System Settings → Appearance → Icon & widget style through Default, Dark, Clear, Tinted, and Light/Dark Mode. Expected: Mono is white with a blue symbol in Light, near-black with a lighter blue symbol in Dark, and in Tinted/Clear matches what Task 3b's chosen variant rendered (the star clearly visible); the orange Colour tile is visibly deeper than before. Confirm one compiled car with `assetutil --info "<helper>/Contents/Resources/Assets.car"` shows three `IconImageStack` renditions (Aqua, DarkAqua, Tintable).

- [ ] **Step 2: macOS 15 leg**

Push the branch and run `gh workflow run ci.yml --ref feat/mono-tile -f dock_check=true`. Expected: `test-macos-15` reports `macOS 15: N passed, 0 failed` (N ≥ 600) and `dock-check-macos-15`'s `measure.txt` verdict passes. Read the verdict from `measure.txt`, not the job colour.

- [ ] **Step 3: Update the rules**

`icon-system.md`: replace the Dark row's "lifted on perceived luminance to a `0.55` floor via `liftedForDarkGlyph`" with "fitted by `TilePalette` so its shaded bottom clears 3:1 against `#2C2C2E`"; add a section "Tile background (Mono) and tone map" stating: one stored colour, roles derived by `TilePalette` (pure, `TilePalette.swift`); Mono = `#FFFFFF→#EFEFF1` / `#2C2C2E→#1C1C1E`; every role ≥ 3:1 (`ToneMap.floor`, searched at 3.1), **measured on the chosen colours before decorative sheens** — macOS 26 Dock icons carry no baked sheen (the system adds its glass); the macOS 15 bake and the in-app preview add a glyph/surface sheen that is decoration, not part of the promise (decided 2026-10-13); Dock icons cannot react to Increase Contrast (no such icon appearance), so the target is fixed; the Customise chips and Mono hero always render canonical Default/Dark (`DockTileIconPreview.forcing`), whatever the system icon style; Task 3b's spike result (2 vs 3 glyph layers for a Mono symbol `.icon`, with its measurements — and, if 3, that `tinted_hidden_specialization_gets_its_own_stack` pins the partition); Apple's `system-light`/`system-dark` fills were considered and not adopted (values unpublished → contrast not computable).

`testing.md` and the icon-rendering skill: add the seams named in **Files** above.

- [ ] **Step 4: Run the full suite once more**

Run: TEST(all). Expected: all pass.

- [ ] **Step 5: Commit**

```bash
git add .claude/rules/icon-system.md .claude/rules/testing.md .claude/skills/icon-rendering/SKILL.md
```
```bash
git commit -m "docs(rules): mono tile background, TilePalette tone map"
```

Then run `stage-gate --dev` on the branch diff before pushing (CLAUDE.md Gates).

**Release note (for whoever tags the release, not this plan):** EVERY existing Colour tile changes look on update — the gradient now starts from the saturated colour (e.g. blue's top #4DABF7 → #007AFF) and colours under 3:1 (orange, green, pink, red, grey) deepen further; Dark-appearance symbols use the new 3:1 rule. Register the `background` event parameter as a GA4 custom definition.
