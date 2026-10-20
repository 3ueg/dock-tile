# Handoff: Customise Tile — three-way Style picker with the Apps face

> **Superseded in part (2026-10-20):** Customise Tile is no longer a drill-down screen with a canvas and a Select Apps pill. It is a native trailing inspector beside Tile Detail; see `docs/superpowers/specs/2026-10-20-customise-inspector-design.md` and `.claude/rules/architecture.md`. The Style cards, Colour and Apps card content below still apply.

Source: Claude Design project `191d3520-2496-46ac-a25a-58f39e0c5d6e`, files `Customise Tile.dc.html`
and `Tile Icon.dc.html` (copied here verbatim, 2026-10-19). `Tile Detail.dc.html` in that project
is today's Tile Detail unchanged (104 pt icon + **Customise** button, Tile Name / Show Tile /
Show in App Switcher, **In This Tile** popover editor with Grid/List and Add) — the two-step flow
stays: Tile Detail chooses **what** is in the tile, Customise chooses **how it looks**.

## About the design files
`Customise Tile.dc.html` is a **design reference in HTML** (a Design Component mounting the
project's macOS design-system web components). It shows intended look and behaviour; it is not
production code. Recreate it natively in SwiftUI/AppKit with the app's existing patterns and the
String Catalog. `Tile Icon.dc.html` is the tile renderer the mock imports — read it for the
per-style tile anatomy, not for pixel values (the real tile is `DockTileIconPreview`).

The mock's accent is teal (`--accents-teal`) and its glyphs are the design system's stand-ins:
use the **system accent** and real **SF Symbols**. The picker follows the mock's **6 columns**
(34 pt symbol circles / 36 pt emoji squares, 42 pt rows) — the 260 pt inspector cannot hold the
app's old 7 × 40 pt grid — while keeping the app's category captions and the pinned DockTile brand
category (ruling 2026-10-19).

## Screen layout (replaces today's single-column Customise)

Window min 782 × 680 (mock 860 × 720, resizable). Sidebar unchanged. The detail pane is **two
columns**:

- **Canvas** (left, flexible, min 250 pt, 12 pt radius, inset hairline). No title band: a floating
  glass pill at the top-left reads **‹ Select Apps** and returns to Tile Detail. The tile name is
  shown under the hero.
  - *Single hero* (Apps face, or Colour background): one 100 pt tile centred on a pastel gradient,
    name beneath.
  - *Light / Dark pair* (Symbol or Emoji on Mono): the canvas splits into two stacked halves —
    light gradient with an 88 pt tile and a sun "Light" caption, dark gradient with an 88 pt tile
    and a moon "Dark" caption.
  - The icon-grid overlay draws on Symbol and Emoji heroes only, never on the Apps face.
- **Inspector** (right, fixed 260 pt, scrolls, 18 pt between groups).

## Inspector, top: the Style picker (always visible)

Three equal white cards in a row (12 pt radius, hairline inset), each: a 32 pt live mini tile
rendered **in that style with the tile's current settings**, a 12 pt medium label, a 16 pt accent
checkmark badge top-right on the selected card, and a 2 pt accent ring.

| Card | Label |
|---|---|
| Apps | **App Preview** |
| Symbol | **Symbol** |
| Emoji | **Emoji** |

Selecting a card changes the face immediately (auto-save, as every Customise edit does).
**App Preview is the default for new tiles.**

## Inspector when App Preview is selected

Group header **Apps** (15 pt semibold, tertiary). One white card, two 46 pt rows:

| Row | Value |
|---|---|
| **Shown** | `min(count, 9) of count` — e.g. "4 of 4", "9 of 12" |
| **Arrangement** | "Fills the Tile" (1 app) · "2 × 2" (2–4) · "3 × 3" (5+) |

Caption under the card (12 pt secondary): the note, then one fixed sentence.
- note: "Shows the only app in this tile." (1) · "Shows all N apps, in tile order." (≤ 9) ·
  "Shows the first 9 of N apps, in tile order." (> 9)
- fixed: "A glass folder that follows Light and Dark Mode." (the mock's "looks the same in Light
  and Dark Mode" was superseded — see Decisions).

Nothing else: no Background, Colour, Size, Weight or picker. The face has no knobs.

## Inspector when Symbol or Emoji is selected

1. **Background** header; two white cards side by side, **Colour** and **Mono**, each with a 32 pt
   thumbnail (Colour: the tile in the current colour; Mono: a diagonal white/black split tile) and
   a label (semibold when selected), accent ring on the selected one. Caption beneath: Colour →
   "Filled with your colour"; Mono → "White in Light Mode, black in Dark Mode" (+ " Emoji keep
   their own colours." for Emoji).
2. **Colour** card — hidden for Mono + Emoji. Header reads **Tile Colour** (Colour) or **Symbol
   Colour** (Mono) with a right-aligned caption "Fills the tile" / "Tints the symbol". Seven 20 pt
   preset swatches (selected: white inner ring + white check) and the rainbow custom button with
   a "+".
3. White card: **Icon Size** row with the value and a stepper (10–19 symbols; the mock caps emoji
   at 14 — keep the app's 10–22 emoji range). Symbol only: **Icon Weight** row with a pop-up
   (Light · Regular · Medium · Semibold · Bold · Heavy).
4. Picker: header **Symbol** / **Emoji**; a white card with a search field ("Search Symbols" /
   "Search Emoji") and the grid. Symbol cell: 34 pt circle, selected = accent fill with a white
   glyph, cells drawn at the chosen weight. Emoji cell: 36 pt rounded square, selected = 20 %
   accent fill + 1.5 pt accent ring.

## Tile renderer notes (from `Tile Icon.dc.html`)

- Apps face: translucent white glass (`rgba(255,255,255,.84 → .52)` over a backdrop blur) —
  in the product this is the compiled icon's `system-light` fill, not a blur. Mini icons sit in a
  centred grid: 1 app → one icon at 0.60 of the tile; 2–4 → 2 columns; 5+ → 3 columns, first nine.
  The product keeps the spec's Apple-measured cell/gap/inset numbers (block 0.70, gap 0.047); the
  mock's 0.16/0.08 and 0.13/0.05 paddings are close and not a separate requirement.
- Symbol / Emoji: unchanged from today (gradient or Mono fill, glass hairline, grid overlay in
  the editor only).
- Sidebar row and every Style card use the same renderer at 30 / 32 pt.

## Decisions (Karthik, 2026-10-19)

1. **Apps face in Dark Mode follows Apple.** The compiled icon keeps `system-dark` for the dark
   appearance, like Apple's Apps icon and the iOS/iPadOS 26–27 folders; the Dock should look as
   native as those. The mock's caption is replaced by **"A glass folder that follows Light and
   Dark Mode."**
2. **Window.** Minimum width rises to 782 pt and the window becomes horizontally resizable
   (mock max 1200 × 900).
