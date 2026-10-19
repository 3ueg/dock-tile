# App Grid follows each icon style — Implementation Plan

**Goal:** An App Grid tile's minis look like each app's own icon in every macOS 26+ icon style
(Default, Dark, Clear Light/Dark, Tinted Light/Dark), in the Dock and in the app.

**Spec:** this plan (no separate spec). Evidence lives in the session scratchpad and is summarised
under "Findings".

## Findings (measured 2026-10-19, macOS 27)

1. **The bug.** The compiled App Grid `.icon` has ONE grid layer, baked from
   `AppIconLoader.icon(for:)` (an `NSWorkspace` icon, rendered in whatever style is active at
   Update time), and shared by the light, dark and tinted appearances. Under Clear Dark the system
   runs its clear filter over that flat colour picture, so VS Code's white plate becomes a bright
   square, while the Dock draws VS Code's own Clear Dark icon (dark plate). Dark has the same
   flaw (dark appearance reuses colour minis).
2. **Which slot feeds which style.** Apple's `ictool` (Icon Composer) on a probe `.icon` with a
   distinct layer per appearance: Default → light layer, Dark → dark layer, Clear Light, Clear
   Dark, Tinted Light and Tinted Dark → the TINTED layer, brightness-remapped by the system.
3. **Our compiler honours a tinted-only layer.** `docktile-actool` on the probe: Aqua stack shows
   only L, DarkAqua only D, Tintable only T (`LayerOpacity` 1/0).
4. **Public API cannot pick a style.** `NSWorkspace.icon(forFile:)` returns the CURRENT system
   style only; under Clear Dark, drawing it under `.aqua` and `.darkAqua` both gave Clear Dark.
5. **Private IconServices can.** `ISBundleIcon initWithBundleURL:` + `ISImageDescriptor
   initWithSize:scale:` with `appearance` (0 light, 1 dark) and `appearanceVariant` (0 normal,
   2 tinted — needs `tintColor`, an `IFColor` — 3 clear), `prepareImageForDescriptor:` then
   `CGImageForImageDescriptor:` returns VS Code's Default, Dark, Clear Light and Clear Dark
   renders on demand, matching the Dock. Without `prepareImageForDescriptor:` uncached variants
   come back as a dashed placeholder.
6. **Best tinted-slot content.** ictool comparison of three candidate tinted grids against the
   apps' own renders: Clear DARK renders (appearance 1, variant 3) match Clear Dark and Tinted Dark
   closely and stay reasonable in Clear Light / Tinted Light; Clear Light renders match the light
   styles but are too pale in the dark ones; colour renders (today) give the bright-plate bug in
   all four.
7. **Folders do not vary.** `ISCustomIcon initWithURL:` and `ISTypeIcon` give the same blue
   folder for every descriptor, so folders get one render in every slot.
8. **In-app.** The sidebar / Tile Detail hero already draw minis via `NSWorkspace` (follows the live
   style), but the tile body is our own stand-in. `TileFace` already shows macOS's render of the
   helper under Tinted; Clear has the same problem (our light-grey stand-in vs the system's glass).

## Plan-gate rulings (2026-10-19)

The plan gate returned "Needs answers". Answered from evidence and the request ("fix all of it"):

1. **Surface.** The wrong VS Code mini was in the DOCK tile (Dock capture by window ID: a bright
   white VS Code square inside Dev under Clear Dark). The in-app minis already follow the live style
   through `NSWorkspace` + `TileIconRasterCache` (its token carries the stored style value, so Clear
   Light and Clear Dark differ); a later in-app capture showed Clear Dark minis. The remaining
   in-app mismatch is the tile BODY (our stand-in vs the system glass) — Task 3, after Update,
   exactly as Tinted works today. The Customise hero stays canonical Light/Dark (existing rule
   "Previews are canonical").
2. **macOS 26.** Not verifiable locally (no macOS 26 host). The renderer test FAILS (does not skip)
   on macOS 26+ when a render is nil: the macos-26 CI leg is the check, and production keeps the
   public-loader fallback either way. macOS 15 skips (no IconServices variants, no declarative path).
3. **Task 3 covers every face**, not only App Grid: under Clear our own drawing is a light-grey
   stand-in for glyph tiles too — the same class of mismatch as issue #22, and the request was to
   match what the OS shows. The helper-folder scan runs only under Clear/Tinted.

Measured for the other findings (macOS 27): TextEdit mean luminance Default 0.938 vs Clear Dark 0.213;
the IconServices render's opaque extent equals NSWorkspace's (206 of 256 px, the icon-grid margin),
so `AppsFaceGrid.drawBox`'s ÷0.805 still holds; 9 apps × 3 styles at 310 px render in 77 ms.

## Global Constraints

- macOS 26+ declarative path only. The macOS 15 legacy bake and the fallback `.icns` keep the
  single colour grid (macOS 15 has no Clear/Tinted; the fallback `.icns` is the light composition).
- Private API is resolved at RUNTIME only and every call is guarded: classes via `NSClassFromString`;
  every selector via `responds(to:)` BEFORE use — including the setters `setAppearance:` /
  `setAppearanceVariant:` (never `setValue(_:forKey:)` on an unchecked key: an ObjC exception is
  uncatchable in Swift). Non-object signatures go through `method(for:)` + `unsafeBitCast` to
  `@convention(c)`: `initWithSize:scale:` `(AnyObject, Selector, CGSize, CGFloat) -> AnyObject`,
  setters `(AnyObject, Selector, Int) -> Void`, `CGImageForImageDescriptor:`
  `(AnyObject, Selector, AnyObject) -> Unmanaged<CGImage>?`. Nothing links IconServices. Any missing class/selector/key, or a nil image → fall back to
  today's `AppIconLoader.icon(for:)` image for that mini. Never crash, never skip a mini because
  of the fallback.
- One rendering seam for the bake; no change to `TileIconRasterCache` / popovers.
- Swift 6, `@MainActor` where the callers already are. New code goes into EXISTING app-target files
  (no pbxproj edits). Tests are new files under `DockTileTests/` (auto-join).
- Logs: one non-verbose `tile` line when the bake falls back for a reason other than "folder".

## Review Focus

1. A future macOS renames/removes the private classes → the bake must still produce a tile (all
   three slots = the public render) and log the fallback once per bake.
2. A mini whose app is uninstalled mid-bake → already skipped by `AppsFaceGrid.select`; the
   renderer must not resurrect it.
3. Folder items → same image in all three slots, from the public loader (no blank document icon —
   `ISBundleIcon` on a folder returns a generic DOCUMENT icon, seen in the probe).
4. Bake while the system is in Clear Dark → the LIGHT slot must still be the Default render, not
   the Clear render (the private descriptor pins the style; the public loader would not).
5. Existing glyph `.icon` documents must be byte-identical (the tinted hidden-specialization is
   Apps-only).

---

### Task 1: Style renderer seam (`AppIconStyleRenderer`)

**Files:** Modify `DockTile/Utilities/AppIconLoader.swift` (append). Test:
`DockTileTests/Unit/Utilities/AppIconStyleRendererTests.swift` (new).

**Produces:**
- `enum AppIconRenderStyle: CaseIterable { case standard, dark, clearDark }`
- `AppIconStyleRenderer.descriptorValues(for:) -> (appearance: Int, appearanceVariant: Int)`
  — pure, `nonisolated static`: standard (0,0), dark (1,0), clearDark (1,3).
- `@MainActor AppIconStyleRenderer.render(appAt url: URL, pixelSize: Int, style:) -> CGImage?`
  — private IconServices path above; nil on any missing piece.

- [ ] Test `descriptorValues` pins exactly (0,0), (1,0), (1,3).
- [ ] Test (macOS 26+, `#available`-gated, system app present on every host:
      `/System/Applications/TextEdit.app`): `.standard` and `.clearDark` at 64 px are both
      non-nil, 64×64, and the standard render's mean luminance exceeds the Clear Dark one by
      ≥ 0.3 (measured 0.938 vs 0.213). Fails if the variant is ignored or a placeholder comes back.
- [ ] Test: the IconServices standard render's opaque extent through the centre row equals the
      `NSWorkspace` render's within 2 px at 256 px (both carry the icon-grid margin).
- [ ] Implement; run; commit.

### Task 2: Bake three grids into the Apps `.icon`

**Files:** `DockTile/Utilities/DeclarativeIconPipeline.swift`, `DockTile/Managers/HelperBundleManager.swift`.
Tests: `IconDocumentBuilderTests`, `IconCompilerTests` (existing).

**Produces:**
- `IconDocumentBuilder.appsFaceImageNames: [AppIconRenderStyle: String]` =
  standard `grid.png` (unchanged name), dark `grid-dark.png`, clearDark `grid-tinted.png`.
- `appsFaceIconJSON()` → one group, three layers built by an Apps-only helper (NOT `LayerSpec` /
  `layerDict`'s two-case `Exclusive`, so glyph documents cannot change) (`glass: false`, flat keys
  unchanged), hidden:
  standard `[{false}, {dark: true}, {tinted: true}]`; dark `[{true}, {dark: false}]`;
  tinted `[{true}, {tinted: false}]`.
- `HelperBundleManager.appsFaceMinis(for:style:)` — per selected item: folder → public loader;
  app → `AppIconStyleRenderer.render(appAt: resolvedURL, pixelSize: 768, style:)` wrapped as
  `NSImage(cgImage:size:)`, else the public loader (and count the fallback). Pixel size: the mini's
  1024-canvas draw box (`AppsFaceGrid.drawBox` for the item count, rounded up) — no 768 constant. The existing
  `appsFaceMinis(for:)` stays for the fallback `.icns` / legacy bake (= public loader, unchanged).

- [ ] `IconDocumentBuilderTests`: the Apps document has exactly the three layers with exactly
      those hidden-specializations; and a glyph document's serialized JSON contains no `tinted`
      hidden-specialization (pin against the change leaking into glyph tiles).
- [ ] `IconCompilerTests`: compiling the Apps document with three distinct PNGs yields an Aqua
      stack showing only `grid`, DarkAqua only `grid-dark`, Tintable only `grid-tinted`
      (`LayerOpacity` from `assetutil --info`).
- [ ] Wire the install path; run the suite; commit.

### Task 3: In-app tile face under Clear

**Files:** `DockTile/Components/DockTileIconPreview.swift` (`TileFace`). Test: `TileFaceTests`.

- [ ] `showsSystemIcon` is true for `.tinted` AND `.clear` when signatures match; false for
      `.defaultStyle` / `.dark`; false on mismatch. Update the doc comment and the guard in
      `systemIcon`.
- [ ] Commit.

### Task 4: Docs + hands-on

- [ ] icon-system.md "Apps tile face": three grids, slot mapping (finding 2), private renderer
      and fallback, folders, the Clear Dark choice for the tinted slot and its known limit
      (Clear Light / Tinted Light are approximations). testing.md seam list.
- [ ] Rebuild signed, Update Dev + Media, capture the Dock by window ID under the current Clear
      Dark; the owner checks the other styles by eye.

## Deviations during build

- The fallback `.icns` uses the Default (standard) IconServices renders, not the public loader:
  a bake during Clear would otherwise freeze a Clear fallback (Review Focus 4 applied to it too).
  `appsFaceMinis(for:)` was replaced by `appsFaceEntries(for:)` + `styledAppsFaceMinis`.
- The renderer returns a square image of AT LEAST the requested size (IconServices may hand back a
  2× backing); the bake draws into a box, so only the margin ratio matters.

## Known limits (accepted)

- Clear Light and Tinted Light/Dark derive from the Clear Dark grid via the system's remap — close,
  not exact (one tinted slot for four styles).
- Minis still refresh only on Update / version-bump migration.
- Private API: can break on a future macOS; the fallback keeps today's look.
