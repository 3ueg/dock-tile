# Apps Tile Face — Design

**Date:** 2026-10-18 · **Status:** draft, awaiting Karthik's approval after the builder check
**Reference:** iOS 26 folders (App Library's 2×2 of large minis for few apps, the Home Screen
folder's 3×3 for many, both on frosted glass) and
the macOS 27 `Apps` launcher icon (`/System/Applications/Apps.app`), whose compiled catalog is
the primary source for the material.

## Intent

A tile can show **the apps it contains** on its Dock face — a grid of mini app icons on the same
frosted glass tile iOS 26 uses for folders — instead of a symbol or emoji. A tile that holds apps
and *looks like* a stack of them needs no explanation: it is Apple's own folder metaphor, and the
system already draws the glass, depth and every appearance from the compiled icon.

Decisions taken with Karthik (2026-10-18):

| Question | Decision |
|---|---|
| What it is | One of three tile **styles** — **App Preview** (the Apps face), **Symbol**, **Emoji** — chosen per tile in Customise's Style picker. **App Preview is the default for new tiles** from this version on; existing tiles keep the face they have. |
| Grid | **Count-based, like iOS**: **1–4 → 2×2** (amended 2026-10-22, owner: one item sits in the top-left cell like an iOS folder; it was one centred 0.60 icon, "Fills the Tile"), **5 or more → 3×3** (first nine). Either grid fills from the top-left, row by row, and cells without an item stay empty glass (three apps = two on top, one bottom-left; six apps = two full rows of a 3×3). Adding a fifth app flips the face from four large minis to small ones, as an iOS folder does when it grows. |
| Material | Apple's `system-light` / `system-dark` icon fills — the same named gradients the `Apps` launcher icon uses. Not the tile's colour. |
| Mini icons | **Flat**, like iOS folder minis — no Liquid Glass lift, no translucency. (Apple's launcher lifts its chiclets with specular + shadow; we deliberately don't: translucency washes out real app icons, and the lift needs compiler work.) |
| Layers | One composite raster layer visible in every appearance (the emoji model). Per-app layers were measured and add nothing. |
| Fewer / more apps | Fewer: empty cells. More than nine: the first nine in tile order. Zero: the face falls back to the tile's symbol face so a new tile never shows a blank glass square. |
| Which apps | Tile order. The editor's drag-reorder already controls it; no per-slot picker. |
| Missing apps | Skipped — the next installed item takes the cell. A baked "not installed" marker would outlive the uninstall. |
| Folder items | **Included, in tile order** (my call, builder-check question 2 — Karthik may overturn). Drawn with the system folder icon `AppIconLoader` already returns, **fitted to the cell**, not through the ÷0.805 app-icon box (a Finder folder glyph carries no squircle margin). Presence judged by path, as `AppInstallChecker` already does for folders. |
| Staleness | Re-bake on **Update** and on the version-bump migration only. The app list joins `iconSignature` so an add/remove/reorder dirties the tile. An app redesigning its own icon stays stale until then — never a Dock restart to chase it. |

## Research findings that shape the design

Spike (throwaway, 2026-10-18, three rounds, scratch only — nothing from it is product code).
Rounds one and two measured a 2×2 grid with glass keys; rounds three and four compiled this
document's exact shape (one flat composite layer, system fills, flat keys) for the 3×3 and the
2×2 grids; round three's nine-app document is the one preserved as the fixture (see "Left to the
builder"):

- A `.icon` document whose only layer is a 1024² PNG of mini app icons compiles under both the
  vendored `docktile-actool` and Apple's `actool` to the required three appearance stacks, and
  macOS draws the glass squircle, shadow and highlight itself. No artefacts.
- `fill: "system-light"` (light + tinted) / `"system-dark"` (dark) renders **pixel-identical** to
  Apple's `Apps` launcher icon under both compilers (left-edge fill rgb 244,244,244 in both).
  The vendored compiler resolves these to fixed gray pairs — `system-light` = gray 1.0 → 0.925,
  `system-dark` = 0.192 → 0.078 (`Vendor/actool/src/icon_bundle.rs`, ~line 2193) — which is what
  the macOS 15 bake and the in-app preview must draw to match.
- Group `translucency` 0.5 (Apple's compiler) washes brand colours out: Safari's blue
  rgb(0,126,235) → (65,157,237), orange → salmon. Specular + neutral shadow with translucency off
  keeps colours exact. Under the vendored compiler every glass key is a no-op (it writes fixed
  lighting metadata and never emits specular/shadow-style/translucency), so flat is what ships
  either way — and flat is what iOS folders show.
- Per-app layers vs one composite: ≤1/255 difference under the vendored compiler, invisible under
  Apple's. `blur-material` is invisible in a static icon.
- **No route yields another app's icon in the other icon style**: `NSWorkspace.icon(forFile:)`,
  the bundle's catalog image, the `.icns` file, and a real GUI process under `darkAqua` all
  returned byte-identical renders. IconServices keys on the system-wide icon style only. So the
  layer is baked in whatever style the user is on at bake time (one layer, every appearance).
- Both compilers name renditions after the **document stem** and ignore `--app-icon`; the product
  already names its document `AppIcon`. Do not rename it.
- `/Applications/Safari.app` is a symlink on macOS 27; `NSWorkspace.icon(forFile:)` on the
  symlink returns the icon with an alias-arrow badge. Resolve symlinks before fetching.
- Round three rendered the final shape at real Dock sizes. At 64 px all nine minis identify by
  colour and shape (each ~13 px); at 48 px (~10 px each) the tile reads as "a folder of apps" and
  the strongly coloured minis still identify, while light ones (Calendar, Notes) collapse to a
  white square with a coloured stripe. Three apps read as a deliberate row; one app is a mostly
  empty glass tile with a single top-left chiclet — intentional, but close to blank at 48 px.
  Round four rendered the 2×2 grid the same way: at 48 px each mini is ~16 px and all four
  identify individually (Calendar vs Notes by header colour and texture, Safari's needle, Claude's
  starburst) — the 2×2 at 48 px reads about as well as the 3×3 at 64 px, which is what the
  count-based rule buys. Two apps read as two chips in the upper half of a glass tile; five apps
  on a 3×3 read as an L-shaped, deliberately partial folder. No clipping: the 2-column draw box
  (334 px) overhangs its 269 px cell but stays well inside the 824 px shape.
- Geometry measured from the iOS 26 screenshot and the App Library reference agree on one
  formula: the icon block is **0.70** of the tile shape, gap **0.047**; three columns give a
  **0.202** mini icon (iOS folder), two would give 0.326 (App Library). Inset 0.15 per side.

**Decided (Karthik, 2026-10-19): Apps face in Dark Mode follows Apple.** The compiled icon
keeps `system-dark` for the dark appearance, as Apple's own Apps icon and the iOS/iPadOS 26–27
folders do — the Dock should look as native as those. The design caption "looks the same in Light
and Dark Mode" is wrong and ships as **"A glass folder that follows Light and Dark Mode."**

Not verified yet: how the system's **Tinted** and **Clear** passes treat nine opaque mini
squircles (they derive relief from the layer's alpha — the emoji precedent says four blank glass
squares). Karthik can view the spike's stub bundles in Finder under each style; the answer does
not change the design, only whether we document it as a known look.

## Goals

- A tile whose Dock face shows its first nine apps on iOS-folder glass, in Light and Dark.
- Zero drift between the Dock icon, the fallback `.icns`, the macOS 15 bake and the in-app preview
  (the project's standing invariant — one geometry seam, one material seam).
- No new permission surface, nothing transmitted, no Dock restart beyond the existing Update path.

## Non-goals (v1)

- Smart Add suggestion CARDS showing this face (they keep their category identity). The tile a card creates is a new tile, so it opens on App Preview like every new tile (Karthik: "by default it will be the app grid preview … from the new versions moving forward").
- Lifted chiclets (specular/shadow via the compiler). Recorded as a follow-up option.
- Watching app bundles for icon changes. Reacting to an app's own icon redesign is out.
- Wallpaper-tinted glass. iOS folders sample the wallpaper; a compiled Dock icon cannot.
- A "+N" count badge.

## Anti-goals

- A face that hides the "app is gone" state (missing apps are skipped, never drawn stale).
- A face that depends on which icon style the user had at bake time more than it must (one
  layer, system fills — the fill adapts even though the minis cannot).
- A second scale/weight/colour control set for this face. Those controls **hide** for it.

## Model

A **separate optional field**, not a new `IconType` case: `IconType` decodes strictly, so a config
carrying an unknown case would fail to load in an older build; an optional field with tolerant
decode (the `TileBackground` / `IconWeight` pattern) survives. **Two different defaults, on
purpose**: a config *missing* the key decodes to the glyph face (every existing tile is a symbol
or emoji and must not change on upgrade), while `ConfigurationDefaults` for a *new* tile is the
Apps face. A test pins both.

- Bump the schema version by one; `ConfigurationDefaults` default; `CodingKeys`;
  `decodeIfPresent`; unknown raw value → default.
- `iconSignature` gains the face and, when the face is Apps, the ordered bundle identifiers (and
  folder paths) of the first nine items — so `TileFace.showsSystemIcon` sees a list change.
  (`contentSignature` already hashes `appItems` ids, so Update dirtying needs nothing new.) The
  builder picks the exact token.
- `tintColor`, `background`, `iconType`, `iconValue`, `iconScale`, `iconWeight` are **retained**
  while the face is Apps (switching back restores the previous look).
- Naming is the builder's; note the existing `TileFace` view type to avoid a clash.

## Geometry seam (pure, tested)

One `nonisolated static` value-in/value-out seam (name to the builder; lives beside
`IconDepthMetrics`), consumed by **all four** renderers:

- Constants: block 0.80 of the shape, gap 0.035 (revised 2026-10-19 from the measured 0.70 / 0.047,
  which read small and crowded in the Dock); columns = 2 when `count ≤ 4`, else 3 → cell
  0.3825 (2 columns) or 0.243 (3 columns) of the shape; the shape is `1 − 2 × IconDepthMetrics.contentInsetRatio` of the canvas in FLAT bakes (fallback
  `.icns`, legacy bake), and the full canvas in the compiled `.icon` layer (the system adds the
  icon-grid margin to an Icon Composer document itself — corrected 2026-10-19, the first build
  inset twice) and the full frame in UI slots (`DockTileIconPreview` does not inset —
  existing rule).
- `columns(count:)` → 1, 2 or 3; `cells(count:)` → one centred rect of 0.60 of the shape, or up
  to four or nine unit-space rects, row-major from the top-left on that grid; `count` clamps at
  9; 0 → empty (the caller falls back to the symbol face).
- A mini icon's **draw box** is its visible cell ÷ 0.805, because third-party icons carry Apple's
  own transparent margin; the visible squircle must land on the 0.202 cell.
- Tests: 1 → one centred cell of 0.60; 2 → top row of a 2×2; 3 → three cells of a 2×2 (two on
  top, one bottom-left); 4 → full 2×2; 5 → 3×3 with five filled; 9 → full 3×3; 10 → nine; cells
  never overlap, the block spans exactly 0.80 on both grids, the 1→2 and 4→5 column flips and the
  row-major order are pinned.

## Renderers

All four draw the same thing from the same two seams:

| Renderer | Change |
|---|---|
| `IconGenerator.generateGlyphLayerPNG` (macOS 26 layer) | Apps branch: clear canvas, draw each mini icon (via `AppIconLoader`, symlinks resolved, `NSImage.size` = box, `.high` interpolation) into its cell, plus a subtle contact shadow (my call — light app icons such as Notes vanish on near-white glass without it; the spike render with a shadow reads well). No squircle, no sheen. |
| `IconDocumentBuilder` | Apps face emits `fill: "system-light"` with specializations `{dark: "system-dark", tinted: "system-light"}` instead of the P3 gradient; one layer, visible everywhere. Write the flat look **explicitly** — layer `"glass": false`, group `"specular": false`, `"translucency": {"enabled": false, "value": 0}`, `"shadow": {"kind": "none", "opacity": 0}` — never by omission: Apple's `actool` fills omitted keys with Icon Composer's defaults (specular on, translucency 0.3, shadow 0.5), which washes real app icons, while the vendored compiler ignores them. Explicit keys mean the document says the same thing under both. |
| `IconGenerator.generateFallbackIcns` + legacy `generateIcon` (macOS 15) | Apps branch: inset squircle filled with the gray pair (light 1.0→0.925; the legacy Dark variant 0.192→0.078), minis on top. Clear/Tinted legacy variants: minis desaturated to keep that path's grayscale promise. |
| `DockTileIconPreview` | Apps mode drawing the same grid on the same gray pair. Light/Dark keys on `IconStyle.forDisplay(raw:colorScheme:)` exactly as the Mono face does (never raw `colorScheme`). Mini icons come from `TileIconRasterCache`, never the IconServices `NSImage` (icon-system rule). Customise hero, sidebar `TileFace`, Tile Detail hero and the never-built previews all route through it. |

`TilePalette`/`ToneMap` are **not** consulted for this face (no glyph, no 3:1 promise to keep).
`helperIconsComplete` is unchanged (same files on disk).

## Customise Tile

**Source of truth: the design handoff**
[docs/design_handoff_customise_tile/README.md](../../design_handoff_customise_tile/README.md)
(Karthik's Claude Design project, copied verbatim beside it). In brief:

- Customise becomes **two columns**: a canvas (single hero, or a stacked Light/Dark pair for
  Symbol/Emoji on Mono) with a floating **‹ Select Apps** pill back to Tile Detail, and a fixed
  260 pt scrolling inspector. Tile Detail is unchanged.
- The inspector opens with the **Style picker**: three cards — **App Preview · Symbol · Emoji** —
  each a live 32 pt mini tile in that style with the tile's current settings, accent ring and
  checkmark on the selected one. Selecting changes the face at once (auto-save).
- **App Preview** shows one **Apps** card — **Shown** "N of M" and **Arrangement** "Fills the
  Tile" / "2 × 2" / "3 × 3" — plus a caption, and nothing else. No knobs.
- **Symbol / Emoji** show Background (Colour / Mono thumbnail cards), the Colour card (Tile Colour
  / Symbol Colour; hidden for Mono + Emoji), Icon Size (+ Icon Weight for Symbol) and the
  categorised picker with search. Same controls as today, re-housed.
- New strings (card labels, "Shown", "Arrangement", "Fills the Tile", the captions, "Select
  Apps"): the builder runs `l10n.py sync-keys` then `export` and the machine pass for
  zh-Hans/ja/de/ru/fr via `import`, as the 2026-10-17 localization cycle did, so
  `LocalizationCatalogTests` stays green; native reviewers follow later through `docs/l10n/`.
- VoiceOver: each Style card is a button labelled with its style; the hero is labelled with the
  face and, for App Preview, the app count.
- **Window (decided 2026-10-19)**: the minimum width rises to 782 pt to fit two columns, and the
  window becomes horizontally **resizable** (today it is fixed at 768). The mock caps at
  1200 × 900; the builder picks the maximum.

## Data flow at bake time

`HelperBundleManager.installHelper` already copies the bundle, strips icons, and calls the
declarative or legacy path from `config`; the only new input is the tile's `appItems`, which the
config already carries. Resolve each item through the same rule `AppLauncher`/`AppIconLoader`
use (`lastKnownPath` first), skip items whose status is missing (`AppInstallChecker`), resolve
symlinks, take the first nine.

## Analytics & diagnostics

- `tile_added_to_dock` / `tile_updated` gain a `face` parameter (`glyph` / `apps`). **Register the
  GA4 custom dimension before the release ships** (registration is forward-only — analytics rule).
- Non-verbose `tile` log line when a bake skips missing items ("Apps face: skipped 2 missing").

## Constraints

- macOS 15 floor stays; the legacy bake must draw this face too (CI's macOS 15 leg runs it).
- Never add a Dock restart; never touch the Dock plist for this.
- The bake reads only local icons; nothing leaves the device.
- Follow the icon-rendering skill's invariants (explicit-pixel bitmaps, no outer tile shadow,
  scratch in temp, re-seat the Dock entry after regenerate — all already in place).

## Left to the builder

- Field and seam names; where the Customise note copy lives.
- Exact contact-shadow magnitude (start from the spike: black α 0.35, blur 12 px, offset −6 px at
  1024; gate below `minDetailSize` like every other depth effect).
- Whether to resolve symlinks inside `AppIconLoader` (fixes any symlinked app in popovers too) or
  only at the bake. Prefer the loader if the change is one line.
- Test placement: geometry seam tests; an `IconDocumentBuilder` test pinning the system fills and
  the absence of glass keys for the Apps face; a `generateGlyphLayerPNG` render test that a
  one-app tile paints only the top-left cell (pixel scan, like `EmojiInkFitRenderTests`).
- **First task of the plan, before product code:** copy round three's `AppIcon.icon` document
  (the exact shape above) into `docs/icon-spike-fixtures/appgrid-systemfill.icon` with a README
  note, recompile it with the vendored compiler, check `assetutil --info` for the three stacks and
  the `system-light`/`system-dark` fills, and pin nothing — view the stub bundle in Finder. The
  scratchpad that holds the spike is session-scoped and vanishes; the fixture is the surviving
  reference, as `devtile-fix.icon` is for gradient fills.
