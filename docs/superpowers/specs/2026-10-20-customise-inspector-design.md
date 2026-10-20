# Customise Tile as a trailing inspector — design

Date: 2026-10-20. Owner: Karthik (k97). Status: approved decisions below; spike result recorded in
"Spike" once run. Supersedes the screen layout in
`docs/design_handoff_customise_tile/README.md` ("Screen layout (replaces today's single-column
Customise)"); the inspector *contents* in that handoff (Style picker, Apps card, Background, Colour,
Icon Size / Weight, picker) are unchanged and still authoritative.

## Intent

Customise Tile stops being a separate screen that replaces Tile Detail and becomes a
**collapsible trailing inspector** beside it, so the user edits the tile's look while still seeing
the tile's name, switches and its apps. The hero tile in Tile Detail is the live preview.

Why now: the drill-down made every look change a two-step trip (Customise → ‹ Select Apps) and
hid the rest of the tile while editing. Apple's own pattern for "how this thing looks" beside
"what this thing is" is the inspector (Finder, Xcode, Icon Composer, Keynote).

## Goals

- One window state: Tile Detail always visible; the inspector opens and closes beside it.
- Edits in the inspector show on the Tile Detail hero **immediately** (same frame), not after a
  debounce.
- The inspector behaves like a macOS inspector: title band, toggle in the band, View menu item with
  ⌥⌘I, remembered across tiles and relaunch.
- Nothing about what the inspector *edits* changes: same Style picker, cards, captions, seams and
  tests.

## Non-goals

- No new preview surface anywhere (no mini hero in the inspector, no Light/Dark pair).
- No change to Tile Detail's hero, form rows or the popover editor beyond the Customise affordances.
- No inspector on Settings panes, About, or the empty state.
- No change to helper generation, icon rendering or the config schema.

## Anti-goals (would make this a failure even if it works)

- Two copies of the edited config side by side (a laggy hero, ping-pong saves, lost edits).
- The window squeezed so Tile Detail breaks at the minimum width.
- A permanent toolbar surface or a glass capsule around a title (the v2 chromeless band must
  survive, see architecture.md "Sidebar Selection & Empty State").
- Dropping the macOS 15 CI leg or any `#available` fallback.

## Decisions (Karthik, 2026-10-20)

1. **Native SwiftUI `.inspector(isPresented:)`**, not a hand-built column. Gated on the spike
   below: a failure of spike criteria 1 or 2 flips the plan to a hand-built trailing column inside
   Tile Detail's HStack; the rest of this document still applies.
2. **Window width.** *(Amended by Karthik 2026-10-20, round 4: the closed minimum is now
   **700 pt** and the open minimum **700 + 260 = 960 pt**; every 768 / 1028 below reads as
   700 / 960. Max stays 1200. Round 3's 728 / 988 broke: with the inspector open, the split view's
   minimum counts the inspector width twice (the SwiftUI hosting view's fitting size includes
   it, and the split adds it again — measured 228 + 274 + 2 × 260 = 1022 pt, where 274 pt is Tile
   Detail's content minimum, held by the hero row), so at 988 the inspector was clipped off the
   window's right edge and AppKit threw during SwiftUI's constraint update. As built in round 4:
   Tile Detail reports a 150 pt minimum (`.frame(minWidth:)`), the window minimums guarantee the
   room its content actually needs (420 pt at the widest sidebar), and a unit test pins
   sidebar max + detail min + 2 × inspector width + slack ≤ the open minimum.)* The closed minimum returns to **768 pt** (the pre-Customise value; 782 was
   raised only for the two-column Customise screen). With the inspector open the minimum is
   **768 + 260 = 1028 pt**; max stays 1200. **Amended by Karthik 2026-10-20 (during
   implementation): the window keeps its width when the inspector opens or closes, as Xcode,
   Pages and Keynote do — the detail column absorbs the 260 pt.** Opening grows the window only
   when it is narrower than 1028 (to exactly 1028, keeping the leading edge, shifted to fit the
   screen); closing never changes the frame, it only lowers the minimum back to 768. The earlier
   text ("grows by the inspector width, closing shrinks it back — Finder / Xcode behaviour") rested
   on a wrong claim about those apps, and shrinking in the same turn as the inspector collapsed
   crashed AppKit's constraint pass.
3. **Height.** The inspector **scrolls as a whole**; the symbol / emoji picker card has a **fixed
   grid height of 320 pt**. The window minimum height stays 500 pt; the 700 pt Customise special
   case in `WindowAccessor` is deleted. Iterate later if the picker feels short.
4. **Previews.** The Tile Detail hero (`TileFace`, 90 pt — 122 pt since Decision 11, live system style) is the only live
   preview. Mono's Light/Dark explanation is the Background chips' diagonal split plus the existing
   caption. The canvas hero, the Light/Dark pair, the icon-grid overlay and the ‹ Select Apps pill
   are removed.
5. **Open state.** One app-wide flag, persisted in `@AppStorage` (main-app domain), survives tile
   switches and relaunch. Selecting a Settings pane, About or the empty state hides the inspector;
   selecting a tile again restores it. Creating a tile never forces it open.
6. **Entry points.** (a) a `sidebar.trailing` toggle trailing Update in the Tile Detail band,
   tooltip Show Inspector / Hide Inspector; (b) the same toggle at the trailing edge of the
   inspector's own band, titled **Customise Tile**; (c) View menu **Show Inspector / Hide
   Inspector**, ⌥⌘I, enabled only while a tile is selected; (d) the **Customise** button and the
   hero icon tap **open** the inspector and never close it. *(Superseded by Decision 11: no
   Customise button; the hero toggles; toolbar label "Toggle Customise Tile".)*
7. **Pane.** Title "Customise Tile" (new key; `button.customise` stays for the button — removed
   with the button by Decision 11). Width
   **fixed 260 pt**, not user-resizable. The spike may add a side inset; the plan names the number.
8. **Spike pass criteria** (throwaway build on this Mac, macOS 27):
   1. The inspector band shows the title and the toggle, no Liquid Glass capsule around the title,
      no toolbar surface at rest.
   2. Tile Detail's band keeps its title leading and Delete / Update trailing with the inspector
      open and closed.
   3. The window grows and shrinks by the inspector width with the system animation; Reduce
      Motion drops the animation.
   4. The scroll-edge scrim fades in under the inspector band when its content scrolls.
   Fail 1 or 2 → hand-built column. Fail 3 or 4 → fix in the plan, approach unchanged. macOS 15 is
   verified only through the CI leg and `#available` fallbacks.
9. **Hero under Clear / Tinted (after the builder check).** While the inspector is OPEN the Tile
   Detail hero forces the canonical render (`.defaultStyle` in Light Mode, `.dark` in Dark Mode,
   via `DockTileIconPreview.forcing(_:)`), as the old canvas did, so a colour edit is always
   visible and the hero matches the inspector's canonical Background chips. Closed, it is today's
   live `TileFace`. This keeps icon-system.md's "Previews are canonical" rule for the editor.
10. **One inspector toggle, not two.** Closed: the toggle trails Update in the Tile Detail band.
    Open: the Tile Detail band shows Delete and Update only, and the toggle is the one beside
    "Customise Tile" in the inspector band. Same `sidebar.trailing` icon, one button that changes
    section (the system toggle's behaviour). Supersedes the sketch's two toggles and entry point
    6(a)/(b) as drawn; spike criterion 2 is read as "Delete / Update trail the detail column".
11. **Hands-on polish (Karthik, 2026-10-20, after the first build).** Supersedes 6(d) and 7's
    title size:
    - A 1 pt separator line runs the full window height between the detail column and the
      inspector (as in the sketch).
    - The **Customise** button under the hero is removed. The hero icon fills the hero row's height
      (the Tile Name card beside it: 3 × 40 pt rows + 2 × 1 pt dividers = 122 pt) and **toggles** the
      inspector both ways; tooltip and accessibility label **"Toggle Customiser"**.
    - The toolbar toggle (both bands) is labelled **"Toggle Customise Tile"** (tooltip and
      accessibility label). The View menu items stay Show / Hide Inspector.
    - The inspector's labels and content follow Tile Detail's: group headers like "In This Tile"
      (13 pt semibold, primary), captions like its hint (11 pt, tertiary), rows like its form rows
      (40 pt, 13 pt labels, 1 pt `quinaryLabel` dividers, the same card surface and insets).
    - The "Customise Tile" band title is one step smaller than the 16 pt page title: **14 pt
      semibold** (Claude's call on "a size smaller"; not 13 pt, which is the row-label size).

## Builder's calls (Claude, 2026-10-20; override freely)

- **State ownership.** `DockTileDetailView` applies `.inspector` itself and hands
  `CustomiseTileView` a `Binding<DockTileConfiguration>` to its `editedConfig`. The inspector keeps
  no copy, no debounce, no `persistEdits`, no `onDisappear` flush: Tile Detail's existing debounce
  and `preservingStoredVisibility` save path persist inspector edits. Tile Detail's
  `onChange(of: configManager.configurations)` icon-field sync ("may be changed in
  CustomiseTileView") is now dead and is removed; the `showInAppSwitcher` sync in that block stays.
  Consequence to accept: `contentSignature` now sees icon edits, so a hidden, unpinned tile's
  **Done** lights up after a colour change. That is correct.
- **Type and file names stay** (`CustomiseTileView.swift`, `CustomiseTileView`), so
  `CustomiseStyleTests`, `CustomiseColourRowStateTests`, `CustomiseHeroStylesTests` and the rule
  references keep working. `heroStyles` becomes unused by the view but stays as a tested seam only
  if something still reads it; otherwise the seam, its test and its rule line are removed together
  (the Background chips carry the Light/Dark explanation now).
- **Effective visibility** = stored flag AND a tile is selected — structural, not a function:
  `.inspector` lives inside `DockTileDetailView`, which only renders for a tile. The window
  minimum follows the STORED flag (read straight from `UserDefaults` by `windowWillResize` and
  the two places that re-assert `contentMinSize`); `AppDelegate.clampedWindowWidth(_:inspectorShown:)`
  is the one tested seam for 768 / 1028 / 1200. (Amended 2026-10-20 after the plan gate: an
  earlier version of this bullet said "effective value", which contradicted the settlement below.)
- **Resize owner (amended after the plan gate)**: `AppDelegate.resizeConfigurationWindow(
  forInspectorShown:)` — called only from `toggleInspector()` — moves the frame through the pure
  `windowFrame(forInspectorShown:from:visibleFrame:)` seam AND sets `contentMinSize` in the safe
  order (lower the minimum before shrinking; grow before raising it). `WindowAccessor` only
  re-asserts the minimum. The spike never ran with a raised minimum, so Task 3 verifies the order
  on the dev build.
- **String keys (amended)**: `title.customiseTile`, `menu.showInspector`, `menu.hideInspector`;
  the menu strings double as the toggle's tooltip and accessibility label.
- **Only the explicit toggle resizes the window; navigation never does** (builder-check
  settlement, matches Finder / Xcode). Selecting a Settings pane hides the inspector and the
  detail column absorbs the 260 pt; selecting a tile again shows it in the already-wide window.
  The window minimum follows the STORED flag (1028 whenever it is on, whatever pane is showing),
  so a tile selected after Settings always has room. The grow / shrink runs from the toggle
  handler itself (the four entry points funnel into one `toggleInspector()`), never from observing
  the flag flip, so a tile switch cannot re-fire it. Grow by 260 keeping the leading edge, clamped
  to the screen's `visibleFrame` and the 1200 max; shrink by 260 on close, clamped to 768 (no
  remembered pre-open width).
- **The View menu item is gated on the SIDEBAR selection** (a tile row), not
  `configManager.selectedConfigId`, which stays set while a Settings pane shows. It is disabled on
  Settings / About / empty state. Enablement and the action reach the `commands` block through a
  `FocusedValue` published by `DockTileConfigurationView` (`.focusedSceneValue`), so no new shared
  state object exists; the stored flag is one `@AppStorage` key.
- **Scrim.** The inspector's ScrollView gets `paneScrollEdgeEffect()` like every other banded pane.
- **Diagnostics only.** Toggle and open paths log `ui()` lines ("Tile Detail → Show Inspector",
  "View menu → Hide Inspector"). No new analytics event.
- **Localization.** New keys: `title.customiseTile`, `menu.showInspector`, `menu.hideInspector`
  (see "String keys (amended)" above). `button.selectApps`, `label.previewLight` and
  `label.previewDark` are removed. Run `sync-keys` → fix any en-US spelling warning → `export` → machine pass for the five
  languages → `import` → `check`, per localization-macos.md.
- **Docs.** architecture.md: replace "Customise Tile is the one pane WITHOUT a title band" with the
  inspector rules (effective visibility, width 768 / 1028, grow-on-open, scrolling inspector, no
  preview inside). testing.md: `clampedWindowWidth(_:inspectorShown:)` / `windowFrame(forInspectorShown:from:visibleFrame:)`. icon-system.md: the
  `heroStyles` mention. The handoff README gets a one-line "superseded by this spec" note at the top.

## Constraints

- Swift 6 strict concurrency; macOS 15 floor; `.inspector` is macOS 14+ so no gate is needed, but
  `ToolbarSpacer` and `.sharedBackgroundVisibility` stay `#available(macOS 26)`-gated as today.
- Visibility ownership is unchanged: `isVisibleInDock` is written only by `performDockAction`.
- The `+` gate, Smart Add sheet, delete confirmation and Dock-restart consent are untouched.
- Test host is the dev app; tests run on Default icon style.

## Spike

To be run before the plan is written, in a scratch SwiftUI app that reproduces the window chrome
(`NavigationSplitView`, `.toolbar(removing: .title)`, `.toolbarBackground(.hidden, for:
.windowToolbar)`, `titlebarAppearsTransparent`, `toolbarStyle = .unified`, the `PaneTitleBand`
pattern) and attaches `.inspector` with a banded ScrollView. Result recorded here.

Result (2026-10-20, macOS 27.0.1, Xcode 27.1, throwaway `swiftc` app driven by Accessibility,
captured by window ID): **native `.inspector` passes; two findings shape the implementation.**

| Criterion | Result | Evidence |
|---|---|---|
| 1 Inspector band | **Pass after one change.** With the inspector band's title placed `.navigation` (the `paneTitleItem` pattern) the title was pulled into the DETAIL band beside "Media", and the whole inspector `.toolbar` leaked into the main band while the inspector was closed. Placing the title `.automatic` and wrapping the inspector's toolbar content in `if isPresented { … }` fixed both: "Customise Tile" renders at the inspector column's leading edge, no capsule, no surface, and nothing shows while closed. | iteration 1 vs 2 captures; AX toolbar listing had two "Sidebar On The Trailing Side" buttons while closed in iteration 1, one in iteration 2 |
| 2 Detail band | **Pass (iteration 2).** Title leading; Delete / Update / toggle end 59 pt before the inspector column (AX x 453…581 in a 900 pt window with the inspector at 640). In iteration 1 they straddled the boundary (toggle at 671…711). | AX button frames |
| 3 Window growth | **SwiftUI does NOT grow the window** (frame 900×552 before and after, `contentMinSize` unchanged). Growing it ourselves works: at 1160 pt the detail took the extra 260 and both bands stayed in their sections. The system slide transition runs; its Reduce Motion behaviour was **not** verifiable in the spike (cannot flip the owner's setting) — hands-on check in the plan. | NSLog frames; AX frames after `set size` |
| 4 Scrim | **Pass.** `onScrollGeometryChange` + the material overlay fade in under the inspector band when the inspector scrolls. | scrolled capture |

| 5 Per-tile recreation (iteration 3, added after the builder check) | **Pass.** With the detail view keyed `.id(selection)` and `.inspector` INSIDE it (the real app's shape), switching tiles with the inspector open rebuilt the inspector content in 4 ms (appear → old disappear), the window frame did not change, the toolbar sections did not move, and six captures over the following second show no flash. `.inspector` stays inside `DockTileDetailView`; `editedConfig` is NOT hoisted. | NSLog appear/disappear + frames, `switchC-*` burst |

Also observed: the inspector content's `onAppear` fires at launch while the inspector is closed —
SwiftUI instantiates the content eagerly. `CustomiseTileView` does no work on appear today; keep it
that way (no `onAppear` side effects in the inspector).

Consequences carried into the plan:
- The inspector band is built with `ToolbarItem(placement: .automatic)` for the title (keeping
  `.sharedBackgroundVisibility(.hidden)` on macOS 26+), a `ToolbarSpacer(.flexible)` and a
  `.primaryAction` toggle, and the whole block is guarded on the presented flag. `PaneTitleBand`
  (which places `.navigation`) is NOT reused for the inspector; a sibling `InspectorTitleBand`
  modifier carries the `.automatic` variant.
- The inspector title's leading inset must be re-measured against the inspector's first card by
  AX frame, as `PaneTitleLabel.leadingAdjustment` was for the other panes (the spike's title sat
  about 40 pt left of the column edge with `.automatic` and a 12 pt pad).
- `WindowAccessor` owns the grow / shrink, as the builder's call above already assumed.

## What's left to the builder

- Exact inset and corner treatment of the inspector's cards on Tahoe (if the spike shows the
  column needs a side inset).
- Whether `heroStyles` keeps a caller.
- The order of the plan's tasks and the per-task tests, within the rules in testing.md.
