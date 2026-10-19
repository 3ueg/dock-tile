# Apps Tile Face Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A tile can show a grid of its own apps' icons (first nine, tile order, 2×2 for 1–4 / 3×3 for 5+) on Apple's `system-light` / `system-dark` glass instead of a symbol or emoji, chosen on Customise Tile's three-card Style picker (**App Preview · Symbol · Emoji**). App Preview is the default for NEW tiles; a config missing the field loads as the glyph face.

**Architecture:** One optional model field (`iconFace: IconFace`; new tiles `.apps`, a missing key decodes to `.glyph`, unknown values tolerant → `.glyph`) joins `iconSignature`. One pure geometry + material seam (`AppsFaceGrid`, beside `IconDepthMetrics`) feeds all four renderers: the macOS 26 layer PNG (`IconGenerator.generateAppsLayerPNG`) under an `IconDocumentBuilder.appsFaceIconJSON` document with system fills and explicit flat keys, the fallback `.icns`, the macOS 15 four-variant bake, and `DockTileIconPreview`'s Apps mode (cache-backed minis). `HelperBundleManager.installTileIcons` resolves the tile's installed items (missing skipped, symlinks resolved) and branches on the face; zero resolvable items fall back to the glyph face everywhere.

**Tech Stack:** Swift 6, SwiftUI + AppKit (+ CoreImage for the legacy grayscale variants), Swift Testing, Icon Composer `.icon` → vendored `docktile-actool` (Rust), `Scripts/l10n/l10n.py`.

**Spec:** [docs/superpowers/specs/2026-10-18-apps-tile-face-design.md](../specs/2026-10-18-apps-tile-face-design.md)

## Global Constraints

- Deployment target macOS 15.0; the macOS 15 CI leg (`test-macos-15`) must stay green — the legacy bake must draw this face too, and no test may assume the macOS 26 pipeline (follow `IconPipeline.isDeclarative`).
- Grid: **1 item → one centred cell of 0.60 of the shape** ("Fills the Tile"); block **0.70** of the shape, gap **0.047**; **2 columns when count is 2–4, else 3** → cell 0.326 / 0.202 of the shape; row-major from the top-left; max **9** items; an app icon's draw box = cell ÷ (1 − 2 × `IconDepthMetrics.contentInsetRatio`) (≈ 0.805); a folder icon is fitted to the cell; empty cells stay glass. Shape = canvas inset by `contentInsetRatio` in every baked artifact, the full frame in `DockTileIconPreview`.
- Material: fill `"system-light"` (light + tinted) / `"system-dark"` (dark) in the `.icon`; the bake and the preview draw the gray pairs light **1.0 → 0.925**, dark **0.192 → 0.078**. `TilePalette` / `ToneMap` are not consulted for this face.
- Flat minis: the `.icon` writes layer `"glass": false`, group `"specular": false`, `"translucency": {"enabled": false, "value": 0}`, `"shadow": {"kind": "none", "opacity": 0}` **explicitly** — never by omission.
- One composite raster layer visible in every appearance; the document is named `AppIcon` (both compilers name renditions after the document stem).
- Missing items are skipped (never drawn stale); folders are included in tile order; zero resolvable items → the glyph face. The bake reads only local icons; nothing leaves the device; no new Dock restart or plist write.
- Schema: separate optional field, not a new `IconType` case; v10; `CodingKeys`; `decodeIfPresent`; **two defaults on purpose** — a config MISSING the key decodes to `.glyph` (existing tiles must not change on upgrade), while `ConfigurationDefaults.iconFace` for a NEW tile is `.apps` ("App Preview is the default for new tiles"); unknown raw value → `.glyph`. `tintColor`, `background`, `iconType`, `iconValue`, `iconScale`, `iconWeight` are retained while the face is Apps.
- Customise Tile follows the design handoff `docs/design_handoff_customise_tile/README.md` verbatim: two columns (canvas + fixed 260 pt inspector), the three-card Style picker (**App Preview · Symbol · Emoji**), the Apps card (**Shown** / **Arrangement**) and captions, with every new string's copy exactly as the README lists it (one exception, decided below: the glass caption). The window becomes **horizontally resizable: minimum 782 pt, maximum 1200 pt wide** (today it is fixed at 768 by four constants plus a `windowWillResize` clamp — Task 10 lists every site); height stays min 500 / unbounded.
- DECIDED (Karthik, 2026-10-19): the dark appearance keeps `system-dark` (Task 5 unchanged) and the App Preview caption ships as exactly "A glass folder that follows Light and Dark Mode."
- All user-facing strings via `AppStrings` (`NSLocalizedString(key, value:, comment:)` three-argument shape) + `Localizable.xcstrings` written only by `l10n.py` (`sync-keys` / `import`); `python3 -I` for every Python invocation.
- Analytics: `tile_added_to_dock` / `tile_updated` gain `face` (`glyph` / `apps`); the GA4 custom dimension must be registered BEFORE the release that ships it (forward-only).
- Icon-rendering invariants: `NSBitmapImageRep` with explicit pixel dims (never `lockFocus`); no baked outer tile shadow; iconset/`.icon` scratch in the temp dir with `defer` cleanup; the Dock entry is re-seated after regenerate (already in place).
- New **app-target** Swift files need `project.pbxproj` entries — this plan adds none (every new type goes into an existing file); new `DockTileTests/` files auto-join. Tests never write `UserDefaults.standard`; prefer `#require`; assert exact values.
- Work on branch `feat/apps-tile-face` in a worktree (superpowers:using-git-worktrees); run `./Scripts/build-compiler.sh` there if `Vendor/actool/target/release/docktile-actool` is absent. Commits are their own Bash call and never contain a bare `-n`. Delete the worktree's `DerivedData/DockTile-<hash>` with the worktree.
- Test command, referred to below as **TEST(<Suite>)**:
  `xcodebuild test -project DockTile.xcodeproj -scheme DockTile -configuration Debug -destination 'platform=macOS' -only-testing:DockTileTests/<Suite> CODE_SIGNING_ALLOWED=NO`
  and **TEST(all)** = the same with `-only-testing:DockTileTests`. Report per-suite executed counts and the `TEST SUCCEEDED`/`FAILED` line, never a grep count over the log.

## Review Focus

1. **Every item missing (or no items) on an Apps-face tile** — the Dock, the sidebar and the hero must show the glyph face, never a blank glass square. Pinned: `AppsFaceGridTests.allMissingSelectsNothing` (Task 3), `AppsFacePreviewTests.unresolvableItemsFallBackToGlyph` (Task 9), and the `installTileIcons` branch condition in Task 8.
2. **A symlinked app bundle** (`/Applications/Safari.app` is a symlink on macOS 27) — its mini must be the real icon, not the alias-arrow-badged one, in the face AND the popover. Pinned: `AppIconLoaderSymlinkTests.symlinkedAppIconHasNoAliasBadge` (Task 7).
3. **A folder item** — drawn fitted to its cell, not enlarged by the ÷0.805 app box (a Finder folder glyph has no squircle margin). Pinned: `AppsFaceGridTests.folderBoxIsTheCell` (Task 3) and `AppsFaceRenderTests.folderMiniFitsItsCell` (Task 4).
4. **Clear / Tinted legacy variants on macOS 15** — minis must be grayscale so that path's promise holds. Pinned: `AppsFaceRenderTests.clearAndTintedVariantsDesaturateMinis` (Task 6).
5. **A config saved by this build and opened by an older one, or a future face value opened by this one** — an unknown `iconFace` value must load as `.glyph` without failing the tile list (older builds ignore the unknown key by construction). Pinned: `IconFaceTests.unknownValueIsGlyph` (Task 2).
6. **Light app icons (Notes, Calendar) on near-white glass** — without a contact shadow they vanish; the shadow must exist at bake sizes and vanish below `minDetailSize`. Pinned: `AppsFaceGridTests.miniShadowMagnitudes` (Task 3) and `AppsFaceRenderTests.miniCastsAContactShadow` (Task 4).

---

### Task 1: Preserve the spike's system-fill document as a fixture (synthetic layer)

**Files:**
- Create: `docs/icon-spike-fixtures/appgrid-systemfill.icon/icon.json` (copy of the spike's document; only the layer's `image-name` changes)
- Create: `docs/icon-spike-fixtures/make-appgrid-layer.swift` (generates the synthetic layer)
- Create: `docs/icon-spike-fixtures/appgrid-systemfill.icon/Assets/grid.png` (generated — the document does not compile without a layer)
- Modify: `docs/icon-spike-fixtures/README.md` (append a section)
- Commit also: `docs/superpowers/specs/2026-10-18-apps-tile-face-design.md`, `docs/superpowers/plans/2026-10-18-apps-tile-face.md`

**Interfaces:**
- Produces: the fixture path `docs/icon-spike-fixtures/appgrid-systemfill.icon` that Task 5's end-to-end compile test and the README reference. The spike's own layer (`nine.png`, a composite of Apple's stock app icons) is **never committed** — third-party artwork in a public repo; the geometry it demonstrated is reproduced with flat coloured squares.

- [ ] **Step 1: Copy the round-three `icon.json` out of the session scratchpad (it vanishes with the session) and point its layer at `grid.png`**

```bash
SRC="/private/tmp/claude-501/-Users-karthik-Work-Products-Docktile-dock-tile/3866aa77-c3e5-4c5f-826e-cba77e5845f9/scratchpad/appgrid-spike/docs3/nine/AppIcon.icon"
mkdir -p docs/icon-spike-fixtures/appgrid-systemfill.icon/Assets
sed 's/"image-name": "nine.png"/"image-name": "grid.png"/' "$SRC/icon.json" > docs/icon-spike-fixtures/appgrid-systemfill.icon/icon.json
```

Expected: `icon.json` has `"fill": "system-light"` and three `fill-specializations` entries (`system-light`, dark → `system-dark`, tinted → `system-light`), one layer `grid` → `grid.png`, no `hidden-specializations`. Do not copy `nine.png`.

- [ ] **Step 2: Write `docs/icon-spike-fixtures/make-appgrid-layer.swift` and generate the layer**

The spike geometry on a 1024 canvas: the 824 px shape is centred (offset 100); block 577, gap 39, cell 166, inset 124 from the shape's edge, so the 3×3 cells start at canvas 224 / 429 / 634 on both axes. Explicit-pixel `NSBitmapImageRep`, never `lockFocus` (icon-rendering invariant).

```swift
#!/usr/bin/env swift
// Synthetic Apps-face layer: nine flat coloured rounded squares on the spike's 3×3 grid.
// Usage: swift make-appgrid-layer.swift <output.png>
import AppKit

let canvas = 1024
let cellOrigins: [CGFloat] = [224, 429, 634]        // 100 + 124 + k × (166 + 39)
let cell: CGFloat = 166
let colours: [NSColor] = [.systemRed, .systemOrange, .systemYellow, .systemGreen, .systemTeal,
                          .systemBlue, .systemIndigo, .systemPurple, .systemGray]

guard CommandLine.arguments.count == 2 else { fputs("usage: make-appgrid-layer.swift <output.png>\n", stderr); exit(2) }
guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: canvas, pixelsHigh: canvas, bitsPerSample: 8,
                                 samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                 colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0),
      let ctx = NSGraphicsContext(bitmapImageRep: rep) else { exit(1) }
rep.size = CGSize(width: canvas, height: canvas)
let cg = ctx.cgContext
cg.clear(CGRect(x: 0, y: 0, width: canvas, height: canvas))
for (i, colour) in colours.enumerated() {
    // Bitmap contexts are y-up: row 0 of the grid is the TOP, so flip the row index.
    let x = cellOrigins[i % 3]
    let y = CGFloat(canvas) - cellOrigins[i / 3] - cell
    let path = CGPath(roundedRect: CGRect(x: x, y: y, width: cell, height: cell),
                      cornerWidth: cell * 0.225, cornerHeight: cell * 0.225, transform: nil)
    cg.addPath(path)
    cg.setFillColor(colour.usingColorSpace(.sRGB)!.cgColor)
    cg.fillPath()
}
guard let png = rep.representation(using: .png, properties: [:]) else { exit(1) }
try! png.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
```

```bash
swift docs/icon-spike-fixtures/make-appgrid-layer.swift docs/icon-spike-fixtures/appgrid-systemfill.icon/Assets/grid.png
sips -g pixelWidth -g pixelHeight docs/icon-spike-fixtures/appgrid-systemfill.icon/Assets/grid.png
```

Expected: `pixelWidth: 1024`, `pixelHeight: 1024`; a few KB; opened in Preview it shows nine coloured squares in the upper-left-to-lower-right order red → gray with a transparent margin all round.

- [ ] **Step 3: Compile it with the vendored compiler and check the three stacks**

```bash
OUT=build/scratch-appgrid; rm -rf "$OUT"; mkdir -p "$OUT"     # build/ is gitignored
Vendor/actool/target/release/docktile-actool docs/icon-spike-fixtures/appgrid-systemfill.icon \
  --compile "$OUT" --app-icon AppIcon --output-partial-info-plist "$OUT/partial.plist" \
  --platform macosx --target-device mac --minimum-deployment-target 15.0
assetutil --info "$OUT/Assets.car" | grep -E '"AssetType" : "IconImageStack"|"Appearance"'
```

Expected: exactly three `IconImageStack` lines whose `Appearance` values are `NSAppearanceNameAqua`, `NSAppearanceNameDarkAqua`, `ISAppearanceTintable`. Pin nothing else; Karthik may drop the car into a stub bundle and view it in Finder under each style (the Tinted/Clear look of nine opaque minis is the spec's one open observation — the real-icon render for that lives only in the spike session's Finder check).

- [ ] **Step 4: Append the README note**

Append to `docs/icon-spike-fixtures/README.md` a section `## appgrid-systemfill.icon` stating: the `icon.json` is the 2026-10-18 Apps-tile-face spike's round-three document (nine apps, one composite layer, system fills); its layer here is **synthetic** — `Assets/grid.png`, nine flat coloured rounded squares on the spike's 3×3 geometry (block 577 / gap 39 / cell 166 / inset 124 on the 824 px shape), generated by `make-appgrid-layer.swift` — because the spike's real layer was a composite of Apple's stock app icons and is not committed; `fill: "system-light"` / `"system-dark"` are Apple's named fills — the vendored compiler resolves them to gray 1.0 → 0.925 / 0.192 → 0.078 (`Vendor/actool/src/icon_bundle.rs`, `keyword_bg_pair`), pixel-identical to the `Apps` launcher icon; the product's document ADDS the explicit flat keys (`glass: false`, `specular: false`, `translucency` off, `shadow: none`) that this fixture omits, because Apple's `actool` fills omitted keys with glass defaults; compile command as in Step 3; link to the spec.

- [ ] **Step 5: Commit**

```bash
git add docs/icon-spike-fixtures/appgrid-systemfill.icon docs/icon-spike-fixtures/make-appgrid-layer.swift docs/icon-spike-fixtures/README.md docs/superpowers/specs/2026-10-18-apps-tile-face-design.md docs/superpowers/plans/2026-10-18-apps-tile-face.md
```
```bash
git commit -m "docs(icons): preserve the Apps-face system-fill spike document with a synthetic layer; spec + plan"
```

---

### Task 2: `IconFace` model field (schema v10), signature and duplicate

**Files:**
- Modify: `DockTile/Models/ConfigurationModels.swift:16-195` (struct fields, `iconSignature` ~49, `duplicate` ~67, init ~87, decoder ~128, `CodingKeys` ~173), plus a new enum after `TileBackground` (~270)
- Modify: `DockTile/Models/ConfigurationSchema.swift:35-37`
- Modify: `DockTile/Views/DockTileDetailView.swift:78-91` (`contentSignature`)
- Test: `DockTileTests/Unit/Models/IconFaceTests.swift` (new), `DockTileTests/Unit/Components/TileFaceTests.swift`, `DockTileTests/Unit/Models/DockTileDuplicateTests.swift`, `DockTileTests/Unit/Managers/DockActionResolutionTests.swift`

**Interfaces:**
- Produces: `enum IconFace: String, Codable, CaseIterable, Hashable { case glyph, apps }` with tolerant `init(from:)` → `.glyph`; `DockTileConfiguration.iconFace: IconFace` (v10, memberwise init parameter `iconFace: IconFace = ConfigurationDefaults.iconFace` placed after `background`); `ConfigurationDefaults.iconFace: IconFace = .apps` (NEW tiles — `createConfiguration()` and `createConfiguration(from:)` pass no face, so they inherit it); the decoder's missing-key fallback is the LITERAL `.glyph`, never `ConfigurationDefaults.iconFace` (existing tiles must not change on upgrade); `DockTileConfiguration.appsFaceIdentities: [String]` (first nine items' identities: `folderPath ?? name` for a folder, else `bundleIdentifier`); `iconSignature` unchanged for `.glyph`, and `<existing>|apps|<identities joined by ",">` for `.apps`.

- [ ] **Step 1: Write the failing tests**

`DockTileTests/Unit/Models/IconFaceTests.swift` (mirror `TileBackgroundTests`):

```swift
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
```

Append to `TileFaceTests` (inside the `iconSignature` MARK):

```swift
    @Test("The glyph face leaves existing signatures byte-identical; Apps appends the face and the first nine identities")
    func appsFaceJoinsTheSignature() {
        let items = (1...10).map { AppItem(bundleIdentifier: "com.example.app\($0)", name: "App \($0)") }
        var glyph = DockTileConfiguration(name: "Work", tintColor: .custom("#FF5733"), iconValue: "bolt", iconFace: .glyph, appItems: items)
        let glyphSignature = glyph.iconSignature
        #expect(glyphSignature == "#FF5733|sfSymbol|bolt|\(glyph.iconScale)|medium|colour")

        glyph.iconFace = .apps
        let nine = (1...9).map { "com.example.app\($0)" }.joined(separator: ",")
        #expect(glyph.iconSignature == glyphSignature + "|apps|" + nine)
        #expect(glyph.appsFaceIdentities.count == 9)
    }

    @Test("On the Apps face the list order, a removal and a folder path all move the signature")
    func appsFaceListChangesMoveTheSignature() {
        let a = AppItem(bundleIdentifier: "com.example.a", name: "A")
        let b = AppItem(bundleIdentifier: "com.example.b", name: "B")
        let folder = AppItem(bundleIdentifier: "folder.1", name: "Docs", isFolder: true, folderPath: "/Users/x/Docs")
        let base = DockTileConfiguration(name: "Work", iconFace: .apps, appItems: [a, b, folder])
        var reordered = base; reordered.appItems = [b, a, folder]
        var removed = base; removed.appItems = [a, folder]
        var moved = base; moved.appItems = [a, b, AppItem(bundleIdentifier: "folder.1", name: "Docs", isFolder: true, folderPath: "/Users/x/Docs2")]
        #expect(Set([base, reordered, removed, moved].map(\.iconSignature)).count == 4)
        #expect(base.iconSignature.hasSuffix("|apps|com.example.a,com.example.b,/Users/x/Docs"))
    }
```

Because a new tile now defaults to `.apps`, every existing test that builds a GLYPH tile and depends on its signature must say so: in `TileFaceTests` add `iconFace: .glyph` to the `base` of `nonIconFieldsIgnored` (its "`appItems` do not move the signature" assertion is the regression pin for the glyph branch — keep it) and to both tiles in `sameLookSameSignature` (whose exact-string pin stays byte-identical).

In `DockTileDuplicateTests.original` add `iconFace: .glyph,` after `background: .mono,` — `.glyph` because the coverage test `sampleCoversEveryContentField` requires every sample field to differ from a NEW tile's default, which is now `.apps`; `duplicateKeepsContent` fails until `duplicate(named:)` copies it.

Append to `DockActionResolutionTests.userEditsChangeSignature`:

```swift
        var refaced = base                       // makeConfig() is an App Preview tile (the new default)
        refaced.iconFace = .glyph
        #expect(DockTileDetailView.contentSignature(of: refaced) != baseSignature)
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: TEST(IconFaceTests), TEST(TileFaceTests), TEST(DockTileDuplicateTests), TEST(DockActionResolutionTests)
Expected: compile errors `cannot find 'IconFace'` / `extra argument 'iconFace'`.

- [ ] **Step 3: Implement the model**

In `ConfigurationModels.swift`: add `enum IconFace` (doc comment: why a separate field, not an `IconType` case — `IconType` decodes strictly; tolerant decode like `TileBackground`); add `var iconFace: IconFace  // v10: glyph (symbol/emoji) or the Apps grid`; memberwise init parameter + assignment; decoder `iconFace = try container.decodeIfPresent(IconFace.self, forKey: .iconFace) ?? .glyph` under a `// v10 fields` comment; `CodingKeys` `// v10 fields` `case iconFace`; `duplicate(named:)` passes `iconFace: iconFace`; add

```swift
    /// Identities of the first `AppsFaceGrid.maxItems` items as the Apps face would draw them.
    var appsFaceIdentities: [String]
```

(hard-code `9` here until Task 3 lands `AppsFaceGrid.maxItems`, then switch to the seam in Task 3), and extend `iconSignature`: compute the existing string into `base`, then `return iconFace == .glyph ? base : base + "|apps|" + appsFaceIdentities.joined(separator: ",")`.

In `ConfigurationSchema.swift`: `// v10: Tile face — App Preview for NEW tiles; the decoder keeps an existing tile's glyph` / `static let iconFace: IconFace = .apps`. In the decoder write `?? .glyph` with a comment naming the two defaults, not `?? ConfigurationDefaults.iconFace`.

In `DockTileDetailView.contentSignature`: `hasher.combine(config.iconFace)` after `background`.

- [ ] **Step 4: Run the tests to verify they pass**

Run: TEST(IconFaceTests), TEST(TileFaceTests), TEST(DockTileDuplicateTests), TEST(DockActionResolutionTests), TEST(ConfigurationModelsTests), then TEST(all)
Expected: all `TEST SUCCEEDED` (IconFaceTests: 6 passed). If TEST(all) turns up another test that built a glyph tile through the memberwise init and now sees the `|apps|` suffix, add `iconFace: .glyph` to that construction — never change the default back.

- [ ] **Step 5: Commit**

```bash
git add DockTile/Models/ConfigurationModels.swift DockTile/Models/ConfigurationSchema.swift DockTile/Views/DockTileDetailView.swift DockTileTests/Unit/Models/IconFaceTests.swift DockTileTests/Unit/Components/TileFaceTests.swift DockTileTests/Unit/Models/DockTileDuplicateTests.swift DockTileTests/Unit/Managers/DockActionResolutionTests.swift
```
```bash
git commit -m "feat(model): iconFace field (v10) joins the icon signature and duplicate"
```

---

### Task 3: `AppsFaceGrid` — geometry, material and selection seam

**Files:**
- Modify: `DockTile/Utilities/IconDepthMetrics.swift` (append a new `enum AppsFaceGrid` after `IconDepthMetrics`)
- Modify: `DockTile/Models/ConfigurationModels.swift` (`appsFaceIdentities` reads `AppsFaceGrid.maxItems`)
- Test: `DockTileTests/Unit/Utilities/AppsFaceGridTests.swift` (new)

**Interfaces:**
- Produces (all `static`, no AppKit/SwiftUI import — `CoreGraphics` + `Foundation` only):
  - `AppsFaceGrid.blockRatio: CGFloat = 0.70`, `gapRatio: CGFloat = 0.047`, `maxItems = 9`
  - `appIconContentRatio: CGFloat` = `1 - 2 * IconDepthMetrics.contentInsetRatio`
  - `singleRatio: CGFloat = 0.60` — one item fills the tile with one centred icon
  - `columns(count: Int) -> Int` (1 for 0…1, 2 for 2…4, 3 otherwise)
  - `cellRatio(columns: Int) -> CGFloat` = `singleRatio` for 1 column, else `(blockRatio - CGFloat(columns - 1) * gapRatio) / CGFloat(columns)`
  - `cells(count: Int) -> [CGRect]` — unit space of the SHAPE, origin top-left, y-down; `min(count, maxItems)` rects; one centred `singleRatio` rect for a single item, else row-major on the block (origin `(1 - blockRatio) / 2`)
  - `drawBox(for cell: CGRect, isFolder: Bool) -> CGRect` — folder: the cell; app: the cell scaled about its centre by `1 / appIconContentRatio`
  - `rect(_ unit: CGRect, in shape: CGRect, yUp: Bool) -> CGRect` — maps a unit rect onto `shape`; `yUp: true` flips for AppKit's non-flipped bitmap contexts
  - `miniShadow(nominalSize: CGFloat) -> IconDepthMetrics.GlyphShadow?` — `nil` below `IconDepthMetrics.minDetailSize`; else `blackAlpha 0.35`, `offset nominalSize * 6 / 1024`, `blur nominalSize * 12 / 1024`
  - `lightGrays: (top: CGFloat, bottom: CGFloat) = (1.0, 0.925)`, `darkGrays = (0.192, 0.078)`, `fillGrays(style: IconStyle) -> (top: CGFloat, bottom: CGFloat)` (`.dark` → dark pair, every other style → light pair), `desaturatesMinis(style: IconStyle) -> Bool` (`.clear`, `.tinted` → true)
  - `select(items: [AppItem], isInstalled: (AppItem) -> Bool) -> (selected: [AppItem], skipped: Int)` — tile order, installed only, at most `maxItems`; `skipped` = missing items in the whole list

- [ ] **Step 1: Write the failing tests**

```swift
//  AppsFaceGridTests.swift — the one geometry/material seam all four Apps-face renderers read.
import CoreGraphics
import Testing
@testable import Dock_Tile

struct AppsFaceGridTests {
    private func close(_ a: CGFloat, _ b: CGFloat, _ tolerance: CGFloat = 1e-9,
                       sourceLocation: SourceLocation = #_sourceLocation) {
        #expect(abs(a - b) < tolerance, "expected \(b), got \(a)", sourceLocation: sourceLocation)
    }

    @Test("Columns: 1 for a single item, 2 for two to four, 3 from five — both flips pinned")
    func columnFlip() {
        #expect(AppsFaceGrid.columns(count: 1) == 1)
        #expect(AppsFaceGrid.columns(count: 2) == 2)                       // 1 → 2 flip
        for n in 2...4 { #expect(AppsFaceGrid.columns(count: n) == 2, "\(n)") }
        #expect(AppsFaceGrid.columns(count: 5) == 3)                       // 4 → 5 flip
        for n in 5...12 { #expect(AppsFaceGrid.columns(count: n) == 3, "\(n)") }
    }

    @Test("Cell sizes: 0.60 single, then the iOS folder / App Library minis")
    func cellSizes() {
        close(AppsFaceGrid.cellRatio(columns: 1), 0.60)
        close(AppsFaceGrid.cellRatio(columns: 2), 0.3265, 1e-4)   // (0.70 − 0.047) / 2
        close(AppsFaceGrid.cellRatio(columns: 3), 0.2020, 1e-4)   // (0.70 − 2 × 0.047) / 3
        close(AppsFaceGrid.appIconContentRatio, 206.0 / 256.0)
    }

    @Test("Cell counts and layout for 1, 2, 3, 4, 5, 9 and 10 items")
    func cellLayouts() {
        let one = AppsFaceGrid.cells(count: 1)
        #expect(one.count == 1)
        close(one[0].minX, 0.20); close(one[0].minY, 0.20); close(one[0].width, 0.60); close(one[0].midX, 0.5)

        let two = AppsFaceGrid.cells(count: 2)
        #expect(two.count == 2)
        close(two[0].minX, 0.15); close(two[0].width, AppsFaceGrid.cellRatio(columns: 2))
        close(two[1].minY, two[0].minY)                  // the top row of a 2×2

        let three = AppsFaceGrid.cells(count: 3)
        #expect(three.count == 3)
        close(three[1].minY, three[0].minY)              // two on top…
        #expect(three[1].minX > three[0].minX)
        close(three[2].minX, three[0].minX)              // …one bottom-left
        #expect(three[2].minY > three[0].minY)

        let four = AppsFaceGrid.cells(count: 4)
        #expect(four.count == 4)
        close(four[3].maxX, 0.85); close(four[3].maxY, 0.85)   // the block spans exactly 0.70

        let five = AppsFaceGrid.cells(count: 5)
        #expect(five.count == 5)
        close(five[0].width, AppsFaceGrid.cellRatio(columns: 3))
        close(five[2].maxX, 0.85)                         // third column exists
        close(five[3].minX, 0.15); #expect(five[3].minY > five[2].minY)   // row-major wrap

        let nine = AppsFaceGrid.cells(count: 9)
        #expect(nine.count == 9)
        close(nine[8].maxX, 0.85); close(nine[8].maxY, 0.85)

        #expect(AppsFaceGrid.cells(count: 10).count == 9)
        #expect(AppsFaceGrid.cells(count: 0).isEmpty)
    }

    @Test("Cells never overlap on either grid")
    func cellsDisjoint() {
        for count in [4, 9] {
            let cells = AppsFaceGrid.cells(count: count)
            for i in cells.indices { for j in cells.indices where i < j {
                #expect(!cells[i].insetBy(dx: 1e-6, dy: 1e-6).intersects(cells[j]), "\(count): \(i) overlaps \(j)")
            } }
        }
    }

    @Test("An app's draw box is its cell ÷ the icon-grid content ratio; a folder's box is the cell")
    func drawBoxes() {
        let cell = AppsFaceGrid.cells(count: 9)[4]
        let app = AppsFaceGrid.drawBox(for: cell, isFolder: false)
        close(app.width, cell.width / AppsFaceGrid.appIconContentRatio)
        close(app.midX, cell.midX); close(app.midY, cell.midY)
        #expect(AppsFaceGrid.drawBox(for: cell, isFolder: true) == cell)
    }

    @Test("folderBoxIsTheCell: a 2×2 app box is 334 px on the 824 px shape, the folder box 269 px; single: 614 vs 494")
    func folderBoxIsTheCell() {
        let shape = CGRect(x: 100, y: 100, width: 824, height: 824)
        let cell = AppsFaceGrid.cells(count: 2)[0]
        let appBox = AppsFaceGrid.rect(AppsFaceGrid.drawBox(for: cell, isFolder: false), in: shape, yUp: false)
        let folderBox = AppsFaceGrid.rect(AppsFaceGrid.drawBox(for: cell, isFolder: true), in: shape, yUp: false)
        close(appBox.width, 334, 1.0)
        close(folderBox.width, 269, 1.0)
        // Independent pins, not derived from the seam: the first cell of a 2×2, and the single
        // centred cell, on a 1024 canvas.
        close(folderBox.minX, 223.6, 0.5); close(folderBox.minY, 223.6, 0.5)
        let single = AppsFaceGrid.cells(count: 1)[0]
        let singleFolder = AppsFaceGrid.rect(AppsFaceGrid.drawBox(for: single, isFolder: true), in: shape, yUp: false)
        let singleApp = AppsFaceGrid.rect(AppsFaceGrid.drawBox(for: single, isFolder: false), in: shape, yUp: false)
        close(singleFolder.minX, 264.8, 0.5); close(singleFolder.width, 494.4, 0.5)
        close(singleApp.width, 614.4, 1.0); close(singleApp.midX, 512, 0.5)
    }

    @Test("rect(in:yUp:) flips the vertical axis for AppKit bitmaps")
    func rectMapping() {
        let shape = CGRect(x: 0, y: 0, width: 100, height: 100)
        let unit = CGRect(x: 0.1, y: 0.2, width: 0.3, height: 0.3)
        let down = AppsFaceGrid.rect(unit, in: shape, yUp: false)
        let up = AppsFaceGrid.rect(unit, in: shape, yUp: true)
        close(down.minY, 20); close(up.minY, 50)          // 100 − (20 + 30)
        close(down.minX, up.minX); close(down.width, 30)
    }

    @Test("miniShadowMagnitudes: the contact shadow is 0.35 / 6 px / 12 px at 1024 and absent below the detail gate")
    func miniShadowMagnitudes() throws {
        let s = try #require(AppsFaceGrid.miniShadow(nominalSize: 1024))
        #expect(s == IconDepthMetrics.GlyphShadow(blackAlpha: 0.35, offset: 6, blur: 12))
        let small = try #require(AppsFaceGrid.miniShadow(nominalSize: 256))
        close(small.offset, 1.5); close(small.blur, 3)
        #expect(AppsFaceGrid.miniShadow(nominalSize: 16) == nil)
        #expect(AppsFaceGrid.miniShadow(nominalSize: IconDepthMetrics.minDetailSize) != nil)
    }

    @Test("Material: the system gray pairs by style, grayscale minis for Clear/Tinted")
    func material() {
        for style in [IconStyle.defaultStyle, .clear, .tinted] {
            let g = AppsFaceGrid.fillGrays(style: style)
            #expect(g.top == 1.0 && g.bottom == 0.925, "\(style): \(g)")
        }
        let dark = AppsFaceGrid.fillGrays(style: .dark)
        #expect(dark.top == 0.192 && dark.bottom == 0.078)
        #expect(AppsFaceGrid.lightGrays.top == 1.0 && AppsFaceGrid.darkGrays.bottom == 0.078)
        #expect(!AppsFaceGrid.desaturatesMinis(style: .defaultStyle) && !AppsFaceGrid.desaturatesMinis(style: .dark))
        #expect(AppsFaceGrid.desaturatesMinis(style: .clear) && AppsFaceGrid.desaturatesMinis(style: .tinted))
    }

    @Test("Selection skips missing items so the next installed one takes the cell, caps at nine, counts the skipped")
    func selection() {
        let items = (1...12).map { AppItem(bundleIdentifier: "com.example.\($0)", name: "\($0)") }
        let missing: Set<String> = ["com.example.2", "com.example.11"]
        let out = AppsFaceGrid.select(items: items) { !missing.contains($0.bundleIdentifier) }
        #expect(out.selected.map(\.bundleIdentifier) == ["com.example.1", "com.example.3", "com.example.4", "com.example.5",
                                                        "com.example.6", "com.example.7", "com.example.8", "com.example.9", "com.example.10"])
        #expect(out.skipped == 2)
    }

    @Test("allMissingSelectsNothing: zero installed → empty selection (the caller falls back to the glyph face)")
    func allMissingSelectsNothing() {
        let items = [AppItem(bundleIdentifier: "a", name: "A"), AppItem(bundleIdentifier: "b", name: "B")]
        let out = AppsFaceGrid.select(items: items) { _ in false }
        #expect(out.selected.isEmpty && out.skipped == 2)
        #expect(AppsFaceGrid.select(items: [], isInstalled: { _ in true }).selected.isEmpty)
    }
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: TEST(AppsFaceGridTests)
Expected: compile error `cannot find 'AppsFaceGrid' in scope`.

- [ ] **Step 3: Implement `enum AppsFaceGrid` in `IconDepthMetrics.swift`**

Header comment: the iOS 26 folder geometry (block 0.70, gap 0.047, measured from the iOS 26 screenshot and the App Library reference — spec "Research findings"; a single item fills the tile with one 0.60 icon, the handoff's "Fills the Tile"), why it is one seam (four renderers), and that `TilePalette` is deliberately not involved. `cells(count:)`: `count == 1` → `[CGRect(x: 0.20, y: 0.20, width: 0.60, height: 0.60)]`; else `let cols = columns(count:)`, `let cell = cellRatio(columns: cols)`, `origin = (1 - blockRatio) / 2`, index `i` → `(x: origin + CGFloat(i % cols) * (cell + gapRatio), y: origin + CGFloat(i / cols) * (cell + gapRatio))`. Replace the hard-coded `9` in `DockTileConfiguration.appsFaceIdentities` with `AppsFaceGrid.maxItems`.

- [ ] **Step 4: Run the tests to verify they pass**

Run: TEST(AppsFaceGridTests), TEST(TileFaceTests)
Expected: `TEST SUCCEEDED` (AppsFaceGridTests: 11 passed).

- [ ] **Step 5: Commit**

```bash
git add DockTile/Utilities/IconDepthMetrics.swift DockTile/Models/ConfigurationModels.swift DockTileTests/Unit/Utilities/AppsFaceGridTests.swift
```
```bash
git commit -m "feat(icons): AppsFaceGrid geometry, material and selection seam"
```

---

### Task 4: The composite layer PNG (macOS 26 renderer)

**Files:**
- Modify: `DockTile/Utilities/IconGenerator.swift` (add `AppsFaceMini`, `generateAppsLayerPNG`, private `drawAppsGrid`; add `import CoreImage` for Task 6's desaturation now so the file's imports change once)
- Test: `DockTileTests/Unit/Utilities/AppsFaceRenderTests.swift` (new; Task 6 appends to it)

**Interfaces:**
- Consumes: `AppsFaceGrid.cells/drawBox/rect/miniShadow` (Task 3).
- Produces:
  - `struct IconGenerator.AppsFaceMini { let image: NSImage; let isFolder: Bool }`
  - `static func generateAppsLayerPNG(minis: [AppsFaceMini], canvas: Int = 1024) throws -> Data` — transparent canvas, shape = canvas inset by `IconDepthMetrics.contentInsetRatio`, each mini drawn into `rect(drawBox(cell), in: shape, yUp: true)` with `NSImage.draw(in:from:operation:fraction:respectFlipped:hints: [.interpolation: NSImageInterpolation.high])` under `AppsFaceGrid.miniShadow(nominalSize: canvas)` applied via `CGContext.setShadow`; no squircle, no stroke, no sheen; throws `IconGeneratorError.imageConversionFailed` / `.pngExportFailed` like `generateGlyphLayerPNG`
  - `private static func drawAppsGrid(minis: [AppsFaceMini], shape: CGRect, nominalSize: CGFloat, desaturate: Bool, in context: CGContext)` — shared by this task and Task 6 (`desaturate` is wired in Task 6; pass `false` here)

- [ ] **Step 1: Write the failing tests**

```swift
//  AppsFaceRenderTests.swift — pixel guards for the Apps face through the REAL renderers
//  (generateAppsLayerPNG → drawAppsGrid → AppsFaceGrid), in the style of GlyphLayerRenderTests.
import AppKit
import SwiftUI
import Testing
@testable import Dock_Tile

@MainActor
@Suite("Apps face rendering")
struct AppsFaceRenderTests {
    static let canvas = 1024
    static let shape = CGRect(x: 100, y: 100, width: 824, height: 824)   // 1024 inset by 25/256

    /// A stand-in app icon: an opaque squircle on Apple's icon grid (transparent margin) — or
    /// full-bleed, which is what a Finder folder glyph's bounds look like to the renderer.
    static func mini(_ colour: NSColor, fullBleed: Bool = false, side: Int = 256) -> NSImage {
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: side, pixelsHigh: side, bitsPerSample: 8,
                                   samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                   colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        rep.size = CGSize(width: side, height: side)
        let ctx = NSGraphicsContext(bitmapImageRep: rep)!
        let full = CGRect(x: 0, y: 0, width: side, height: side)
        let inset = fullBleed ? 0 : CGFloat(side) * IconDepthMetrics.contentInsetRatio
        let r = full.insetBy(dx: inset, dy: inset)
        ctx.cgContext.clear(full)
        ctx.cgContext.addPath(RoundedRectangle(cornerRadius: r.width * 0.225, style: .continuous).path(in: r).cgPath)
        ctx.cgContext.setFillColor(colour.cgColor)
        ctx.cgContext.fillPath()
        let image = NSImage(size: rep.size); image.addRepresentation(rep); return image
    }

    static func bitmap(_ png: Data) throws -> NSBitmapImageRep { try #require(NSBitmapImageRep(data: png)) }

    /// Centre of cell `i` for `count` items, in y-down pixel coordinates of the 1024 canvas.
    static func centre(_ i: Int, count: Int) -> (x: Int, y: Int) {
        let r = AppsFaceGrid.rect(AppsFaceGrid.cells(count: count)[i], in: shape, yUp: false)
        return (Int(r.midX), Int(r.midY))
    }

    static func alpha(_ rep: NSBitmapImageRep, _ x: Int, _ y: Int) -> CGFloat {
        rep.colorAt(x: x, y: y)?.alphaComponent ?? 0
    }

    /// Width of the opaque run along row `y` starting from the first opaque pixel at or after `fromX`.
    static func opaqueRun(_ rep: NSBitmapImageRep, y: Int, fromX: Int) -> Int {
        var x = fromX
        while x < rep.pixelsWide, alpha(rep, x, y) < 0.5 { x += 1 }
        let start = x
        while x < rep.pixelsWide, alpha(rep, x, y) >= 0.5 { x += 1 }
        return x - start
    }

    @Test("oneAppIsCentredAtSixtyPercent: one app is one centred icon at 0.60 of the shape; the canvas is 1024² with transparent margin")
    func oneAppIsCentredAtSixtyPercent() throws {
        let rep = try Self.bitmap(try IconGenerator.generateAppsLayerPNG(
            minis: [.init(image: Self.mini(.systemBlue), isFolder: false)]))
        #expect(rep.pixelsWide == Self.canvas && rep.pixelsHigh == Self.canvas)
        for (x, y) in [(2, 2), (1021, 2), (2, 1021), (1021, 1021), (512, 104), (104, 512), (358, 230)] {
            #expect(Self.alpha(rep, x, y) == 0, "(\(x),\(y)) painted")   // (358,230) = where a 2×2 cell 0 would start
        }
        #expect(Self.alpha(rep, 512, 512) == 1)
        let c0 = Self.centre(0, count: 1)
        #expect(c0.x == 512 && c0.y == 512)                     // independent pin: centred
        let run = Self.opaqueRun(rep, y: 512, fromX: 0)
        #expect(abs(run - 494) <= 4, "visible squircle is \(run) px, 0.60 of 824 is 494")
    }

    @Test("Two apps paint the top row of a 2×2 and leave the bottom row glass")
    func twoAppsPaintTheTopRow() throws {
        let rep = try Self.bitmap(try IconGenerator.generateAppsLayerPNG(
            minis: (0..<2).map { _ in .init(image: Self.mini(.systemBlue), isFolder: false) }))
        for i in 0...1 { let c = Self.centre(i, count: 2); #expect(Self.alpha(rep, c.x, c.y) == 1, "cell \(i) empty") }
        for i in 2...3 { let c = Self.centre(i, count: 4); #expect(Self.alpha(rep, c.x, c.y) == 0, "cell \(i) is not empty glass") }
        let c0 = Self.centre(0, count: 2)
        #expect(c0.x == 358 && c0.y == 358)                     // independent pin of the 2×2 origin
    }

    @Test("The visible squircle lands on the cell: an app's margin is absorbed by the ÷0.805 box")
    func appSquircleFillsItsCell() throws {
        let rep = try Self.bitmap(try IconGenerator.generateAppsLayerPNG(
            minis: (0..<2).map { _ in .init(image: Self.mini(.systemRed), isFolder: false) }))
        let c0 = Self.centre(0, count: 2)
        let expected = Int(AppsFaceGrid.cellRatio(columns: 2) * Self.shape.width)   // 269
        let run = Self.opaqueRun(rep, y: c0.y, fromX: 0)
        #expect(abs(run - expected) <= 4, "visible squircle is \(run) px, cell is \(expected)")
    }

    @Test("folderMiniFitsItsCell: a full-bleed folder glyph is fitted to the cell, not enlarged")
    func folderMiniFitsItsCell() throws {
        let rep = try Self.bitmap(try IconGenerator.generateAppsLayerPNG(
            minis: [.init(image: Self.mini(.systemOrange, fullBleed: true), isFolder: true)]))
        let run = Self.opaqueRun(rep, y: 512, fromX: 0)
        #expect(abs(run - 494) <= 4, "folder drew \(run) px; fitted to the 494 px cell, not the 614 px app box")
    }

    @Test("Nine apps fill a 3×3; a tenth is dropped; adjacent minis do not touch")
    func nineAppsFillTheGrid() throws {
        let minis = (0..<10).map { _ in IconGenerator.AppsFaceMini(image: Self.mini(.systemGreen), isFolder: false) }
        let rep = try Self.bitmap(try IconGenerator.generateAppsLayerPNG(minis: minis))
        for i in 0..<9 {
            let c = Self.centre(i, count: 9)
            #expect(Self.alpha(rep, c.x, c.y) == 1, "cell \(i) empty")
        }
        // The gap between cell 0 and cell 1 (midpoint of the gap, on the cells' centre row) is glass:
        // a mini body is alpha 1; only the two 0.35-alpha shadows can feather into the 38 px gap.
        let a = AppsFaceGrid.rect(AppsFaceGrid.cells(count: 9)[0], in: Self.shape, yUp: false)
        let b = AppsFaceGrid.rect(AppsFaceGrid.cells(count: 9)[1], in: Self.shape, yUp: false)
        #expect(Self.alpha(rep, Int((a.maxX + b.minX) / 2), Int(a.midY)) < 0.3)
    }

    @Test("Five apps on a 3×3 leave the bottom row's last two cells and the whole third row empty")
    func fiveAppsAreAnL() throws {
        let minis = (0..<5).map { _ in IconGenerator.AppsFaceMini(image: Self.mini(.systemIndigo), isFolder: false) }
        let rep = try Self.bitmap(try IconGenerator.generateAppsLayerPNG(minis: minis))
        for i in 0..<5 { let c = Self.centre(i, count: 9); #expect(Self.alpha(rep, c.x, c.y) == 1) }
        for i in 5..<9 { let c = Self.centre(i, count: 9); #expect(Self.alpha(rep, c.x, c.y) == 0) }
    }

    @Test("miniCastsAContactShadow: soft shadow below a mini, none above it")
    func miniCastsAContactShadow() throws {
        let rep = try Self.bitmap(try IconGenerator.generateAppsLayerPNG(
            minis: [.init(image: Self.mini(.white, fullBleed: true), isFolder: true)]))   // full-bleed: the body reaches the cell edge
        let cell = AppsFaceGrid.rect(AppsFaceGrid.cells(count: 1)[0], in: Self.shape, yUp: false)
        let below = Self.alpha(rep, Int(cell.midX), Int(cell.maxY) + 5)
        let above = Self.alpha(rep, Int(cell.midX), Int(cell.minY) - 5)
        #expect(below > 0.05 && below < 0.4, "shadow below: \(below)")
        // The shadow is OFFSET downward (6 px at 1024), so the row 5 px above the mini carries far
        // less of it than the row 5 px below — a relative check that a blur-radius detail can't trip.
        #expect(above < below / 2, "shadow above \(above) vs below \(below)")
        let shadowColour = try #require(rep.colorAt(x: Int(cell.midX), y: Int(cell.maxY) + 5)?.usingColorSpace(.sRGB))
        #expect(shadowColour.brightnessComponent < 0.2)       // black, not a smeared mini
    }

    @Test("No minis → an entirely transparent layer (the caller must have fallen back to the glyph face)")
    func emptyLayerIsTransparent() throws {
        let rep = try Self.bitmap(try IconGenerator.generateAppsLayerPNG(minis: []))
        #expect(Self.alpha(rep, 512, 512) == 0 && Self.alpha(rep, 358, 358) == 0)
    }
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: TEST(AppsFaceRenderTests)
Expected: compile error `type 'IconGenerator' has no member 'generateAppsLayerPNG'`.

- [ ] **Step 3: Implement `AppsFaceMini`, `drawAppsGrid` and `generateAppsLayerPNG` in `IconGenerator.swift`**

Place after `generateGlyphLayerPNG` under `// MARK: - Apps face`. `drawAppsGrid`: `for mini in minis.prefix(AppsFaceGrid.maxItems)` zipped with `AppsFaceGrid.cells(count:)`; per mini `context.saveGState()`, `setShadow(offset: CGSize(width: 0, height: -shadow.offset), blur: shadow.blur, color: black α)` when the seam returns one, draw `mini.image` (a copy with `size` set to the box size so `draw(in:)` scales the whole bitmap), `restoreGState()`. Doc comment: why a contact shadow (light icons vanish on near-white glass), why no squircle/sheen (the system draws the shape and the glass; flat minis are what iOS folders show).

- [ ] **Step 4: Run the tests to verify they pass**

Run: TEST(AppsFaceRenderTests), TEST(GlyphLayerRenderTests)
Expected: `TEST SUCCEEDED` (AppsFaceRenderTests: 8 passed; the glyph suite unchanged).

- [ ] **Step 5: Commit**

```bash
git add DockTile/Utilities/IconGenerator.swift DockTileTests/Unit/Utilities/AppsFaceRenderTests.swift
```
```bash
git commit -m "feat(icons): composite Apps-face layer PNG for the declarative pipeline"
```

---

### Task 5: `IconDocumentBuilder.appsFaceIconJSON` — system fills, explicit flat keys, real compile

**Files:**
- Modify: `DockTile/Utilities/DeclarativeIconPipeline.swift:29-95` (`IconDocumentBuilder`)
- Test: `DockTileTests/Unit/Utilities/IconDocumentBuilderTests.swift`, `DockTileTests/Unit/Utilities/IconCompilerTests.swift`

**Interfaces:**
- Consumes: `IconGenerator.generateAppsLayerPNG` (Task 4), the fixture (Task 1).
- Produces: `IconDocumentBuilder.systemLightFill = "system-light"`, `systemDarkFill = "system-dark"`, `appsFaceLayerName = "grid"`, `appsFaceImageName = "grid.png"`; `nonisolated static func appsFaceIconJSON() -> [String: Any]` — `"fill": "system-light"`; `"fill-specializations": [["value": "system-light"], ["appearance": "dark", "value": "system-dark"], ["appearance": "tinted", "value": "system-light"]]`; one group `["specular": false, "translucency": ["enabled": false, "value": 0], "shadow": ["kind": "none", "opacity": 0], "layers": [layer]]` where `layer` = `layerDict(LayerSpec(name: "grid", imageName: "grid.png", exclusiveTo: nil))` plus `"glass": false`; `"supported-platforms"` as today.

- [ ] **Step 1: Write the failing tests**

Append to `IconDocumentBuilderTests`:

```swift
    @Test("Apps face: system fills, one always-visible layer, and the flat look written explicitly")
    func appsFaceDocument() throws {
        let json = IconDocumentBuilder.appsFaceIconJSON()
        #expect(json["fill"] as? String == "system-light")
        let specs = try #require(json["fill-specializations"] as? [[String: Any]])
        #expect(specs.count == 3)
        #expect(specs[0]["appearance"] == nil && specs[0]["value"] as? String == "system-light")
        #expect(specs[1]["appearance"] as? String == "dark" && specs[1]["value"] as? String == "system-dark")
        #expect(specs[2]["appearance"] as? String == "tinted" && specs[2]["value"] as? String == "system-light")

        let group = try #require((json["groups"] as? [[String: Any]])?.first)
        #expect(group["specular"] as? Bool == false)
        let translucency = try #require(group["translucency"] as? [String: Any])
        #expect(translucency["enabled"] as? Bool == false && (translucency["value"] as? NSNumber)?.doubleValue == 0)
        let shadow = try #require(group["shadow"] as? [String: Any])
        #expect(shadow["kind"] as? String == "none" && (shadow["opacity"] as? NSNumber)?.doubleValue == 0)

        let layers = try #require(group["layers"] as? [[String: Any]])
        #expect(layers.count == 1)
        #expect(layers[0]["name"] as? String == "grid" && layers[0]["image-name"] as? String == "grid.png")
        #expect(layers[0]["glass"] as? Bool == false)
        #expect(layers[0]["fill"] as? String == "none")
        #expect(layers[0]["hidden-specializations"] == nil)
        #expect((json["supported-platforms"] as? [String: [String]])?["squares"] == ["macOS"])
        // The document serialises (no Swift tuples or enums leaked in).
        #expect(JSONSerialization.isValidJSONObject(json))
    }
```

Append to `IconCompilerTests` (beside `builderOutputCompilesToValidCar`):

```swift
    @MainActor
    @Test("End-to-end: the Apps-face document compiles to a valid layered car",
          .enabled(if: FileManager.default.fileExists(atPath: IconCompilerTests.builtCompilerPath)))
    func appsFaceDocumentCompilesToValidCar() throws {
        let scratch = try makeScratchDir()
        defer { try? FileManager.default.removeItem(at: scratch) }
        let mini = AppsFaceRenderTests.mini(.systemBlue)
        let png = try IconGenerator.generateAppsLayerPNG(
            minis: (0..<5).map { _ in .init(image: mini, isFolder: false) })
        let document = try IconDocumentBuilder.writeDocument(
            json: IconDocumentBuilder.appsFaceIconJSON(),
            layerPNGs: [IconDocumentBuilder.appsFaceImageName: png], name: "AppIcon", parent: scratch)
        let car = try IconCompiler.compile(
            document: document, outputDir: scratch.appendingPathComponent("out"),
            compilerURL: URL(fileURLWithPath: Self.builtCompilerPath))
        #expect(FileManager.default.fileExists(atPath: car.path))
    }

    /// The fixture's layer is SYNTHETIC (nine flat squares from `make-appgrid-layer.swift`); its
    /// `icon.json` is the spike's real system-fill document, which is what this pins.
    @Test("End-to-end: the preserved system-fill fixture (synthetic layer) compiles to a layered car",
          .enabled(if: FileManager.default.fileExists(atPath: IconCompilerTests.builtCompilerPath)))
    func appsFaceFixtureCompiles() throws {
        let document = Self.projectRoot.appendingPathComponent("docs/icon-spike-fixtures/appgrid-systemfill.icon")
        let outputDir = try makeScratchDir()
        defer { try? FileManager.default.removeItem(at: outputDir) }
        let car = try IconCompiler.compile(
            document: document, outputDir: outputDir, compilerURL: URL(fileURLWithPath: Self.builtCompilerPath))
        #expect(car.lastPathComponent == "Assets.car")
    }
```

(`compile` throws unless all three appearance stacks are present, so reaching the `#expect` is the structural proof.)

- [ ] **Step 2: Run the tests to verify they fail**

Run: TEST(IconDocumentBuilderTests), TEST(IconCompilerTests)
Expected: compile error `has no member 'appsFaceIconJSON'`.

- [ ] **Step 3: Implement in `DeclarativeIconPipeline.swift`**

Add the four constants and `appsFaceIconJSON()` to `IconDocumentBuilder`; reuse the private `layerDict` and add `"glass": false` to its result for this document only (a `layerDict(_:glass:)` parameter defaulting to `nil` = key omitted keeps the glyph document byte-identical — `IconDocumentBuilderTests.fixtureInvariants` and `symbolLayersSwapByHiddenSpecializations` guard that). Doc comment: why explicit flat keys (Apple's `actool` defaults: specular on, translucency 0.3, shadow 0.5 — washes real app icons; the vendored compiler ignores them, so explicit keys make the document mean the same under both), why `tinted` reuses `system-light`, and the fixture reference `docs/icon-spike-fixtures/appgrid-systemfill.icon`.

Decided 2026-10-19: the dark appearance keeps `system-dark` (Apple's own Apps icon and iOS folders go dark); the Customise caption (Task 10) therefore reads "A glass folder that follows Light and Dark Mode.", not the handoff's "looks the same".

- [ ] **Step 4: Run the tests to verify they pass**

Run: TEST(IconDocumentBuilderTests), TEST(IconCompilerTests)
Expected: `TEST SUCCEEDED`; the two new compiler tests execute (not skipped) on this Mac because `Vendor/actool/target/release/docktile-actool` exists.

- [ ] **Step 5: Commit**

```bash
git add DockTile/Utilities/DeclarativeIconPipeline.swift DockTileTests/Unit/Utilities/IconDocumentBuilderTests.swift DockTileTests/Unit/Utilities/IconCompilerTests.swift
```
```bash
git commit -m "feat(icons): Apps-face .icon document with system fills and explicit flat keys"
```

---

### Task 6: Fallback `.icns` and the macOS 15 four-variant bake

**Files:**
- Modify: `DockTile/Utilities/IconGenerator.swift` (`// MARK: - Apps face` section; `drawAppsGrid`'s `desaturate` wiring)
- Test: `DockTileTests/Unit/Utilities/AppsFaceRenderTests.swift` (append)

**Interfaces:**
- Consumes: `AppsFaceGrid.fillGrays/desaturatesMinis` (Task 3), `drawAppsGrid`, `buildIcns`, `createSquirclePath`, `drawGradient` (existing privates).
- Produces:
  - `static func appsIcon(minis: [AppsFaceMini], size: CGSize, iconStyle: IconStyle) -> NSImage` — explicit-pixel bitmap; clear; shape = canvas inset by `contentInsetRatio`; squircle (corner 22.5% of the shape) filled top→bottom with `fillGrays(style:)` as two `NSColor(white:alpha: 1)` stops; minis via `drawAppsGrid(…, desaturate: AppsFaceGrid.desaturatesMinis(style: iconStyle))`; no stroke, no sheen (flat, like the compiled icon)
  - `static func generateAppsFallbackIcns(minis: [AppsFaceMini], outputURL: URL) throws` = `buildIcns { appsIcon(minis:, size: $0, iconStyle: .defaultStyle) }`
  - `static func generateAppsIcns(minis: [AppsFaceMini], outputURL: URL, iconStyle: IconStyle) throws` = `buildIcns { appsIcon(minis:, size: $0, iconStyle: iconStyle) }`
  - `private static func desaturated(_ image: NSImage) -> NSImage` — `CIColorControls` with `kCIInputSaturationKey: 0` over the image's `CGImage`, back into an explicit-pixel `NSBitmapImageRep`; returns `image` if any step fails

- [ ] **Step 1: Write the failing tests**

Append to `AppsFaceRenderTests`:

```swift
    // MARK: - Fallback .icns and the legacy bake (same renderer, four styles)

    static func gray(_ rep: NSBitmapImageRep, _ x: Int, _ y: Int) throws -> CGFloat {
        let c = try #require(rep.colorAt(x: x, y: y)?.usingColorSpace(.sRGB))
        #expect(abs(c.redComponent - c.greenComponent) < 0.01 && abs(c.greenComponent - c.blueComponent) < 0.01,
                "not gray at (\(x),\(y)): \(c)")
        return c.redComponent
    }

    static func bake(_ style: IconStyle, minis: [IconGenerator.AppsFaceMini]) throws -> NSBitmapImageRep {
        let image = IconGenerator.appsIcon(minis: minis, size: CGSize(width: canvas, height: canvas), iconStyle: style)
        return try #require(image.representations.compactMap { $0 as? NSBitmapImageRep }.first)
    }

    @Test("Every style bakes the icon-grid margin and the system gray pair, top stop at the top",
          arguments: IconStyle.allCases)
    func bakeIsMarginedOnSystemGrays(_ style: IconStyle) throws {
        let rep = try Self.bake(style, minis: [.init(image: Self.mini(.systemBlue), isFolder: false)])
        #expect(Self.alpha(rep, 1, 512) == 0, "\(style): mid-edge painted — no margin")
        #expect(Self.alpha(rep, 512, 512) == 1)
        let run = Self.opaqueRun(rep, y: 512, fromX: 0)
        #expect(abs(run - 824) <= 2, "\(style): shape is \(run) px wide")
        let expected = AppsFaceGrid.fillGrays(style: style)
        #expect(abs(try Self.gray(rep, 512, 106) - expected.top) < 0.02, "\(style) top")
        #expect(abs(try Self.gray(rep, 512, 917) - expected.bottom) < 0.02, "\(style) bottom")
    }

    @Test("Dark is the dark pair, Default the light pair — independent pins")
    func grayPairsPinned() throws {
        let dark = try Self.bake(.dark, minis: [])
        #expect(abs(try Self.gray(dark, 512, 106) - 0.192) < 0.02)
        #expect(abs(try Self.gray(dark, 512, 917) - 0.078) < 0.02)
        let light = try Self.bake(.defaultStyle, minis: [])
        #expect(try Self.gray(light, 512, 106) > 0.98)
        #expect(abs(try Self.gray(light, 512, 917) - 0.925) < 0.02)
    }

    @Test("clearAndTintedVariantsDesaturateMinis: Default/Dark keep the mini's colour, Clear/Tinted are grayscale")
    func clearAndTintedVariantsDesaturateMinis() throws {
        let red = IconGenerator.AppsFaceMini(image: Self.mini(.systemRed, fullBleed: true), isFolder: true)
        let c0 = Self.centre(0, count: 1)
        for style in IconStyle.allCases {
            let c = try #require(try Self.bake(style, minis: [red]).colorAt(x: c0.x, y: c0.y)?.usingColorSpace(.sRGB))
            #expect(c.alphaComponent == 1)
            if AppsFaceGrid.desaturatesMinis(style: style) {
                #expect(c.saturationComponent < 0.05, "\(style) mini still coloured: \(c)")
            } else {
                #expect(c.saturationComponent > 0.6, "\(style) mini lost its colour: \(c)")
            }
        }
    }

    @Test("The written fallback .icns carries the margin and the light pair in its largest rendition")
    func fallbackIcnsFile() throws {
        let out = FileManager.default.temporaryDirectory.appendingPathComponent("docktile-apps-\(UUID().uuidString).icns")
        defer { try? FileManager.default.removeItem(at: out) }
        try IconGenerator.generateAppsFallbackIcns(
            minis: [.init(image: Self.mini(.systemBlue), isFolder: false)], outputURL: out)
        let image = try #require(NSImage(contentsOf: out))
        let rep = try #require(image.representations.compactMap { $0 as? NSBitmapImageRep }.max(by: { $0.pixelsWide < $1.pixelsWide }))
        #expect(rep.pixelsWide == 1024)
        #expect(Self.alpha(rep, 1, 512) == 0)
        #expect(try Self.gray(rep, 512, 106) > 0.98)
    }

    @Test("The legacy variant file is written for a non-default style")
    func legacyVariantFile() throws {
        let out = FileManager.default.temporaryDirectory.appendingPathComponent("docktile-apps-dark-\(UUID().uuidString).icns")
        defer { try? FileManager.default.removeItem(at: out) }
        try IconGenerator.generateAppsIcns(minis: [.init(image: Self.mini(.systemBlue), isFolder: false)],
                                           outputURL: out, iconStyle: .dark)
        let image = try #require(NSImage(contentsOf: out))
        let rep = try #require(image.representations.compactMap { $0 as? NSBitmapImageRep }.max(by: { $0.pixelsWide < $1.pixelsWide }))
        #expect(abs(try Self.gray(rep, 512, 106) - 0.192) < 0.02)
    }
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: TEST(AppsFaceRenderTests)
Expected: compile error `has no member 'appsIcon'`.

- [ ] **Step 3: Implement `appsIcon`, `generateAppsFallbackIcns`, `generateAppsIcns`, `desaturated` and wire `desaturate` through `drawAppsGrid`**

`drawGradient(context:path:topColor:bottomColor:rect:)` already draws top→bottom on the shape — pass `NSColor(white: grays.top, alpha: 1)` / `NSColor(white: grays.bottom, alpha: 1)`. Doc comment on `appsIcon`: the gray pair is the vendored compiler's resolution of `system-light`/`system-dark` (so the bake, the preview and the compiled icon agree), and Clear/Tinted minis are desaturated to keep the legacy path's grayscale promise.

- [ ] **Step 4: Run the tests to verify they pass**

Run: TEST(AppsFaceRenderTests), TEST(LegacyIcnsMarginTests)
Expected: `TEST SUCCEEDED` (AppsFaceRenderTests: 8 + 4 + 4 parameterised cases).

- [ ] **Step 5: Commit**

```bash
git add DockTile/Utilities/IconGenerator.swift DockTileTests/Unit/Utilities/AppsFaceRenderTests.swift
```
```bash
git commit -m "feat(icons): Apps-face fallback .icns and macOS 15 style variants on the system grays"
```

---

### Task 7: `AppIconLoader` resolves symlinks

**Files:**
- Modify: `DockTile/Utilities/AppIconLoader.swift:62-70` (`iconFromAppURL`)
- Test: `DockTileTests/Unit/Utilities/AppIconLoaderSymlinkTests.swift` (new)

**Interfaces:**
- Produces: `iconFromAppURL` fetches `NSWorkspace.shared.icon(forFile:)` on `appURL.resolvingSymlinksInPath().path` (one line; fixes the face AND the popover, per the spec's preference). `AppIconLoader.icon(for:)` signature unchanged.

- [ ] **Step 1: Write the failing test**

```swift
//  AppIconLoaderSymlinkTests.swift — /Applications/Safari.app is a symlink on macOS 27 and
//  NSWorkspace.icon(forFile:) on a symlink returns the icon with an alias-arrow badge.
import AppKit
import Testing
@testable import Dock_Tile

@MainActor
@Suite("AppIconLoader symlink resolution")
struct AppIconLoaderSymlinkTests {
    private func png(_ image: NSImage) throws -> Data {
        var rect = CGRect(x: 0, y: 0, width: 128, height: 128)
        let cg = try #require(image.cgImage(forProposedRect: &rect, context: nil, hints: nil))
        return try #require(NSBitmapImageRep(cgImage: cg).representation(using: .png, properties: [:]))
    }

    @Test("symlinkedAppIconHasNoAliasBadge: a symlink to Finder yields Finder's own icon bytes")
    func symlinkedAppIconHasNoAliasBadge() throws {
        let real = "/System/Library/CoreServices/Finder.app"
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let link = dir.appendingPathComponent("Finder.app")
        try FileManager.default.createSymbolicLink(atPath: link.path, withDestinationPath: real)

        // A bundle id Launch Services cannot resolve, so the loader takes the last-known-path branch.
        let item = AppItem(bundleIdentifier: "com.example.not-registered", name: "Finder", lastKnownPath: link.path)
        let viaLink = try png(try #require(AppIconLoader.icon(for: item)))
        let direct = try png(NSWorkspace.shared.icon(forFile: real))
        #expect(viaLink == direct)
        // Control (the badge was observed on macOS 27; earlier OSes are unverified, so only pin it
        // there): without the fix the loader returned exactly these alias-badged bytes.
        if #available(macOS 27.0, *) {
            let badged = try png(NSWorkspace.shared.icon(forFile: link.path))
            #expect(badged != direct, "the control is broken: the symlink's icon should carry an alias badge")
        }
    }
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: TEST(AppIconLoaderSymlinkTests)
Expected: FAIL on `viaLink == direct` (alias-badged bytes).

- [ ] **Step 3: Implement**

In `iconFromAppURL`, resolve before the `NSWorkspace` call; keep `loadIconDirectlyFromBundle` on the resolved path too. One sentence in the doc comment: symlinked bundles (Safari on macOS 27) returned an alias-badged icon.

- [ ] **Step 4: Run the test to verify it passes**

Run: TEST(AppIconLoaderSymlinkTests), TEST(TileIconRasterCacheTests)
Expected: `TEST SUCCEEDED`.

- [ ] **Step 5: Commit**

```bash
git add DockTile/Utilities/AppIconLoader.swift DockTileTests/Unit/Utilities/AppIconLoaderSymlinkTests.swift
```
```bash
git commit -m "fix(icons): resolve symlinks before fetching an app's icon (no alias badge)"
```

---

### Task 8: Bake-time wiring in `HelperBundleManager` + diagnostics line

**Files:**
- Modify: `DockTile/Managers/HelperBundleManager.swift:860-1030` (`installTileIcons`, `installDeclarativeIcon`, new `appsFaceMinis`, new `installCompiledIcon`)

**Interfaces:**
- Consumes: `AppsFaceGrid.select`, `IconGenerator.generateAppsLayerPNG/generateAppsFallbackIcns/generateAppsIcns`, `IconDocumentBuilder.appsFaceIconJSON/appsFaceImageName`, `AppIconLoader.icon(for:)`, `AppInstallChecker.resolve(_:)`.
- Produces:
  - `func appsFaceMinis(for config: DockTileConfiguration) -> (minis: [IconGenerator.AppsFaceMini], skipped: Int)` — `AppsFaceGrid.select(items: config.appItems) { AppInstallChecker.resolve($0).status == .installed }`, each selected item → `AppIconLoader.icon(for:)` (an item whose icon is `nil` counts as skipped too), `isFolder: item.isFolder`
  - `private func installCompiledIcon(json: [String: Any], layerPNGs: [String: Data], resourcesPath: URL) async throws` — the scratch-dir / `writeDocument(name: "AppIcon")` / `compileOffMain` / copy-`Assets.car` body lifted verbatim out of `installDeclarativeIcon`, which now calls it
  - `installTileIcons` branch: `if config.iconFace == .apps { let face = appsFaceMinis(for: config); if face.minis.isEmpty { log "Apps face for \(diagnosticName): no installed items — baking the glyph face" } else { if face.skipped > 0 { log("tile", "Apps face for \(diagnosticName): skipped \(face.skipped) missing item(s)") }; legacy → four `generateAppsIcns` variants + copy current (same loop shape as today); declarative → `installCompiledIcon(json: appsFaceIconJSON(), layerPNGs: [appsFaceImageName: generateAppsLayerPNG(minis:)])` + `generateAppsFallbackIcns`; return } }` — both log lines non-verbose (`tile` category), then the existing glyph path runs unchanged

No unit test reaches this `@MainActor`, filesystem-bound method (the decisions it composes are the seams tested in Tasks 3–6); its verification is hands-on.

- [ ] **Step 1: Implement the three methods and the branch**

Keep the glyph path's code untouched below the new early-return; `helperIconsComplete` needs no change (same filenames on disk).

- [ ] **Step 2: Build and run the whole suite**

Run: `xcodebuild -project DockTile.xcodeproj -scheme DockTile -configuration Debug build` then TEST(all)
Expected: build succeeds; `TEST SUCCEEDED`.

- [ ] **Step 3: Hands-on: bake a real Apps-face tile with the dev build**

Rebuild signed (no `CODE_SIGNING_ALLOWED=NO`), `codesign --verify` the product, launch it. The face has no UI yet, so set it on a dev tile by editing the dev config once: `python3 -I -c` reading `~/Library/Preferences/com.docktile.dev.configs.json`, setting `"iconFace": "apps"` on one tile that has ≥5 installed apps and one deliberately missing item, writing it back (dev data only — never the Release config). Relaunch the dev app, press **Update** on that tile. Then:

```bash
H=~/Library/Application\ Support/DockTile-Dev/<Tile>.app
assetutil --info "$H/Contents/Resources/Assets.car" | grep -c '"AssetType" : "IconImageStack"'   # 3
grep -c "Apps face for" ~/Library/Application\ Support/DockTile-Dev/diagnostics.log               # ≥ 1, says "skipped 1 missing item(s)"
```

Look at the Dock tile under Light and Dark (System Settings → Appearance) and at the helper in Finder; the glass squircle, shadow and highlight are the system's, the minis are flat. Capture evidence by window ID only (driving-the-dev-build.md). Record what the Tinted / Clear styles do to the nine minis in the commit message or the Task 12 doc — the spec's open observation.

- [ ] **Step 4: Commit**

```bash
git add DockTile/Managers/HelperBundleManager.swift
```
```bash
git commit -m "feat(icons): bake the Apps face into helpers (skips missing items, glyph fallback when none)"
```

---

### Task 9: `DockTileIconPreview` Apps mode (hero, sidebar `TileFace`, Tile Detail)

**Files:**
- Modify: `DockTile/Components/DockTileIconPreview.swift` (stored `appsFaceItems`, full initializer, `fromConfig`, `body`; no strings — the VoiceOver label lands with its catalog entry in Task 10)
- Test: `DockTileTests/Unit/Components/AppsFacePreviewTests.swift` (new)

**Interfaces:**
- Consumes: `AppsFaceGrid.*`, `TileIconRasterCache.shared.image(for:pointSize:scale:appearanceToken:contentStamp:)`, `TileIconRasterCache.liveAppearanceToken(isDark:)`, `TileIconRasterCache.contentStamp(for:resolvedPath:)`, `AppInstallChecker.resolve(_:)`, `IconStyle.forDisplay` via the existing `iconStyle` computed property.
- Produces:
  - `DockTileIconPreview.appsFaceItems: [AppItem]` — stored `let`, default `[]`; a new trailing parameter `appsFaceItems: [AppItem] = []` on the full initializer; the two legacy initializers set `[]`
  - `fromConfig` passes `config.iconFace == .apps ? config.appItems : []`
  - `private var appsFaceMinis: [AppItem]` = `AppsFaceGrid.select(items: appsFaceItems) { AppInstallChecker.resolve($0).status == .installed }.selected`
  - `body`: `if !appsFaceMinis.isEmpty { appsFaceBody } else { <existing ZStack> }` — so zero resolvable items IS the glyph face
  - `appsFaceBody`: a `RoundedRectangle(cornerRadius:, style: .continuous)` filling the frame with a vertical `LinearGradient` of `Color(white: grays.top)` → `Color(white: grays.bottom)` from `AppsFaceGrid.fillGrays(style: iconStyle)`; one `Image(decorative: cgImage, scale: displayScale)` per mini at `AppsFaceGrid.rect(drawBox(cell), in: full frame, yUp: false)` (`.resizable().frame(width:height:).position(x:y:)`), with `.saturation(0)` when `AppsFaceGrid.desaturatesMinis(style: iconStyle)` and `.shadow(color:radius:y:)` from `AppsFaceGrid.miniShadow(nominalSize: size)`; minis come from `TileIconRasterCache.shared.image(for: item, pointSize: box.width, scale: displayScale, appearanceToken: TileIconRasterCache.liveAppearanceToken(isDark: colorScheme == .dark), contentStamp: TileIconRasterCache.contentStamp(for: item, resolvedPath: AppInstallChecker.resolve(item).resolvedPath))` — never the IconServices `NSImage`; `@Environment(\.displayScale) private var displayScale`
  - The VoiceOver label is added in Task 10 together with its catalog entry (a key in code without a catalog entry fails `LocalizationCatalogTests.codeKeysExistInCatalog`, so no commit may separate the two)

- [ ] **Step 1: Write the failing tests**

```swift
//  AppsFacePreviewTests.swift — renders the REAL DockTileIconPreview in Apps mode through
//  ImageRenderer (as IconPreviewGeometryTests does) and scans pixels.
import AppKit
import SwiftUI
import Testing
@testable import Dock_Tile

@MainActor
@Suite("Apps face preview")
struct AppsFacePreviewTests {
    private static let side: CGFloat = 256
    private static let finder = AppItem(bundleIdentifier: "com.apple.finder", name: "Finder",
                                        lastKnownPath: "/System/Library/CoreServices/Finder.app")
    private static let ghost = AppItem(bundleIdentifier: "com.example.not-installed", name: "Nope")

    private func render(items: [AppItem], style: IconStyle) throws -> NSBitmapImageRep {
        let view = DockTileIconPreview(
            tintColor: .blue, iconType: .sfSymbol, iconValue: "star.fill", iconScale: 14,
            iconWeight: .medium, background: .colour, size: Self.side, appsFaceItems: items
        ).forcing(style)
        let renderer = ImageRenderer(content: view)
        renderer.scale = 1
        return NSBitmapImageRep(cgImage: try #require(renderer.cgImage))
    }
    private func png(_ rep: NSBitmapImageRep) throws -> Data {
        try #require(rep.representation(using: .png, properties: [:]))
    }
    private func srgb(_ rep: NSBitmapImageRep, _ x: Int, _ y: Int) throws -> NSColor {
        try #require(rep.colorAt(x: x, y: y)?.usingColorSpace(.sRGB))
    }
    private static let frame = CGRect(x: 0, y: 0, width: side, height: side)
    private static func cell(_ i: Int, count: Int) -> CGRect {
        AppsFaceGrid.rect(AppsFaceGrid.cells(count: count)[i], in: frame, yUp: false)
    }
    /// Highest saturation along the cell's centre row — Finder's icon is half dark blue, half
    /// white face, so a single centre pixel could land on the seam between them.
    private func maxSaturation(_ rep: NSBitmapImageRep, in cell: CGRect) throws -> CGFloat {
        try [0.2, 0.35, 0.5, 0.65, 0.8].map { f in
            try srgb(rep, Int(cell.minX + cell.width * f), Int(cell.midY)).saturationComponent
        }.max() ?? 0
    }

    @Test("One installed app: light glass fills the frame, the mini sits top-left, the other cells are glass")
    func oneAppOnLightGlass() throws {
        let rep = try render(items: [Self.finder], style: .defaultStyle)
        let top = try srgb(rep, 128, 4)                      // full-frame shape, no icon-grid margin
        #expect(top.redComponent > 0.97 && abs(top.redComponent - top.blueComponent) < 0.02)
        let bottom = try srgb(rep, 128, 251)
        #expect(abs(bottom.redComponent - 0.925) < 0.03)
        let cell0 = Self.cell(0, count: 1)                 // the single centred 0.60 cell (51…205 px)
        #expect(abs(cell0.midX - 128) < 1)
        #expect(try maxSaturation(rep, in: cell0) > 0.3, "the centred cell shows glass, not Finder")
        // Inside the shape, left of the mini's draw box (33…223 px): empty glass.
        let glass = try srgb(rep, 20, 128)
        #expect(glass.saturationComponent < 0.03 && glass.redComponent > 0.9, "beside the mini is not empty glass: \(glass)")
    }

    @Test("Forced Dark draws the dark pair")
    func darkGlass() throws {
        let rep = try render(items: [Self.finder], style: .dark)
        #expect(abs(try srgb(rep, 128, 4).redComponent - 0.192) < 0.03)
        #expect(abs(try srgb(rep, 128, 251).redComponent - 0.078) < 0.03)
    }

    @Test("Clear / Tinted previews keep the light glass and drain the minis' colour")
    func clearAndTintedDesaturate() throws {
        for style in [IconStyle.clear, .tinted] {
            let rep = try render(items: [Self.finder], style: style)
            #expect(try srgb(rep, 128, 4).redComponent > 0.97, "\(style)")
            #expect(try maxSaturation(rep, in: Self.cell(0, count: 1)) < 0.05, "\(style)")
        }
    }

    @Test("unresolvableItemsFallBackToGlyph: every item missing renders the glyph face byte-for-byte")
    func unresolvableItemsFallBackToGlyph() throws {
        let apps = try png(try render(items: [Self.ghost, Self.ghost], style: .defaultStyle))
        let glyph = try png(try render(items: [], style: .defaultStyle))
        #expect(apps == glyph)
    }

    @Test("fromConfig routes the items only for an Apps-face tile")
    func fromConfigRoutesByFace() {
        var config = DockTileConfiguration(name: "Work", iconFace: .glyph, appItems: [Self.finder])
        #expect(DockTileIconPreview.fromConfig(config, size: 44).appsFaceItems.isEmpty)
        config.iconFace = .apps
        #expect(DockTileIconPreview.fromConfig(config, size: 44).appsFaceItems == [Self.finder])
    }
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: TEST(AppsFacePreviewTests)
Expected: compile error `extra argument 'appsFaceItems' in call`.

- [ ] **Step 3: Implement the Apps mode**

Doc comments on `appsFaceBody`: Light/Dark keys on `iconStyle` (`IconStyle.forDisplay`, like Mono — never raw `colorScheme`); the full frame is the shape (UI slot rule); minis are cache bitmaps (icon-system rule); the gray pair is the compiler's resolution of the system fills. `TileFace` needs no change — `fromConfig` carries the face.

- [ ] **Step 4: Run the tests to verify they pass**

Run: TEST(AppsFacePreviewTests), TEST(IconPreviewGeometryTests), TEST(IconPreviewBackgroundTests), TEST(TileFaceTests)
Expected: `TEST SUCCEEDED` (AppsFacePreviewTests: 5 passed).

- [ ] **Step 5: Commit**

```bash
git add DockTile/Components/DockTileIconPreview.swift DockTileTests/Unit/Components/AppsFacePreviewTests.swift
```
```bash
git commit -m "feat(ui): Apps-face preview — cache-backed minis on the system grays"
```

---

### Task 10: Customise Tile — two-column canvas + inspector, Style picker, Apps card; strings in every language; resizable window

**Files:**
- Modify: `DockTile/Views/CustomiseTileView.swift` (whole layout; `IconPickerTab` ~583 becomes `TileStyle`; `init` ~33; `heroStyles` ~126; `studioCanvas`/`heroTile` ~157-206; `inspectorCard` ~210; `backgroundSection`/`colourSection`/`tileIconSizeSection`/`tileIconSection` ~245-548; `BackgroundChip` ~747; the `.paneTitleBand`/toolbar Back ~49-59)
- Modify: `DockTile/Views/DockTileDetailView.swift:245-262` (sync `iconFace` from the saved config, beside `iconType`)
- Modify: `DockTile/Components/DockTileIconPreview.swift` (`.accessibilityLabel` on `appsFaceBody` from Task 9)
- Modify: `DockTile/Constants/AppStrings.swift` (18 new keys, below)
- Modify (window): `DockTile/App/AppDelegate.swift:29` (`fixedWindowWidth`), `:172-173` (`contentMinSize`/`contentMaxSize`), `:177-179` (frame width fix-up), `:187-190` (`windowWillResize`); `DockTile/App/DockTileApp.swift:23` (`windowWidth`), `:77-78` (`.windowResizability(.contentSize)` + `.defaultSize`); `DockTile/Views/DockTileConfigurationView.swift:58` (`windowWidth`), `:78-84` (`.frame(minWidth:idealWidth:maxWidth:…)`), `:271` (`WindowAccessor.fixedWidth`), `:306-316` (`contentMinSize`/`contentMaxSize`/width fix-up)
- Modify: `DockTile/Resources/Localizable.xcstrings` only via `l10n.py sync-keys` / `import`; `docs/l10n/zh-Hans.md`, `ja.md`, `de.md`, `ru.md`, `fr.md`
- Test: `DockTileTests/Unit/Views/CustomiseStyleTests.swift` (new), `DockTileTests/Unit/Views/CustomiseHeroStylesTests.swift`, run `CustomiseColourRowStateTests`, `LocalizationCatalogTests`, `AppStringsTests`, `SystemSymbolNameTests`, `AppsFacePreviewTests`

Source of truth: `docs/design_handoff_customise_tile/README.md`, with the mock beside it — `Customise Tile.dc.html` (layout, copy, states) and `Tile Icon.dc.html` (per-style tile anatomy). The README is the extracted spec; open the mock for anything it leaves visual. Keep the app's categorised 7-column pickers and the pinned DockTile brand category, the system accent and real SF Symbols, as the README says.

**Interfaces:**
- Consumes: `DockTileIconPreview(… appsFaceItems:)` (Task 9), `AppsFaceGrid.columns(count:)` / `maxItems` (Task 3), `IconFace` (Task 2).
- Produces (all on `CustomiseTileView`, `nonisolated static` unless noted):
  - `enum TileStyle: CaseIterable, Equatable { case apps, symbol, emoji }` (internal — replaces the private `IconPickerTab`), `init(face: IconFace, iconType: IconType)` (`.apps` → `.apps`; `.glyph` + `.sfSymbol` → `.symbol`; `.glyph` + `.emoji` → `.emoji`), `var label: String` (`AppStrings.Label.styleAppPreview` / `AppStrings.Tab.symbol` / `AppStrings.Tab.emoji`)
  - `applyStyle(_ style: TileStyle, to config: DockTileConfiguration) -> DockTileConfiguration` — `.apps`: `iconFace = .apps`, every glyph field untouched; `.symbol`: `iconFace = .glyph`, `iconType = .sfSymbol`, `iconValue` kept when it already is a symbol else `ConfigurationDefaults.iconValue`; `.emoji`: `iconFace = .glyph`, `iconType = .emoji`, `iconValue` kept when already an emoji else `ConfigurationDefaults.symbolEmoji`; `symbolEmoji` mirrors `iconValue` whenever it changes
  - `heroStyles(background: TileBackground, followsAppearance: Bool, iconFace: IconFace) -> [IconStyle?]` — `.apps` → `[nil]` (single hero); `.glyph` + `.colour` → `[nil]`; `.glyph` + `.mono` → `followsAppearance ? [.defaultStyle, .dark] : [.defaultStyle]` (the Light/Dark pair)
  - `enum InspectorSection: Equatable { case stylePicker, apps, background, colour, iconSize, iconWeight, picker }`; `inspectorSections(face: IconFace, background: TileBackground, iconType: IconType) -> [InspectorSection]` — `.apps` → `[.stylePicker, .apps]`; glyph → `[.stylePicker, .background]` + `.colour` unless `background == .mono && iconType == .emoji` + `.iconSize` + `.iconWeight` only for `.sfSymbol` + `.picker`, in that order
  - `struct AppsSummary: Equatable { let shown: String; let arrangement: String; let note: String }`; `appsSummary(count: Int) -> AppsSummary` — `shown` = `AppStrings.Label.appsShownValue(min(count, AppsFaceGrid.maxItems), count)`; `arrangement`: 0 → `"—"` (an em dash, not copy — nothing is arranged), else by `AppsFaceGrid.columns(count:)`: 1 → `appsArrangementFills`, 2 → `appsArrangementTwoByTwo`, 3 → `appsArrangementThreeByThree`; `note`: 0 → `appsNoteNone`, 1 → `appsNoteOne`, 2…9 → `appsNoteAll(count)`, ≥ 10 → `appsNoteFirstNine(count)`
  - Layout (README "Screen layout"): the pane is `HStack(alignment: .top, spacing: 18)` of **canvas** (flexible, `minWidth: 250`, 12 pt continuous radius, inset hairline `.quinaryLabel`) and **inspector** (`ScrollView` of `VStack(spacing: 18)`, `.frame(width: 260)`); the `.paneTitleBand(…)` modifier and the `.navigation` toolbar Back button are REMOVED from this view; the canvas carries a floating pill at top-leading (`padding(12)`): `Button { onBack() } label: { Label(AppStrings.Button.selectApps, systemImage: "chevron.left") }`, `.buttonStyle(.plain)`, glass capsule (`.glassEffect(.regular, in: .capsule)` under `#available(macOS 26, *)`, else `.background(.regularMaterial, in: Capsule())`); the tile name (`configManager.displayName(for:)`, 13 pt medium) sits under the hero. Single hero: one 100 pt `DockTileIconPreview(… appsFaceItems:)` centred on `StudioCanvasBackgroundView`; pair: two stacked halves — light (same background, 88 pt tile forced `.defaultStyle`, caption `Label(previewLight, systemImage: "sun.max")`) and dark (`LinearGradient(colors: [Color(white: 0.17), Color(white: 0.11)])`, 88 pt tile forced `.dark`, caption `Label(previewDark, systemImage: "moon")` in `.environment(\.colorScheme, .dark)`); `IconGridOverlay` only when `iconFace == .glyph`
  - Style picker (always first in the inspector): header-less `HStack(spacing: 10)` of three equal white cards (`NSColorBackgroundView.formGroup`, 12 pt radius, hairline inset), each a `Button` with a 32 pt `DockTileIconPreview` rendered in that style from the CURRENT settings (`.apps` card: `appsFaceItems: editedConfig.appItems`; `.symbol` card: `iconType: .sfSymbol, iconValue: applyStyle(.symbol, to: editedConfig).iconValue`; `.emoji` card likewise), a 12 pt medium label, and on the selected card a 2 pt `Color.accentColor` ring plus a 16 pt `checkmark.circle.fill` badge top-trailing; `.accessibilityAddTraits(.isSelected)`; tap → `editedConfig = Self.applyStyle(style, to: editedConfig)` (auto-saves through the existing `onChange(of: editedConfig)`); `selectedStyle` is a computed `TileStyle(face:iconType:)`, not `@State`
  - Apps section: group header `AppStrings.Label.appsHeader` (15 pt semibold, `.tertiary`); one white card with two 46 pt rows `appsShown` → `summary.shown` and `appsArrangement` → `summary.arrangement` (hairline between); caption under the card (12 pt `.secondary`): `summary.note + " " + AppStrings.Label.appsGlass`
  - Symbol/Emoji sections: **Background** header + two `BackgroundChip`s restyled as white cards (32 pt thumbnail — today's Colour / diagonal Mono split — label semibold when selected, accent ring) + caption (`backgroundHintColour` / `backgroundHintMono` (or `backgroundHintMonoStatic` on macOS 15), and for `.emoji` append `" " + backgroundHintEmojiColours`); **Colour** card (only when `inspectorSections` contains `.colour`): header `tileColour` (Colour) / `symbolColour` (Mono) with a right-aligned caption — Colour: `colourHint(colourRow)` as today (`colourHintFills` / `colourHintDeepened`), Mono: `colourHintTints` — above today's `colourPickerStrip` (20 pt swatches); **Icon Size** white card: `iconSize` row with the stepper (10–19 symbols / 10–22 emoji, unchanged) and, for `.sfSymbol` only, the `iconWeight` row with the existing pop-up + info button; **picker**: header `Tab.symbol` / `Tab.emoji`, a white card holding today's `iconSearchField` (placeholders `Search.symbols` / `Search.emojis` — existing strings, kept) and the existing `SymbolPickerGrid` / `EmojiPickerGrid` (cells unchanged)
  - `DockTileIconPreview.appsFaceBody` gets `.accessibilityLabel(AppStrings.Label.appsFaceAccessibility(appsFaceMinis.count))`
  - **Inspector fit (controller ruling, 2026-10-19 — the 260 pt inspector cannot hold today's grids):** follow the handoff mock, not "cells unchanged": `SymbolPickerGrid` and `EmojiPickerGrid` lay out **6 columns** of 42 pt rows — symbol cell a 34 pt circle (selected: accent fill, white glyph, drawn at the chosen weight), emoji cell a 36 pt rounded square (selected: 20 % accent fill + 1.5 pt accent ring) — KEEPING the category captions and the pinned DockTile brand category. Grep their call sites first; if any caller other than Customise exists, add a `columns:`/cell-size parameter instead of changing the shared default. Colour swatches become **20 pt** (7 presets + the custom button, 6 pt spacing ≈ 202 pt) with the handoff's selected look (white inner ring + white check). Verify by building and reading the AX frame widths in the hands-on step, never by eye.
  - **Top of the pane (controller ruling):** with the title band removed, the canvas extends under the transparent 52 pt toolbar strip (`.ignoresSafeArea(edges: .top)`, as today's `StudioCanvasBackgroundView` does); the inspector `ScrollView` stays in the safe area and carries `paneScrollEdgeEffect()` (architecture.md: every scrolling pane under the band needs it).
  - **Orphans (coding guardrails):** after the rewrite, grep each of `colourHintToned`, `colourHintTonedStatic`, `colourHintEmoji` and any other accessor the old layout used; delete accessors with no remaining caller and their catalog keys through `l10n.py` if it supports removal, else leave the catalog entries and say so in the report.
  - Window: the four `768` constants become `minWindowWidth = 782` + `maxWindowWidth = 1200` (`AppDelegate.swift:29`, `DockTileApp.swift:23`, `DockTileConfigurationView.swift:58`, `:271`); `contentMinSize.width = 782`, `contentMaxSize.width = 1200` (`AppDelegate.swift:172-173`, `DockTileConfigurationView.swift:306-307`); the two "fix width if incorrect" blocks (`AppDelegate.swift:177-179`, `DockTileConfigurationView.swift:314-316`) clamp into 782…1200 instead of forcing one value; `AppDelegate.windowWillResize` (`:187-190`) returns `width: min(max(frameSize.width, 782), 1200)`; `DockTileConfigurationView.swift:78-84` `.frame(minWidth: 782, idealWidth: 782, maxWidth: 1200, …)`; `DockTileApp.swift:78` `.defaultSize(width: 782, height: 600)` with `.windowResizability(.contentSize)` kept. No test pins the width (`grep -rn 768 DockTileTests` is empty; `MacOSFloorGuardTests` pins only the OS floor).
  - Strings — every value exactly as the handoff README writes it (three-argument `NSLocalizedString` shape, en-GB; `label.apps.note.none` is builder copy for the zero-item case the README does not cover):
    - `AppStrings.Button.selectApps` — `"button.selectApps"`, `"Select Apps"`, comment "Customise Tile: floating pill that returns to Tile Detail"
    - `AppStrings.Label.styleAppPreview` — `"label.style.appPreview"`, `"App Preview"`, comment "Customise Tile: Style picker card for the Apps face" (Symbol / Emoji cards reuse `tab.symbol` / `tab.emoji`)
    - `Label.appsHeader` — `"label.apps.header"`, `"Apps"`, comment "Customise Tile: group header above the Apps card"
    - `Label.appsShown` — `"label.apps.shown"`, `"Shown"`, comment "Customise Tile: Apps card row — how many apps the face shows"
    - `static func Label.appsShownValue(_ shown: Int, _ total: Int) -> String` — `"label.apps.shownValue"`, `"%1$lld of %2$lld"`, comment "Customise Tile: Apps card Shown value, e.g. 9 of 12; %1$lld = shown, %2$lld = total (positional so a language may reorder them)"
    - `Label.appsArrangement` — `"label.apps.arrangement"`, `"Arrangement"`, comment "Customise Tile: Apps card row — the grid the face uses"
    - `Label.appsArrangementFills` — `"label.apps.arrangement.fills"`, `"Fills the Tile"`, comment "Customise Tile: Arrangement value for one app"
    - `Label.appsArrangementTwoByTwo` — `"label.apps.arrangement.twoByTwo"`, `"2 × 2"`, comment "Customise Tile: Arrangement value for 2–4 apps"
    - `Label.appsArrangementThreeByThree` — `"label.apps.arrangement.threeByThree"`, `"3 × 3"`, comment "Customise Tile: Arrangement value for 5 or more apps"
    - `Label.appsNoteOne` — `"label.apps.note.one"`, `"Shows the only app in this tile."`, comment "Customise Tile: Apps caption, one app"
    - `static func Label.appsNoteAll(_ count: Int) -> String` — `"label.apps.note.all"`, `"Shows all %lld apps, in tile order."`, comment "Customise Tile: Apps caption, 2–9 apps; %lld = app count"
    - `static func Label.appsNoteFirstNine(_ count: Int) -> String` — `"label.apps.note.firstNine"`, `"Shows the first 9 of %lld apps, in tile order."`, comment "Customise Tile: Apps caption, more than nine apps; %lld = app count"
    - `Label.appsNoteNone` — `"label.apps.note.none"`, `"No apps yet — add some in Tile Detail."`, comment "Customise Tile: Apps caption when the tile has no apps (builder copy, not in the handoff)"
    - `Label.appsGlass` — `"label.apps.glass"`, `"A glass folder that follows Light and Dark Mode."`, comment "Customise Tile: fixed sentence after the Apps caption (decided 2026-10-19: the dark appearance is system-dark)"
    - `Label.tileColour` — `"label.tileColour"`, `"Tile Colour"`, comment "Customise Tile: Colour card header for a Colour tile"
    - `Label.colourHintTints` — `"label.colour.hint.tints"`, `"Tints the symbol"`, comment "Customise Tile: Colour card caption for a Mono tile"
    - `Label.backgroundHintEmojiColours` — `"label.background.hint.emojiColours"`, `"Emoji keep their own colours."`, comment "Customise Tile: appended to the Background caption for an Emoji tile"
    - `static func Label.appsFaceAccessibility(_ count: Int) -> String` — `"label.appsFace.accessibility"`, `"Apps face: showing %lld of this tile's apps"`, comment "VoiceOver label for a tile preview showing the Apps face; %lld = number of app icons shown"
  - Diagnostics: `DiagnosticsLog.shared.ui("Customise → Style '\(style)'")` on a card tap; `.onChange(of: editedConfig.iconFace) { DiagnosticsLog.shared.log("tile", "Face changed to \(newValue.rawValue) for \(editedConfig.diagnosticName)") }`; `ui("Customise → Select Apps (back to Tile Detail)")` on the pill

- [ ] **Step 1: Write the failing tests**

`DockTileTests/Unit/Views/CustomiseStyleTests.swift` (English expectations — like `SmartAddEngineTests`, passes only on an English test host):

```swift
import Testing
@testable import Dock_Tile

@Suite("Customise style picker seams")
@MainActor   // nested in a View (main-actor) type, like the sibling suites
struct CustomiseStyleTests {
    @Test("The selected Style card follows the face, then the icon type")
    func styleFromConfig() {
        #expect(CustomiseTileView.TileStyle(face: .apps, iconType: .emoji) == .apps)
        #expect(CustomiseTileView.TileStyle(face: .glyph, iconType: .sfSymbol) == .symbol)
        #expect(CustomiseTileView.TileStyle(face: .glyph, iconType: .emoji) == .emoji)
        #expect(CustomiseTileView.TileStyle.allCases == [.apps, .symbol, .emoji])
    }

    @Test("applyStyle: App Preview keeps the glyph behind it; Symbol/Emoji switch the glyph and clear the face")
    func applyStyle() {
        let items = [AppItem(bundleIdentifier: "com.apple.Safari", name: "Safari")]
        let symbol = DockTileConfiguration(name: "W", tintColor: .preset(.red), iconType: .sfSymbol, iconValue: "bolt",
                                           iconFace: .glyph, appItems: items)
        let apps = CustomiseTileView.applyStyle(.apps, to: symbol)
        #expect(apps.iconFace == .apps)
        #expect(apps.iconType == .sfSymbol && apps.iconValue == "bolt" && apps.tintColor == .preset(.red))
        let back = CustomiseTileView.applyStyle(.symbol, to: apps)
        #expect(back.iconFace == .glyph && back.iconValue == "bolt")
        #expect(CustomiseTileView.applyStyle(.symbol, to: symbol) == symbol)

        let emoji = CustomiseTileView.applyStyle(.emoji, to: symbol)
        #expect(emoji.iconFace == .glyph && emoji.iconType == .emoji)
        #expect(emoji.iconValue == ConfigurationDefaults.symbolEmoji && emoji.symbolEmoji == ConfigurationDefaults.symbolEmoji)

        let emojiTile = DockTileConfiguration(name: "E", iconType: .emoji, iconValue: "🎬", iconFace: .glyph)
        let toSymbol = CustomiseTileView.applyStyle(.symbol, to: emojiTile)
        #expect(toSymbol.iconType == .sfSymbol && toSymbol.iconValue == ConfigurationDefaults.iconValue)
        #expect(CustomiseTileView.applyStyle(.emoji, to: emojiTile) == emojiTile)
    }

    @Test("appsSummary: Shown, Arrangement and the note for 0, 1, 4, 9 and 12 apps")
    func appsSummary() {
        typealias S = CustomiseTileView.AppsSummary
        #expect(CustomiseTileView.appsSummary(count: 1) == S(shown: "1 of 1", arrangement: "Fills the Tile", note: "Shows the only app in this tile."))
        #expect(CustomiseTileView.appsSummary(count: 4) == S(shown: "4 of 4", arrangement: "2 × 2", note: "Shows all 4 apps, in tile order."))
        #expect(CustomiseTileView.appsSummary(count: 9) == S(shown: "9 of 9", arrangement: "3 × 3", note: "Shows all 9 apps, in tile order."))
        #expect(CustomiseTileView.appsSummary(count: 12) == S(shown: "9 of 12", arrangement: "3 × 3", note: "Shows the first 9 of 12 apps, in tile order."))
        #expect(CustomiseTileView.appsSummary(count: 0) == S(shown: "0 of 0", arrangement: "—", note: "No apps yet — add some in Tile Detail."))
        #expect(AppStrings.Label.appsGlass == "A glass folder that follows Light and Dark Mode.")
    }

    @Test("inspectorSections: App Preview has no knobs; Symbol/Emoji re-house today's controls")
    func inspectorSections() {
        typealias I = CustomiseTileView.InspectorSection
        for background in TileBackground.allCases { for type in [IconType.sfSymbol, .emoji] {
            #expect(CustomiseTileView.inspectorSections(face: .apps, background: background, iconType: type) == [.stylePicker, .apps])
        } }
        #expect(CustomiseTileView.inspectorSections(face: .glyph, background: .colour, iconType: .sfSymbol)
                == [I.stylePicker, .background, .colour, .iconSize, .iconWeight, .picker])
        #expect(CustomiseTileView.inspectorSections(face: .glyph, background: .mono, iconType: .sfSymbol)
                == [I.stylePicker, .background, .colour, .iconSize, .iconWeight, .picker])
        #expect(CustomiseTileView.inspectorSections(face: .glyph, background: .colour, iconType: .emoji)
                == [I.stylePicker, .background, .colour, .iconSize, .picker])
        #expect(CustomiseTileView.inspectorSections(face: .glyph, background: .mono, iconType: .emoji)
                == [I.stylePicker, .background, .iconSize, .picker])          // Colour card hidden, not disabled
    }
}
```

Replace `CustomiseHeroStylesTests` bodies with the three-argument seam and add:

```swift
    @Test("Colour follows the live style (one preview) whatever the OS")
    func colour() {
        #expect(CustomiseTileView.heroStyles(background: .colour, followsAppearance: true, iconFace: .glyph) == [nil])
        #expect(CustomiseTileView.heroStyles(background: .colour, followsAppearance: false, iconFace: .glyph) == [nil])
    }

    @Test("Mono shows the stacked Light / Dark pair only where the icon is compiled per appearance")
    func monoFollowsAppearance() {
        #expect(CustomiseTileView.heroStyles(background: .mono, followsAppearance: true, iconFace: .glyph) == [.defaultStyle, .dark])
    }

    @Test("Mono on the macOS 15 legacy bake is one light preview")
    func monoStatic() {
        #expect(CustomiseTileView.heroStyles(background: .mono, followsAppearance: false, iconFace: .glyph) == [.defaultStyle])
    }

    @Test("App Preview is one live hero even on a Mono tile")
    func appsFaceIsOnePreview() {
        #expect(CustomiseTileView.heroStyles(background: .mono, followsAppearance: true, iconFace: .apps) == [nil])
        #expect(CustomiseTileView.heroStyles(background: .colour, followsAppearance: false, iconFace: .apps) == [nil])
    }
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: TEST(CustomiseStyleTests), TEST(CustomiseHeroStylesTests)
Expected: compile errors `'TileStyle' is not a member type` / `extra argument 'iconFace' in call`.

- [ ] **Step 3: Implement the seams, the 18 strings' accessors, the view and the Detail sync**

In `DockTileDetailView`'s `.onChange(of: configManager.configurations)` sync block add `if editedConfig.iconFace != updatedConfig.iconFace { editedConfig.iconFace = updatedConfig.iconFace }` beside the `iconType` sync (without it, Tile Detail's hero and its Update button lag the face change made in Customise). `colourRowState` and `CustomiseColourRowStateTests` are unchanged — the view now HIDES the Colour card for `.emojiLocked` (via `inspectorSections`) instead of disabling it, and uses `.deepened` for the Colour caption as today.

- [ ] **Step 4: Make the window resizable (782…1200)**

Edit the sites listed under "Window" in Interfaces (file:line). Keep `WindowAccessor.customiseMinHeight = 700` (≥ the handoff's 680). Build, launch the dev build, drag the window's right edge: it resizes between 782 and 1200 pt and never narrower; at 782 the Customise pane shows the canvas at ≥ 250 pt beside the 260 pt inspector with no clipping.

- [ ] **Step 5: Sync the catalog and export the sheets**

Run: `python3 -I Scripts/l10n/l10n.py sync-keys`
Expected: `added 18 keys` (the list under "Strings"); the only en-US spelling warnings are for `label.tileColour` and `label.background.hint.emojiColours` → set their en-US values to "Tile Color" and "Emoji keep their own colors." textually in the catalog (anchored on the neighbouring key, the file's own `json.dumps(indent=2)` style), as the rule for en-US spellings says.
Run: `python3 -I Scripts/l10n/l10n.py export`
Expected: five sheets rewritten; `grep -c '| todo |' docs/l10n/de.md` → 18.

- [ ] **Step 6: Machine pass — fill the 18 `todo` rows in each of the five sheets, status `machine`**

Rules (docs/l10n/GLOSSARY.md): keep every placeholder exactly (`%1$lld` and `%2$lld` in `label.apps.shownValue` — reorder them if the language needs to, never renumber); "Tile Detail" must use the SAME rendering the sheet already uses for the Tile Detail pane name; "Light and Dark Mode" must match Apple's System Settings terms the glossary gives; "2 × 2" / "3 × 3" keep the multiplication sign; `label.style.appPreview` and `button.selectApps` must stay short (a 32 pt card label and a pill — German and Russian run ~30 % long); Smart Add identity names are untouched. Edit no other row.

```bash
for L in zh-Hans ja de ru fr; do python3 -I Scripts/l10n/l10n.py import $L; done
```
Expected: `<lang>: 18 entries updated` ×5; no lint output.

- [ ] **Step 7: Run the tests and what CI runs**

```bash
python3 -I -m unittest discover -s Scripts/l10n -p 'test_*.py'
python3 -I Scripts/l10n/l10n.py check
```
Expected: unittest `OK`; `review sheets consistent with the catalog`.
Run: TEST(CustomiseStyleTests), TEST(CustomiseHeroStylesTests), TEST(CustomiseColourRowStateTests), TEST(LocalizationCatalogTests), TEST(AppStringsTests), TEST(SystemSymbolNameTests), TEST(AppsFacePreviewTests)
Expected: `TEST SUCCEEDED` (CustomiseStyleTests: 4 passed; CustomiseHeroStylesTests: 4 passed).

- [ ] **Step 8: Hands-on**

Launch the dev build. Customise → two columns; the pill reads **‹ Select Apps** and returns to Tile Detail; the Style picker shows three live cards with the ring + checkmark on the current one; a NEW tile opens on **App Preview** with the Apps card ("0 of 0", "Fills the Tile", the no-apps note); after adding four apps in Tile Detail the card reads "4 of 4" / "2 × 2" and the hero shows the 2×2; a fifth app flips it to "3 × 3"; selecting **Symbol** restores the previous symbol, shows Background / Colour / Icon Size + Weight / picker; **Emoji** hides Icon Weight; Mono + Emoji hides the Colour card and the caption ends with "Emoji keep their own colours."; Mono + Symbol shows the stacked Light / Dark halves with the sun / moon captions; the icon-grid overlay appears on Symbol/Emoji heroes only; Update enables on Tile Detail after a style change. VoiceOver: each card reads its label and "selected"; the hero reads the face and count. German (`defaults write com.docktile.dev.app AppleLanguages "(de)"`, then `defaults delete …`): the card labels and the pill fit at 782 pt. Capture by window ID.

- [ ] **Step 9: Commit**

```bash
git add DockTile/Views/CustomiseTileView.swift DockTile/Views/DockTileDetailView.swift DockTile/Components/DockTileIconPreview.swift DockTile/Constants/AppStrings.swift DockTile/App/AppDelegate.swift DockTile/App/DockTileApp.swift DockTile/Views/DockTileConfigurationView.swift DockTile/Resources/Localizable.xcstrings docs/l10n DockTileTests/Unit/Views/CustomiseStyleTests.swift DockTileTests/Unit/Views/CustomiseHeroStylesTests.swift
```
```bash
git commit -m "feat(ui): Customise Tile two-column Style picker with App Preview; resizable 782–1200 window"
```

---

### Task 11: Analytics `face` parameter (+ GA4 registration before release)

**Files:**
- Modify: `DockTile/Views/DockTileDetailView.swift:590-595` (the `tileAddedToDock`/`tileUpdated` parameters move into a seam)
- Test: `DockTileTests/Unit/Managers/DockActionResolutionTests.swift` (append), `DockTileTests/Unit/Managers/AnalyticsServiceTests.swift` (run — `AnalyticsEvent` name safety; no new event is added)

**Interfaces:**
- Produces: `nonisolated static func DockTileDetailView.dockActionParameters(for config: DockTileConfiguration) -> [String: Any]` returning exactly `["layout": config.layoutMode.rawValue, "app_count": config.appItems.count, "show_in_app_switcher": config.showInAppSwitcher, "background": config.background.rawValue, "face": config.iconFace.rawValue]`; `performDockAction` logs `AnalyticsService.shared.log(wasInDock ? .tileUpdated : .tileAddedToDock, Self.dockActionParameters(for: configToSave))`.

- [ ] **Step 1: Write the failing test**

Append to `DockActionResolutionTests`:

```swift
    // MARK: - dockActionParameters

    @Test("Dock action analytics carry layout, app_count, show_in_app_switcher, background and face")
    func dockActionParameters() {
        var config = makeConfig()
        config.iconFace = .apps
        config.background = .mono
        config.layoutMode = .list
        config.showInAppSwitcher = true
        let params = DockTileDetailView.dockActionParameters(for: config)
        #expect(params["face"] as? String == "apps")
        #expect(params["background"] as? String == "mono")
        #expect(params["layout"] as? String == "list")
        #expect(params["app_count"] as? Int == 2)
        #expect(params["show_in_app_switcher"] as? Bool == true)
        #expect(Set(params.keys) == ["layout", "app_count", "show_in_app_switcher", "background", "face"])
        #expect(DockTileDetailView.dockActionParameters(for: makeConfig())["face"] as? String == "apps")   // memberwise default = new-tile default
        var glyph = makeConfig(); glyph.iconFace = .glyph
        #expect(DockTileDetailView.dockActionParameters(for: glyph)["face"] as? String == "glyph")
    }
```

- [ ] **Step 2: Run the test to verify it fails**

Run: TEST(DockActionResolutionTests)
Expected: compile error `has no member 'dockActionParameters'`.

- [ ] **Step 3: Implement the seam and call it from `performDockAction`**

- [ ] **Step 4: Run the tests to verify they pass**

Run: TEST(DockActionResolutionTests), TEST(AnalyticsEventNamingTests)
Expected: `TEST SUCCEEDED`.

- [ ] **Step 5: Commit**

```bash
git add DockTile/Views/DockTileDetailView.swift DockTileTests/Unit/Managers/DockActionResolutionTests.swift
```
```bash
git commit -m "feat(analytics): face parameter on tile_added_to_dock / tile_updated"
```

- [ ] **Step 6: Register the GA4 dimension BEFORE tagging the release (not a branch change — record it in Task 12's analytics.md line)**

```bash
TOKEN=$(gcloud auth print-access-token --account=ga4-fetch@dock-tile.iam.gserviceaccount.com --scopes=https://www.googleapis.com/auth/analytics.edit)
curl -s -X POST -H "Authorization: Bearer $TOKEN" -H "Content-Type: application/json" \
  https://analyticsadmin.googleapis.com/v1beta/properties/542196919/customDimensions \
  -d '{"parameterName":"face","displayName":"Tile face","description":"glyph or apps — which face the tile Dock icon shows","scope":"EVENT"}'
```
Expected: a JSON body echoing `"parameterName": "face"`. Registration is forward-only; events sent before it are invisible in GA4.

---

### Task 12: Rules, skill map and docs

**Files:**
- Modify: `.claude/rules/icon-system.md` (new section after "Tile background (Mono) and tone map")
- Modify: `.claude/rules/testing.md` (seam list)
- Modify: `.claude/skills/icon-rendering/SKILL.md` (seam table row + end-to-end flow sentence)
- Modify: `.claude/rules/architecture.md` (window width + Customise pane chrome, two lines)
- Modify: `.claude/rules/analytics.md` (the `face` parameter + registration line)
- Modify: `CLAUDE.md` (Icon System pointer line gains "Apps face")

- [ ] **Step 1: icon-system.md — `## Apps tile face`**

Cover, one bullet each: the model (`iconFace`, v10, separate field — why not an `IconType` case; TWO defaults: missing key → glyph, new tile → apps; glyph fields retained; glyph signatures unchanged, Apps appends face + first nine identities); the seam (`AppsFaceGrid`: 1 item = one centred 0.60 icon / 0.70 / 0.047 / 2-vs-3 columns at 4→5 / ÷0.805 app box / folders fitted / nine max / shadow 0.35·6·12 at 1024 gated by `minDetailSize` / grays 1.0→0.925 and 0.192→0.078 / Clear-Tinted desaturate); the four renderers and what each draws (compiled car: one composite layer on `system-light`/`system-dark` with explicit flat keys — Apple's `actool` would otherwise add specular/translucency/shadow and wash the icons; fallback and legacy bakes on the inset squircle; preview on the full frame); bake-time selection (installed only, tile order, symlinks resolved in `AppIconLoader`, zero → glyph face, non-verbose `tile` log for skipped items); staleness (re-bake on Update and version-bump migration only — an app's own icon redesign stays stale until then); the macOS 27 Tinted/Clear observation from Task 8 Step 3; the fixture `docs/icon-spike-fixtures/appgrid-systemfill.icon`; `TilePalette` not consulted.

- [ ] **Step 2: testing.md — add to the seam list**

`AppsFaceGrid.columns` / `.cells` / `.drawBox` / `.miniShadow` / `.fillGrays` / `.select` (Apps face: one centred 0.60 icon for 1 → 2×2 for 2–4 → 3×3 from 5, folders fitted to the cell, missing skipped, zero → glyph; guarded by `AppsFaceGridTests` + `AppsFaceRenderTests` + `AppsFacePreviewTests`), `IconDocumentBuilder.appsFaceIconJSON` (system fills + explicit flat keys; `IconDocumentBuilderTests`, compiled end-to-end in `IconCompilerTests`), `CustomiseTileView.heroStyles(…iconFace:)` / `.applyStyle` / `.inspectorSections` / `.appsSummary` / `TileStyle(face:iconType:)` (the Style picker and the Apps card; `CustomiseStyleTests`, English host), `DockTileDetailView.dockActionParameters`, `IconFace` tolerant decode + the two defaults (`IconFaceTests`).

- [ ] **Step 3: SKILL.md — seam table row**

`| AppsFaceGrid | Apps face geometry (block 0.70, gap 0.047, 2/3 columns, ÷0.805 app box, folders fitted), contact shadow, system gray pairs, item selection | AppsFaceGridTests, AppsFaceRenderTests |` and one sentence in "Declarative path": an Apps-face tile writes `appsFaceIconJSON` (system fills, flat keys) around one composite layer from `generateAppsLayerPNG`.

- [ ] **Step 4: analytics.md and CLAUDE.md**

architecture.md "Sidebar Selection & Empty State": the window is now resizable 782…1200 pt wide (was fixed 768) and Customise Tile is the one pane WITHOUT a title band — a floating ‹ Select Apps pill on its canvas returns to Tile Detail (design handoff `docs/design_handoff_customise_tile/README.md`); also state that NEW tiles default to App Preview while a config missing `iconFace` loads as glyph. analytics.md, in the "Reading the data back" bullet about registered params: `face` (`glyph`/`apps`) on `tile_added_to_dock` / `tile_updated`, registered <date> as "Tile face" (EVENT scope) — fill the date when Task 11 Step 6 runs. CLAUDE.md Icon System line: append "Apps face (grid of the tile's own apps on system glass)".

- [ ] **Step 5: Full verification**

Run: TEST(all); `python3 -I Scripts/l10n/l10n.py check`; `python3 -I -m unittest discover -s Scripts/l10n -p 'test_*.py'`
Expected: `TEST SUCCEEDED`, `review sheets consistent with the catalog`, `OK`. Then rebuild signed and `codesign --verify` before handing the dev build over.

- [ ] **Step 6: Commit, then gate**

```bash
git add .claude/rules/icon-system.md .claude/rules/testing.md .claude/skills/icon-rendering/SKILL.md .claude/rules/architecture.md .claude/rules/analytics.md CLAUDE.md
```
```bash
git commit -m "docs(rules): Apps tile face — seams, renderers, analytics param"
```

Run the `stage-gate` skill with `--dev` on the branch before pushing (CLAUDE.md "Gates"); on macos CI, confirm the `test-macos-15` leg's "Prove the suite" line includes the new `AppsFaceRenderTests` legacy cases.
