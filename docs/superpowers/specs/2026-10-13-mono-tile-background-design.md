# Mono Tile Background — Design

**Date:** 2026-10-13 · **Status:** approved in conversation, awaiting spec review
**Design source:** canvas "Mono Tile, Colour Glyph" (artboards *Mono background, dynamic*,
*Colour background*, *Emoji on a mono tile*, *Tone map: contrast-safe colour*).

## Intent

Let a tile be a plain **Mono** tile — white in Light Mode, near-black in Dark Mode — with the
tile's chosen colour moved onto the **symbol**. The same colour keeps one stored value and gains a
derived tone per role, so every tile (Colour or Mono) clears a fixed contrast floor between symbol
and background.

Decisions taken with Karthik (2026-10-13):

| Question | Decision |
|---|---|
| Background options | Two: **Colour** (today's look) and **Mono** (follows system appearance). No fixed white/black. |
| Tone-map Colour tiles too? | **Yes, all tiles.** Existing Colour tiles deepen on the next version-bump migration. |
| Contrast target | **3:1 always** (WCAG 2.2 SC 1.4.11 non-text). Increase Contrast does not change the bake. |
| Customise header | **In scope:** title band shows the tile name with a "Customise Tile" subtitle. |
| Mono glyph layers (plan gate) | **Spike first:** bake a Mono symbol `.icon` with 2 layers and with a 3rd white tinted-only layer, view both under Tinted/Clear; keep the 3rd only if 2 fails (the compiler builds the Tintable rendition on the light — white — gradient). |
| Sheen vs 3:1 (plan gate) | **3:1 is measured on the chosen colours, before decorative sheens.** macOS 26 Dock icons carry none; the macOS 15 bake and preview sheens are decoration. |
| Previews under a fixed icon style (plan gate) | **Always canonical:** the Background chips and the Mono Light/Dark hero force Default/Dark whatever the system icon style. |

## Research findings that shape the design

- No high-contrast app-icon appearance exists: Icon Composer authors default/dark/tinted only
  (clear derived); the Dock does not re-render on Increase Contrast. A baked icon therefore carries
  one fixed contrast target — hence "3:1 always".
- `.icon` per-appearance fills are `fill-specializations` entries `{appearance, value}` with the
  default entry carrying no `appearance` — the pipeline already emits exactly this shape
  (`IconDocumentBuilder.iconJSON`), so Mono needs no new document structure.
- Apple recommends its `system-light`/`system-dark` gradients over pure white/black for icon
  backgrounds (WWDC25-220). Not adopted: their values are unpublished, so contrast cannot be
  computed, the in-app preview cannot match, and macOS 15 cannot render them. Recorded as a
  future option.
- Hue-preserving lightness adjustment: bisect OKLCH lightness with hue fixed, reduce chroma to stay
  in sRGB gamut, and measure the real WCAG 2 ratio each step (Adobe Leonardo's approach). Mixing
  toward black/white in sRGB (the canvas prototype) muddies oranges and shifts hue.

## Model

`DockTileConfiguration.background: TileBackground` — schema **v9**.

```swift
enum TileBackground: String, Codable, CaseIterable { case colour, mono }
```

- Default `.colour` in `ConfigurationDefaults`; decoded with `decodeIfPresent`; an unknown raw
  value decodes to `.colour` (tolerant custom `init(from:)`, same pattern as `IconWeight`) so an
  older binary reading a newer config never fails the whole decode.
- Added to `CodingKeys` and to `DockTileDetailView.contentSignature` (it is a user edit: changing
  it must dirty the tile and enable Update).
- `tintColor` remains the only stored colour. Its role is derived, never stored twice.

## Tone map (pure seam)

`ToneMap` — `nonisolated`, value-in/value-out, no AppKit/SwiftUI types (plain sRGB triples).

- `contrastRatio(_:_:) -> Double` — WCAG 2 relative luminance (sRGB linearisation, threshold
  0.04045; 0.2126 R + 0.7152 G + 0.0722 B), `(L1 + 0.05) / (L2 + 0.05)`.
- `fit(_ colour:, direction: .darker | .lighter, target: Double, passes: (RGB) -> Bool) -> RGB`
  - If `colour` already passes → returned **unchanged** (byte-identical).
  - Else convert to OKLCH, hold H, bisect L toward 0 (`.darker`) or 1 (`.lighter`) for 20
    iterations; at each candidate reduce C until the sRGB conversion is in gamut; return the
    passing candidate closest to the original L.
  - The predicate form lets a caller test the pair the renderer actually draws (see below).
- `ToneMap.target = 3.0` — the single contrast constant.

## Palette (pure seam — single source of colour truth)

`TilePalette.resolve(tint:background:style:iconType:) -> (top: RGB, bottom: RGB, glyph: RGB)`,
`nonisolated`. `tint` is the tile's saturated base (`TintColor.colorBottom`; for a custom colour,
its hex). Constants: `lightTop #FFFFFF`, `lightBottom #EFEFF1`, `darkTop #2C2C2E`,
`darkBottom #1C1C1E` (the existing `darkNeutral*` values — Colour tiles' Dark appearance is
unchanged in background).

| Background | Style | Top / Bottom | Glyph |
|---|---|---|---|
| Colour | Default | `fillTop` = fit(tint, darker) so white clears 3:1 against it; `fillBottom` = `fillTop` with OKLCH L − 0.06 | white |
| Colour | Dark, symbol | darkTop / darkBottom | fit(tint, lighter) so the glyph's **shaded bottom** (glyph darkened by `IconDepthMetrics.glyphBottomDarken(style: .dark, iconType: .sfSymbol, nominalSize: 1024)` — the full-size value, the strongest darkening any rendition applies) clears 3:1 against `darkTop` |
| Colour | Dark, emoji | `darkenedForDarkMode` of the tint (unchanged) | unused |
| Mono | Default | lightTop / lightBottom | fit(tint, darker) against `lightBottom` |
| Mono | Dark (symbol and emoji) | darkTop / darkBottom | as Colour/Dark/symbol (emoji: unused) |
| Any | Clear / Tinted | unchanged greyscale values | unchanged |

Measuring pairs: each fit tests the weakest pair the renderer draws — the lightest point of a
light glyph against the lightest ground, the darkest against the darkest. Colour fill tests white
against `fillTop` (the gradient's lighter end).

This replaces `liftedForDarkGlyph(minLuminance: 0.55)` for Dark-appearance symbols: one rule
(3:1) instead of a luminance floor. A glyph that already clears 3:1 is unchanged.

Adapters (thin, no logic): `TintColor.colors(for:iconType:background:)` (SwiftUI `Color`) and
`.nsColors(for:iconType:background:)` (AppKit `NSColor`) convert `TilePalette` output. The
`background` parameter has **no default** — every call site must state it (compile-time guard
against a renderer silently drawing Colour for a Mono tile). `TintColor.badgeColors(for:tint:)`
routes its Default case through the same Colour fill rule; badges stay symbol-only.

## Renderers (each reads the palette — no colour logic of their own)

- **macOS 26 declarative** (`HelperBundleManager` → `IconDocumentBuilder.iconJSON`): passes
  light/dark/tinted fills and glyph colours from the palette with `config.background`. Mono: white
  gradient default fill, near-black `dark` specialization, glyph layers pre-coloured with the
  fitted tones. `IconDocumentBuilder`'s interface is unchanged; the car validation gate is
  unchanged.
- **Fallback `.icns`** (`IconGenerator.generateFallbackIcns`) and **glyph layer PNGs**
  (`generateGlyphLayerPNG`): take `background` and pass it to the palette.
- **macOS 15 legacy bake** (`IconGenerator.generateIcon`): Default and Dark variants follow the
  palette; Clear/Tinted unchanged. No change to detection/swap machinery.
- **Live preview** (`DockTileIconPreview`): takes `background`; therefore the sidebar tile icons,
  Smart Add cards and every other preview follow Mono with no extra work.
- **Emoji on Mono**: white / near-black tile; the emoji keeps its own colours and depth treatment.

**Rollout:** the release's version bump regenerates every pinned tile through the existing
migration batch (one Dock restart; `refreshDockEntry` re-seats every entry). No new migration code.
Existing Colour tiles visibly deepen — release notes must say so.

## Customise UI (`CustomiseTileView`)

Order: **Background · Colour · Icon Size / Icon Weight · Tile Icon** (picker unchanged).

- **Background row** — label "Background" + hint ("Filled with your colour" /
  "White in Light Mode, black in Dark Mode"); trailing radio group of two 44 pt chips with
  captions: **Colour** (tile in the current fill with white symbol) and **Mono** (diagonal split:
  light half with the Light glyph tone, dark half with the Dark tone). Selected chip: 2 pt accent
  ring with 2 pt gap. Each chip is a real button with `accessibilityLabel` ("Colour, filled with
  your colour" / "Mono, white in Light Mode and black in Dark Mode") and `.isSelected` trait.
  Changing it marks the config edited (same path as colour changes).
- **Colour row** — label "Colour" (Colour) / "Symbol Colour" (Mono); hint "Fills the tile",
  "Deepened slightly so the symbol stays clear" (Colour, when the fill moved), "Toned for Light and
  Dark" (Mono), "Emoji keep their own colours" (Mono + emoji). Swatches and custom picker
  unchanged. Mono + emoji: `.disabled` on the swatch controls only, row faded with `.opacity`,
  `.help` on the row (development.md tooltip rule).
- **Hero** — Colour: one preview as today. Mono: two previews side by side (Light and Dark
  palette), captioned "Light" with `sun.max` and "Dark" with `moon`.
- **Title band** — the pane's title is the tile's display name with a "Customise Tile" subtitle.
  `paneTitleItem`/`paneTitleBand` gain an optional `subtitle: String?`; every other pane passes
  nothing and renders exactly as today. The subtitle rides inside the same title `ToolbarItem`
  (one `VStack`), so the macOS-26 `.sharedBackgroundVisibility(.hidden)` treatment and the
  single-`.toolbar` spacer rule (architecture.md) are untouched.
- Strings via `AppStrings` (`Localizable.xcstrings`, inserted textually): en-GB/en-AU "Colour",
  en-US "Color" for every colour word.

## Analytics

`tile_added_to_dock` / `tile_updated` gain a `background` parameter (`colour`/`mono`) — adoption
measured at commit, not on every toggle. Must be registered as a GA4 custom definition to be
visible (analytics.md).

## Testing

| Guard | Fails when |
|---|---|
| `ToneMapTests` | any preset or sample custom colour misses 3:1 in any role; an already-passing colour is altered; OKLCH hue drifts > 3° (excluding greys); result is out of gamut |
| `TilePaletteTests` | Mono Default background is not `#FFFFFF/#EFEFF1`; Mono Dark is not the dark neutrals; Clear/Tinted change; Colour glyph is not white |
| `TilePaletteAdapterTests` | `colors` and `nsColors` disagree for any background × style × icon type |
| `ConfigurationModelsTests` (extend) | a pre-v9 config does not decode to `.colour`; an unknown raw value fails decode; `background` does not round-trip |
| `IconDocumentBuilderTests` (extend) | a Mono tile's `icon.json` default fill is not the light gradient or its `dark` specialization is not the dark neutrals |
| `DockActionResolutionTests` (extend) | changing `background` does not change `contentSignature` |
| `DarkGlyphTreatmentTests`, `BadgeColorMappingTests` (in `TintColorTests.swift`) | updated: the luminance-floor assertions become 3:1 assertions; badges mirror the palette |
| `AppStringsTests` | new keys missing or en-US/en-GB spelling wrong |

Manual: one bake each of symbol / emoji / brand glyph in Colour and Mono, viewed in the Dock under
Light, Dark, Tinted and Clear (macOS 26), plus the macOS 15 CI leg green.

## Out of scope

Reacting to Increase Contrast; Apple `system-light`/`system-dark` fills; a per-tile contrast
setting; changing the symbol picker or Icon Size/Weight controls.
