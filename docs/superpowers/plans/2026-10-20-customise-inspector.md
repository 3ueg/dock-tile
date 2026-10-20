# Customise Tile Inspector Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the Customise Tile drill-down screen with a native, collapsible trailing inspector beside Tile Detail, editing the same `editedConfig` so the Tile Detail hero previews every change live.

**Architecture:** `DockTileDetailView` applies SwiftUI `.inspector(isPresented:)` itself and hands `CustomiseTileView` a `Binding` to its own `editedConfig`; Tile Detail's existing debounce persists inspector edits, so there is one copy and one save path. The open flag is one `@AppStorage` key; effective visibility = flag AND a tile row selected. Only the explicit toggle resizes the window (grow/shrink by 260 pt from the toggle handler); the window minimum follows the stored flag. Spike-verified on macOS 27 (spec "Spike").

**Tech Stack:** Swift 6 strict concurrency, SwiftUI `.inspector` (macOS 14+), AppKit `NSWindow` sizing, Swift Testing, `Scripts/l10n/l10n.py`.

**Spec:** `docs/superpowers/specs/2026-10-20-customise-inspector-design.md`

**Where this plan overrides the spec's builder's calls** (the spec is amended to match; architecture.md is written from this version): the grow/shrink and the minimum are set by `AppDelegate.resizeConfigurationWindow`, not `WindowAccessor` (which only re-asserts the minimum); the width clamp reads the STORED flag, never an "effective" value; the string keys are `title.customiseTile`, `menu.showInspector`, `menu.hideInspector` (the menu strings double as the toggle's tooltip and accessibility label), not `navigation.*`/`tooltip.*`.

## Global Constraints

- macOS 15 floor; `ToolbarSpacer` and `.sharedBackgroundVisibility(.hidden)` stay `#available(macOS 26.0, *)`-gated with the existing fallbacks.
- Window width: closed minimum **768**, open minimum **768 + 260 = 1028**, maximum **1200**. Inspector width **260**, not user-resizable. Window minimum height stays **500**; the 700 pt Customise special case is deleted.
- Picker grid fixed height **320**. The inspector scrolls as a whole and carries `paneScrollEdgeEffect()`.
- The inspector's `.toolbar` content is guarded on the presented flag and places its title `.automatic` (never `.navigation`); `PaneTitleBand` is not reused for it.
- One inspector toggle: trails Update in the Tile Detail band while closed; lives beside "Customise Tile" in the inspector band while open. Icon `sidebar.trailing`.
- Customise button and hero icon tap OPEN only, never close. View menu "Show Inspector" / "Hide Inspector", **⌥⌘I**, enabled only while a tile row is the sidebar selection.
- Hero while open: `DockTileIconPreview.fromConfig(editedConfig, size: 90).forcing(.defaultStyle | .dark by colorScheme)`; closed: today's `TileFace`.
- Nothing inside the inspector does work on `onAppear` (SwiftUI instantiates the content while closed).
- `isVisibleInDock` is written only by `performDockAction`; the inspector never calls `updateConfiguration`.
- Strings through `AppStrings` + String Catalog; new keys go `sync-keys` → `export` → machine pass → `import` → `check`. The author is named `k97` only. Tests use `MockUserDefaults`, never `UserDefaults.standard`.
- Run the unit suite on the Default icon style; rebuild signed after the test run before launching the dev app.

## Review Focus

1. The window is at the 1200 max (or against the screen's right edge) and the inspector opens: the frame must not exceed the screen or the max; the detail column absorbs the shortfall. Pinned in Task 1 (`windowFrame` cases).
2. The inspector is open and the user shrinks the window by dragging: `windowWillResize` must refuse below 1028, not 768. Pinned in Task 1 (`clampedWindowWidth(_:inspectorShown:)` cases).
3. A tile is deleted while the inspector is open and the list becomes empty: the detail shows the empty state with no inspector, no window resize, and the next tile created shows the inspector again. Structural (the inspector lives inside Tile Detail, which the empty state does not render); pinned by the Task 8 window-ID capture and AX read.
4. A colour change in the inspector on a hidden, unpinned tile: Tile Detail's **Done** must become enabled (content signature now includes icon fields). Pinned in Task 4 (`contentSignature` test).
5. ⌥⌘I while a Settings pane is showing: the menu item is disabled and nothing changes; the stored flag is untouched. Pinned in Task 6 (`inspectorCommandIsEnabled` cases).

---

### Task 1: Window width seams for the inspector

**Files:**
- Modify: `DockTile/App/AppDelegate.swift:28-35` (constants + clamp), `:170-197` (`windowWillResize`)
- Modify: `DockTile/Constants/UserDefaultsKeys.swift` (new key)
- Test: `DockTileTests/Unit/App/MainWindowWidthTests.swift`

**Interfaces:**
- Produces: `AppDelegate.minWindowWidth == 768`, `AppDelegate.inspectorWidth: CGFloat == 260`, `nonisolated static func clampedWindowWidth(_ width: CGFloat, inspectorShown: Bool) -> CGFloat`, `nonisolated static func windowFrame(forInspectorShown shown: Bool, from frame: CGRect, visibleFrame: CGRect) -> CGRect`, `UserDefaultsKeys.inspectorShown = "inspectorShown"`.

- [ ] **Step 1: Rewrite `MainWindowWidthTests`** — range test expects `minWindowWidth == 768`, `inspectorWidth == 260`, `maxWindowWidth == 1200`; parameterised clamp cases `(input, inspectorShown, expected)`: `(700,false,768) (768,false,768) (900,false,900) (1500,false,1200) (700,true,1028) (1000,true,1028) (1100,true,1100) (1500,true,1200)`; frame cases for `windowFrame`: open from `(x:100,y:200,w:800,h:600)` on `visibleFrame (0,0,2000,1200)` → `w:1060, x:100`; open from `w:1100` → `w:1200` (max); open from `x:1500,w:800` on that screen → `w:1060, x:940` (shifted left to fit); open from `w:800` on a `visibleFrame` only 900 wide → `w:900, x:0`; **second display**: open from `x:2100,w:800` on `visibleFrame (2000,0,1600,1000)` → `w:1060, x:2100`, and open from `x:3000,w:800` there → `w:1060, x:2540` (clamped to `maxX` 3600, so a clamp against `width` alone fails); close from `w:1060` → `w:800`; close from `w:1028` → `w:768`; close from `w:900` → `w:768` (never below the closed min). Height and y never change.
- [ ] **Step 2: Run** `xcodebuild test … -only-testing:DockTileTests/MainWindowWidthTests CODE_SIGNING_ALLOWED=NO` — expected FAIL (no `inspectorShown:` overload).
- [ ] **Step 3: Implement** in `AppDelegate`: `minWindowWidth = 768`, `nonisolated static let inspectorWidth: CGFloat = 260`, the two seams above (the one-argument `clampedWindowWidth` is replaced, not kept — update its two callers in `AppDelegate` and `DockTileConfigurationView.WindowAccessor` to pass `inspectorShown:`). `windowWillResize` and `configureMainWindowSizing` read `UserDefaults.standard.bool(forKey: UserDefaultsKeys.inspectorShown)` for the flag (the minimum follows the STORED flag by spec). Add the key to `UserDefaultsKeys` with a doc comment: main-app domain, default false = closed.
- [ ] **Step 4: Run** the same suite — expected PASS; then a Debug build — expected `BUILD SUCCEEDED`.
- [ ] **Step 5: Commit** `feat(window): 768/1028/1200 width seams for the Customise inspector`.

### Task 2: Strings and localization for the inspector

**Files:**
- Modify: `DockTile/Constants/AppStrings.swift` (`enum Title` at ~1352: add `customiseTile`; `enum Menu` ~1072: add `showInspector`, `hideInspector`)
- Modify: `DockTile/Resources/Localizable.xcstrings`, `docs/l10n/*.md` (via the tool)
- Test: `DockTileTests/Unit/Constants/AppStringsTests.swift`

**Interfaces:**
- Produces: `AppStrings.Title.customiseTile` ("Customise Tile"; en-US "Customize Tile"), `AppStrings.Menu.showInspector` ("Show Inspector"), `AppStrings.Menu.hideInspector` ("Hide Inspector"). The menu strings double as the toggle's `.help` and accessibility label (no separate tooltip keys).

- [ ] **Step 1: Add tests** in `AppStringsTests`: the three accessors are non-empty; `localizedString(for: "title.customiseTile", locale: "en-US") == "Customize Tile"` and `en-GB`/`en-AU` == "Customise Tile" (the catalog-JSON pattern at lines 246-304).
- [ ] **Step 2: Run** `-only-testing:DockTileTests/AppStringsTests` — expected FAIL (accessors missing).
- [ ] **Step 3: Add the three `NSLocalizedString(key, value:, comment:)` accessors** (keys `title.customiseTile`, `menu.showInspector`, `menu.hideInspector`), then run `python3 -I Scripts/l10n/l10n.py sync-keys`, fix the en-US value of `title.customiseTile` textually in the catalog as the warning directs, then `python3 -I Scripts/l10n/l10n.py export`.
- [ ] **Step 4: Machine pass**: in each of `docs/l10n/{zh-Hans,ja,de,ru,fr}.md` fill the Translation column of the three new rows with status `machine`, following `docs/l10n/GLOSSARY.md` (Apple's own View-menu wording for "Show/Hide Inspector" in each language), then `python3 -I Scripts/l10n/l10n.py import <lang>` for each.
- [ ] **Step 5: Run** `python3 -I -m unittest discover -s Scripts/l10n -p 'test_*.py'`, `python3 -I Scripts/l10n/l10n.py check`, and `-only-testing:DockTileTests/AppStringsTests -only-testing:DockTileTests/LocalizationCatalogTests` — expected all PASS.
- [ ] **Step 6: Commit** `feat(l10n): Customise Tile inspector title and Show/Hide Inspector menu strings`.

### Task 3: Inspector state and window grow/shrink

**Files:**
- Modify: `DockTile/Views/DockTileConfigurationView.swift` (`DockTileConfigurationView` state; `WindowAccessor`)
- Modify: `DockTile/App/AppDelegate.swift` (window lookup + resize)

**Interfaces:**
- Consumes: Task 1 seams and key.
- Produces: `@AppStorage(UserDefaultsKeys.inspectorShown) private var inspectorShown = false` on `DockTileConfigurationView`; `private func toggleInspector()`; `WindowAccessor(inspectorShown: Bool)` (replaces `isCustomising`); `AppDelegate.resizeConfigurationWindow(forInspectorShown shown: Bool)` (`@MainActor`).

Effective visibility (flag AND a tile row selected) is **structural**, not a seam: `.inspector` lives inside `DockTileDetailView`, which `DockTileConfigurationView.detailColumn` renders only for `.tile` (and `.tilesPlaceholder`/`.none` with no selected config → the empty state). No `effectiveInspectorVisibility` function exists; the menu half of the rule is Task 6's `inspectorCommandIsEnabled`, and the delete-last-tile case is pinned by the Task 8 capture.

- [ ] **Step 1: Implement `AppDelegate.resizeConfigurationWindow(forInspectorShown:)`**: find the window by `configurationWindowID`; compute `target = windowFrame(forInspectorShown:from: window.frame, visibleFrame: (window.screen ?? NSScreen.main)!.visibleFrame)`; **order matters** (the spike never ran with a raised minimum): when closing, lower `contentMinSize.width` to 768 BEFORE `setFrame`, when opening `setFrame` first THEN raise it to 1028 — so the frame change is never below the current minimum; `setFrame(target, display: true, animate: !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion)`. This method is the ONLY place that moves the frame for an inspector change. `configureMainWindowSizing` and `WindowAccessor.configureWindow` only **re-assert** `contentMinSize.width = clampedWindowWidth(0, inspectorShown:)` (768 / 1028) from the stored flag — they never change the frame for an inspector change. The SwiftUI `.frame(minWidth: 768)` under `.windowResizability(.contentSize)` stays at 768 while the AppKit minimum is 1028: the AppKit value wins, as the old 700 pt height override already relied on.
- [ ] **Step 2: Implement the state**: `toggleInspector()` flips `inspectorShown`, logs `ui("Inspector → \(shown ? "shown" : "hidden")")`, then calls `AppDelegate.resizeConfigurationWindow(forInspectorShown:)`. In `WindowAccessor` delete `customiseMinHeight`, `isCustomising` and the height-growth branch; keep the width clamp (now `clampedWindowWidth(_:inspectorShown:)`) and the 500 min height. Leave `isDrilledDown` in place for Task 4.
- [ ] **Step 3: Verify** with a Debug build (`BUILD SUCCEEDED`) and, on the signed dev build driven by AX: `position/size of window 1` reads `w` +260 after pressing the toggle and −260 after pressing it again; with the inspector open, `set size of window 1 to {800, 600}` leaves `w == 1028` (the raised minimum holds); with it closed the same call leaves `w == 800`.
- [ ] **Step 4: Run** the full unit suite — expected `TEST SUCCEEDED`.
- [ ] **Step 5: Commit** `feat(window): inspector open flag; grow/shrink and minimum from the toggle`.

### Task 4: Tile Detail hosts the inspector; the drill-down goes

**Files:**
- Modify: `DockTile/Views/DockTileDetailView.swift` (init `:133`, body `:140-283`, hero `:355-385`)
- Modify: `DockTile/Views/CustomiseTileView.swift` (init + state `:13-100`, `persistEdits` `:257`)
- Modify: `DockTile/Views/DockTileConfigurationView.swift:223-256` (`tileDetail`)
- Test: `DockTileTests/Unit/Views/DockActionResolutionTests.swift` (add a `contentSignature` case)

**Interfaces:**
- Consumes: Task 3 `inspectorShown`, `toggleInspector`.
- Produces: `DockTileDetailView(config: DockTileConfiguration, inspectorShown: Binding<Bool>, onToggleInspector: @escaping () -> Void)`; `CustomiseTileView(config: Binding<DockTileConfiguration>, isPresented: Bool, onToggleInspector: @escaping () -> Void)` — `isPresented` is the guard for the inspector's toolbar content (Task 5), passed as `inspectorShown.wrappedValue`. `CustomiseTileView` keeps every `nonisolated static` seam unchanged (`applyStyle`, `inspectorSections`, `colourRowState`, `appsSummary`, `appsCaption`, `TileStyle`).

- [ ] **Step 1: Add a test** to `DockActionResolutionTests`: two configs differing only in `tintColor` have different `contentSignature`s, and only in `iconFace` likewise (pins Review Focus 4 — it already holds, the test makes the dependency explicit).
- [ ] **Step 2: Run** it — expected PASS (guard, not driver; proceed).
- [ ] **Step 3: Refactor `CustomiseTileView`**: `@Binding var editedConfig`; delete `@State editedConfig`, `saveGeneration`, `hasPendingSave`, the `.onChange(of: editedConfig)` block, the `.task(id:)`, `.onDisappear`, `persistEdits()`, `onBack`, `selectAppsPill`; keep the per-field diagnostics `onChange`s and `selectIcon`. Body is unchanged otherwise in this task (canvas still present; Task 5 removes it).
- [ ] **Step 4: Refactor `DockTileDetailView`**: new init; apply `.inspector(isPresented: inspectorShown) { CustomiseTileView(config: $editedConfig, isPresented: inspectorShown.wrappedValue, onToggleInspector: onToggleInspector).inspectorColumnWidth(AppDelegate.inspectorWidth) }` on the ScrollView after `.paneTitleBand`; delete the icon-field sync lines inside `.onChange(of: configManager.configurations)` (keep the `showInAppSwitcher` sync and the comment's reasoning); hero icon tap and the Customise `SubtleButton` call `onToggleInspector()` only `if !inspectorShown.wrappedValue` (log `ui` either way, with "already open").
- [ ] **Step 5: Refactor `DockTileConfigurationView.tileDetail`**: delete `isDrilledDown`, the `ZStack`, both `.transition`s, the `.animation`; render `DockTileDetailView(config:inspectorShown: $inspectorShown, onToggleInspector: toggleInspector).id(selectedConfig.id)`; `WindowAccessor(inspectorShown: inspectorShown)`.
- [ ] **Step 6: Run** the full unit suite (`-only-testing:DockTileTests`) — expected `TEST SUCCEEDED`. Also fix the two `#Preview` blocks the init changes break (`DockTileDetailView.swift:876` `onCustomise: {}`, `CustomiseTileView.swift:977` `onBack: {}`). Then on the signed dev build, driven by AX in the single-`to` form and captured by window ID: after pressing the toggle, `static text "Customise Tile" of toolbar 1 of window 1` exists; after selecting the General row it does not; after selecting the tile row again it does; a capture after clicking a colour swatch shows the hero in that colour (no 300 ms wait needed: capture immediately).
- [ ] **Step 7: Commit** `feat(ui): Customise Tile is a trailing inspector editing Tile Detail's config; drill-down removed`.

### Task 5: Inspector layout — band, scrolling, fixed picker, canvas removed

**Files:**
- Modify: `DockTile/Views/CustomiseTileView.swift` (body, `canvas`/`canvasSurface`/`pairHalf`/`heroTile`/`heroStyles`/`monoFollowsAppearance` region `:240-380`, `inspector` `:383-405`, `pickerSection` `:720-760`)
- Modify: `DockTile/Views/DockTileConfigurationView.swift` (beside `PaneTitleBand`: new `InspectorTitleBand`)
- Delete: `DockTileTests/Unit/Views/CustomiseHeroStylesTests.swift`
- Test: `DockTileTests/Unit/Views/PaneScrollEdgeEffectTests.swift` (unchanged; the inspector reuses the seam)

**Interfaces:**
- Produces: `View.inspectorTitleBand(_ title: String, isPresented: Bool, onToggle: @escaping () -> Void)`; `CustomiseTileView.pickerGridHeight: CGFloat = 320` (nonisolated static).

- [ ] **Step 1: Add `InspectorTitleBand`** (`ViewModifier`, same file as `PaneTitleBand`): `.toolbar { if isPresented { ToolbarItem(placement: .automatic) { PaneTitleLabel(title:) } [+ .sharedBackgroundVisibility(.hidden) on macOS 26]; ToolbarSpacer(.flexible) / Spacer fallback; ToolbarItem(placement: .primaryAction) { Button(action: onToggle) { Image(systemName: "sidebar.trailing") }.help(AppStrings.Menu.hideInspector).accessibilityLabel(AppStrings.Menu.hideInspector) } } }`. Make `PaneTitleLabel` take a `leadingAdjustment` parameter defaulting to its current static so the inspector can pass its own measured value.
- [ ] **Step 2: Rebuild `CustomiseTileView.body`** as `ScrollView { VStack(alignment: .leading, spacing: 16) { …sections… }.padding(12) }.paneScrollEdgeEffect().inspectorTitleBand(AppStrings.Title.customiseTile, isPresented: isPresented, onToggle: onToggleInspector)` (`isPresented` from the Task 4 init: SwiftUI instantiates the content while closed, and an unguarded inspector toolbar merges into the main band — spike finding 1). Delete `canvas`, `canvasSurface`, `pairHalf`, `pairCaption`, `heroTile`, `selectAppsPill`, `GlassCapsule`, `paneGutter`, `pillInset`, `heroStyles`, `paneTopInset` and the `.ignoresSafeArea`/`.frame(width: 260)` on the old `inspector`. Keep `monoFollowsAppearance` (chips, captions). The picker card's `ScrollView` gets `.frame(height: Self.pickerGridHeight)`; drop the `maxHeight: .infinity` frames and the `Spacer` branch.
- [ ] **Step 3: Delete `CustomiseHeroStylesTests.swift`** (its seam is gone). Build + run `-only-testing:DockTileTests/CustomiseStyleTests -only-testing:DockTileTests/CustomiseColourRowStateTests -only-testing:DockTileTests/SystemSymbolNameTests` — expected PASS.
- [ ] **Step 4: Measure the title inset** on the running dev build: read the AX frame of the "Customise Tile" static text and of the first inspector card (`Scripts/dev-capture.sh` style `osascript`, single-`to` form) and set the inspector's `leadingAdjustment` so their leading edges match; record the number in a comment beside it. Capture by window ID.
- [ ] **Step 5: Commit** `feat(ui): inspector band, scrolling inspector with a 320 pt picker; canvas and Select Apps pill removed`.

### Task 6: Entry points — one moving toggle, open-only Customise, ⌥⌘I, canonical hero

**Files:**
- Modify: `DockTile/Views/DockTileDetailView.swift` (band `ToolbarItemGroup` `:165-180`, `heroSection` `:362-366`)
- Modify: `DockTile/Views/DockTileConfigurationView.swift` (focused value)
- Modify: `DockTile/App/DockTileApp.swift:80-115` (`commands`)
- Create: `DockTileTests/Unit/Views/InspectorEntryPointTests.swift`

**Interfaces:**
- Produces: `DockTileDetailView.heroForcedStyle(inspectorShown: Bool, colorScheme: ColorScheme) -> IconStyle?` (nonisolated static: `nil` when closed, `.defaultStyle` light / `.dark` dark when open); `DockTileConfigurationView.inspectorCommandIsEnabled(selection: SidebarSelection?) -> Bool` (true only for `.tile`); `struct InspectorCommand { let isEnabled: Bool; let isShown: Bool; let toggle: () -> Void }` + `FocusedValues.inspectorCommand`.

- [ ] **Step 1: Write `InspectorEntryPointTests`**: `heroForcedStyle(false, .light) == nil`, `(false, .dark) == nil`, `(true, .light) == .defaultStyle`, `(true, .dark) == .dark`; `inspectorCommandIsEnabled(.tile(UUID())) == true`, `(.settings(.popover)) == false`, `(.tilesPlaceholder) == false`, `(nil) == false`.
- [ ] **Step 2: Run** it — expected FAIL.
- [ ] **Step 3: Implement**: in the Tile Detail band, after `actionButton`, `if !inspectorShown.wrappedValue { Button(action: onToggleInspector) { Image(systemName: "sidebar.trailing") }.buttonStyle(.bordered).help(AppStrings.Menu.showInspector).accessibilityLabel(AppStrings.Menu.showInspector) }`. Hero: `if let forced = Self.heroForcedStyle(…) { DockTileIconPreview.fromConfig(editedConfig, size: 90).forcing(forced) } else { TileFace(config: editedConfig, size: 90) }` with the same `contentShape`/hover/tap modifiers on both. Root view: `.focusedSceneValue(\.inspectorCommand, InspectorCommand(isEnabled: Self.inspectorCommandIsEnabled(selection: selection), isShown: inspectorShown, toggle: toggleInspector))`. Commands: `CommandGroup(after: .sidebar) { InspectorMenuItem() }` where `InspectorMenuItem: View` reads `@FocusedValue(\.inspectorCommand)`, shows `Button(cmd?.isShown == true ? AppStrings.Menu.hideInspector : AppStrings.Menu.showInspector)` with `.keyboardShortcut("i", modifiers: [.command, .option])`, `.disabled(cmd?.isEnabled != true)`, logging `ui("Menu → \(label) (⌥⌘I)")`.
- [ ] **Step 4: Run** the full unit suite — expected `TEST SUCCEEDED`; on the signed dev build via AX: `enabled of menu item "Show Inspector" of menu "View" of menu bar 1` is `true` with a tile row selected and `false` on General; the count of toolbar buttons whose description is "Show Inspector" or "Hide Inspector" is exactly 1 with the inspector closed and exactly 1 open.
- [ ] **Step 5: Commit** `feat(ui): one inspector toggle that moves with the inspector, ⌥⌘I, canonical hero while editing`.

### Task 7: Orphans and documentation

**Files:**
- Delete: `DockTile/Components/IconGridOverlay.swift`, `DockTileTests/Unit/Components/IconGridOverlayLineColourTests.swift`; remove the four `IconGridOverlay` lines from `DockTile.xcodeproj/project.pbxproj` (`AAIGOV01`/`AAIGOV02`)
- Modify: `DockTile/Constants/AppStrings.swift` (delete `Button.selectApps`, `Label.previewLight`, `Label.previewDark`), `DockTileTests/Unit/Constants/AppStringsTests.swift:356`, `DockTile/Resources/Localizable.xcstrings` (delete the three entries textually, anchored on their keys, same style), `docs/l10n/*.md` via `export`
- Modify: `.claude/rules/architecture.md` ("Customise Tile is the one pane WITHOUT a title band" → the inspector rules), `.claude/rules/testing.md` (seam list: `clampedWindowWidth(_:inspectorShown:)` / `windowFrame(forInspectorShown:from:visibleFrame:)`, `heroForcedStyle`, `inspectorCommandIsEnabled`; drop `heroStyles`), `.claude/rules/icon-system.md:93` (`heroStyles` mention), `docs/design_handoff_customise_tile/README.md` (one-line superseded note at the top), `CLAUDE.md` if the Rules index text needs it

- [ ] **Step 1: Delete the orphans and the strings**; `python3 -I Scripts/l10n/l10n.py export` then `check`; grep the tree for `IconGridOverlay`, `selectApps`, `previewLight`, `previewDark`, `heroStyles` (incl. the `BackgroundChip` doc comment at `CustomiseTileView.swift:~990`), `isDrilledDown`, `onCustomise`, `onBack`, `customiseMinHeight` — expected no hits outside git history.
- [ ] **Step 2: Update the rules and the handoff note** as listed; the architecture.md inspector paragraph must state: effective visibility, 768/1028/1200, toggle-only resizing, `.automatic` title + guarded toolbar (why: the spike's merge/leak), one moving toggle, canonical hero while open, no `onAppear` work in the inspector.
- [ ] **Step 3: Run** the full unit suite, the l10n unit tests and `check`, and a Debug build — expected all green.
- [ ] **Step 4: Commit** `chore: remove the drill-down's orphans; rules for the Customise inspector`.

### Task 8: Verification and hands-on gate

**Files:** none (verification only).

- [ ] **Step 1: Full verification commands** from CLAUDE.md "Verification" on the Default icon style — expected `TEST SUCCEEDED` with per-suite counts reported for `MainWindowWidthTests`, `InspectorEntryPointTests`, `AppStringsTests`, `LocalizationCatalogTests`, `CustomiseStyleTests`, `CustomiseColourRowStateTests`, `DockActionResolutionTests`.
- [ ] **Step 2: Rebuild signed**, `codesign --verify` passes, launch the dev app in the background (never frontmost while the owner may be typing) and capture by window ID, reading `position/size of window 1` and the "Customise Tile" static text at each step: closed at 768 wide; open (window `w == 1028`); Settings pane with the flag on (no "Customise Tile" text, `w` unchanged); back to a tile (text present, `w` unchanged); delete-last-tile with the inspector open (empty state, no text, `w` unchanged); create a tile (text present again); Clear or Tinted style on this Mac with the inspector open (hero canonical) and closed (`TileFace`).
- [ ] **Step 3: Hands-on by Karthik** (cannot be scripted): Reduce Motion on → open/close has no animation; a drag below 1028 while open is refused; German or Russian: "Customise Tile" and the Show/Hide items fit.
- [ ] **Step 4: Run `gh workflow run ci.yml --ref <branch>`** before merging (the macOS 15 leg is the only place the `#available` fallbacks run). Expected: both jobs green; read the "Prove the suite" line.
- [ ] **Step 5:** `stage-gate --dev` on the diff before push (CLAUDE.md "Gates").
