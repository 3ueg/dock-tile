# Stable Inspector Identity Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Bring tile switching with the Customise inspector open back to v2.4.0's cost by keeping the inspector alive across tiles, with no change a user can see beyond the one the spec names.

**Architecture:** First prove the best case: HEAD with only the inspector's `.id(selectedConfig.id)` removed, raced against v2.4.0. Only if that meets the bar: move the inspector's per-tile state onto an observable owned by each `TileEditSession`, re-key the search field per session, make the inspector's change logs ignore tile switches, then drop the `.id` for real and re-measure. Tile Detail is not touched.

**Tech Stack:** Swift 6, SwiftUI + AppKit, Swift Testing, `xcrun xctrace` (Animation Hitches).

**Spec:** `docs/superpowers/specs/2026-10-22-stable-tile-identity-design.md`

## Global Constraints

- Swift 6 strict concurrency; macOS 15 floor (`ScrollPosition` is macOS 15+, no gate needed).
- No new app-target files: append to the files each task names. New tests go under `DockTileTests/` (auto-join).
- Tile Detail is out of scope: in `DockTileDetailView.swift` only `TileEditSession` changes; `tileDetail`'s `.id(selectedConfig.id)`, `persistEdits`, the debounce and the `onDisappear` flush stay as they are.
- **Measurement protocol** (every A/B in this plan): optimised builds into scratch DerivedData (recipe in `Scripts/perf/README.md` after Task 1), deleted afterwards; baseline is tag `v2.4.0` (its app code = main's; no schema change since, same MARKETING_VERSION 2.4.0, so it runs safely on the dev data without migration); builds run interleaved (A, B, C, A, B, C, …), **three runs each**, decisions on the **mean**; a run with a lone hang over 1 s (a machine hiccup, as the perf rule records) is rerun, not averaged; check the sidebar row names before each block (test runs create and delete dev tiles); `mem` = 200 switches over the mixed sequence, footprint read at +10 s AND +30 s after the last switch, the bar applied to +30 s.
- **Pass bar** (spec Decision 2), tile switching only: inspector open, tiles sequence mean frozen ≤ v2.4.0 mean + 150 ms and mean hangs ≤ v2.4.0 + 2; `mem` ≤ v2.4.0 + 10 MB. Inspector closed and the Settings sequence: no worse than the pre-change branch by more than 150 ms / 2 hangs.
- Dev app: rebuild signed + relaunch after each code change; ask Karthik before `xcodebuild test`, AX driving or benchmark runs.
- Tests: `xcodebuild test -project DockTile.xcodeproj -scheme DockTile -configuration Debug -destination 'platform=macOS' -only-testing:DockTileTests CODE_SIGNING_ALLOWED=NO` → `** TEST SUCCEEDED **`; then a signed rebuild that passes `codesign --verify`.
- Commits end with `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`.

## Review Focus

Each item is checked by hand on HEAD **before** Task 4 (to record today's behaviour) and again after it.

1. **Search text never crosses tiles.** Route: type "star" in a Symbol tile's picker search, keep focus there, press ⌘N (New Tile) — the new tile's search is empty and its grid unfiltered; typing then goes to the new field only.
2. **Colour panel after a switch.** Route: Custom colour → panel open → switch tile → drag in the panel. Expected, today and after: the stored `tintColor` of NEITHER tile changes (the panel holds the old session's bindings). Observe the dev config JSON for both tiles.
3. **A switch logs nothing.** After Task 4 a tile switch fires the inspector's change handler; a plain switch must add no `tile`/`ui` "changed" lines to `diagnostics.log`. Pinned by `InspectorChangeLogTests` + the source scan in Task 2.
4. **Scroll starts at the top.** Scroll the inspector and the picker down on tile A, switch to B (and close/reopen on A): both at the top.
5. **Focus (named change, spec 6a).** Tab focus or VoiceOver on a Style card, switch tile: focus stays on that card (today it is dropped). Record both; anything else is a finding.

---

### Task 1: Harness in the repo + best-case go/no-go

**Files:**
- Create: `Scripts/perf/nav-bench.sh`, `Scripts/perf/nav-hangsum.sh`
- Modify: `Scripts/perf/README.md`, `.claude/rules/performance-measurement.md` ("Main-window navigation")

**Interfaces:**
- Produces (footprint at +10 s and +30 s in `mem` mode): `nav-bench.sh <app path> <label> <inspectorShown true|false> <settings|tiles|symbols|mem>` writing under `$NAV_BENCH_OUT` (default `$TMPDIR/nav-bench`); `nav-hangsum.sh <label>` → `[label] hangs: N totalling X ms, worst Y ms`, refusing any run whose `switches driven` is below 12.

- [ ] **Step 1: Port the session harness** from `/private/tmp/claude-501/-Users-karthik-Work-Products-Docktile-dock-tile/0bf36d6b-408f-4b3f-8d5e-5ecc343b2b4f/scratchpad/` (`hitches2.sh`, `findsidebar.zsh`, `memplateau3.sh`, `hitchsum.sh`; copy before the folder goes). Keep: AX sidebar path with the reopen retry; exit 2 with `NO SIDEBAR — run invalid`; `switches driven: N/12`; idle CPU from two `ps -o time=` reads, never `top`; `pgrep -f "…/MacOS/Dock Tile Dev( |$)"`. Sequences (dev data): `tiles` = rows 2,3,4 ×4 (Dev symbol, Media App Grid, Work symbol); `symbols` = rows 2,4 ×6 (symbol↔symbol, the picker survives); `settings` = General/Work/Popover/Work/About/Work ×2; `mem` as in the protocol. README: the optimised recipe and the protocol.
- [ ] **Step 2: Prove the guard fails.** `nav-bench.sh /nonexistent x false tiles` → exit 2; a run with 11 driven switches → `nav-hangsum.sh` refuses it.
- [ ] **Step 3: Best-case spike (throwaway, never committed).** A scratch worktree at HEAD with only `.id(selectedConfig.id)` removed from `inspectorColumn`. Three optimised builds: `v2.4.0`, HEAD, spike. Run the protocol, inspector open: `tiles`, `symbols`, `mem`; plus `tiles` closed and `settings` open for HEAD and spike.
- [ ] **Step 4: Go/no-go.** Spike meets the pass bar on `tiles` and `mem` → go. Otherwise stop and report the table to Karthik; no later task is built (spec Decision 3). Record the table in the perf rule either way.
- [ ] **Step 5: Commit** the harness and rule (`perf(tools): navigation benchmark harness`). `DevToolingExclusionTests` stays green. Delete the scratch worktree and its DerivedData.

### Task 2: A tile switch is never logged as an edit

**Files:**
- Modify: `DockTile/Views/CustomiseTileView.swift` (the six per-field `onChange` logs, lines ~40–57)
- Test: `DockTileTests/Unit/Views/InspectorChangeLogTests.swift` (create)

**Interfaces:**
- Produces: `CustomiseTileView.changeLogs(from old: DockTileConfiguration, to new: DockTileConfiguration) -> [ChangeLog]`, `nonisolated static`; `struct ChangeLog: Equatable { let category: String; let message: String; let verbose: Bool }`. Empty when `old.id != new.id`; otherwise one entry per changed field, in this order and with today's exact text:
  - tintColor → `("tile", "Colour changed for \(new.diagnosticName) → \(new.tintColor)", verbose: true)`
  - background → `("ui", "Customise → Background \(new.background.rawValue) for '\(new.name)'", verbose: true)`
  - iconScale → `("tile", "Icon size changed to \(new.iconScale) for \(new.diagnosticName)", verbose: true)`
  - iconValue → `("tile", "Icon changed to \(new.iconType == .emoji ? "emoji" : "symbol") '\(new.iconValue)' for \(new.diagnosticName)", verbose: false)`
  - iconWeight → `("ui", "Customise → Icon weight \(new.iconWeight.rawValue) for '\(new.name)'", verbose: true)`
  - iconFace → `("tile", "Face changed to \(new.iconFace.rawValue) for \(new.diagnosticName)", verbose: false)`

- [ ] **Step 1: Write the failing tests**

```swift
@Test func switchingTilesLogsNothing() {
    let a = DockTileConfiguration(name: "A", tintColor: .preset(.blue), iconValue: "star")
    let b = DockTileConfiguration(name: "B", tintColor: .preset(.red), iconValue: "heart")
    #expect(CustomiseTileView.changeLogs(from: a, to: b).isEmpty)
}
@Test func everyLoggedFieldKeepsItsMessage() {
    let a = DockTileConfiguration(name: "A", tintColor: .preset(.blue), iconValue: "star", iconScale: 14,
                                  iconWeight: .medium, background: .colour, iconFace: .glyph)
    var b = a
    b.tintColor = .preset(.red); b.background = .mono; b.iconScale = 15
    b.iconValue = "heart"; b.iconWeight = .bold; b.iconFace = .apps
    #expect(CustomiseTileView.changeLogs(from: a, to: b) == [
        .init(category: "tile", message: "Colour changed for \(b.diagnosticName) → \(b.tintColor)", verbose: true),
        .init(category: "ui", message: "Customise → Background mono for 'A'", verbose: true),
        .init(category: "tile", message: "Icon size changed to 15 for \(b.diagnosticName)", verbose: true),
        .init(category: "tile", message: "Icon changed to symbol 'heart' for \(b.diagnosticName)", verbose: false),
        .init(category: "ui", message: "Customise → Icon weight bold for 'A'", verbose: true),
        .init(category: "tile", message: "Face changed to apps for \(b.diagnosticName)", verbose: false)])
}
@Test func unrelatedFieldLogsNothing() {
    let a = DockTileConfiguration(name: "A")
    var b = a; b.name = "Renamed"
    #expect(CustomiseTileView.changeLogs(from: a, to: b).isEmpty)
}
@Test func inspectorLogsThroughChangeLogsOnly() throws {
    let src = try String(contentsOf: URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("DockTile/Views/CustomiseTileView.swift"), encoding: .utf8)
    #expect(!src.contains(".onChange(of: editedConfig."))
    #expect(src.contains("Self.changeLogs(from:"))
}
```

(Adjust the `DockTileConfiguration` initialiser's argument order to its declaration; the `#filePath` hop count to the repo root as other source-scan tests do.)

- [ ] **Step 2: Run** `-only-testing:DockTileTests/InspectorChangeLogTests` → FAIL (`changeLogs` missing; the scan finds today's handlers).
- [ ] **Step 3: Implement** `changeLogs` and replace the six handlers with one `.onChange(of: editedConfig) { old, new in for log in Self.changeLogs(from: old, to: new) { DiagnosticsLog.shared.log(log.category, log.message, verbose: log.verbose) } }`. Leave `.onChange(of: selectedStyle)` for Task 3.
- [ ] **Step 4: Run** the suite → `** TEST SUCCEEDED **`.
- [ ] **Step 5: Commit** (`refactor(ui): the inspector logs edits, never tile switches`).

### Task 3: The inspector's per-tile state lives on the session

**Files:**
- Modify: `DockTile/Views/DockTileDetailView.swift` (`TileEditSession` only), `DockTile/Views/CustomiseTileView.swift` (state, init, `#Preview`), `DockTile/Views/DockTileConfigurationView.swift` (`CustomiseInspectorColumn`)
- Test: `DockTileTests/Unit/Views/TileEditSessionStoreTests.swift`, `DockTileTests/Unit/Views/InspectorChangeLogTests.swift` (one more scan)

**Interfaces:**
- Produces: `@MainActor final class CustomiseInspectorState: ObservableObject` (in `CustomiseTileView.swift`) with `@Published var searchText = ""`, `@Published var customColor: Color = .blue`, `@Published var scroll = ScrollPosition(edge: .top)`, `@Published var pickerScroll = ScrollPosition(edge: .top)`, and `func reset()` restoring all four. `TileEditSession.inspector: CustomiseInspectorState` (`let`, created in `init`). `CustomiseTileView.init(config:inspector:)` — `inspector` required, no default.

- [ ] **Step 1: Write the failing tests**

```swift
@Test func eachSessionStartsWithFreshInspectorState() {
    let s = TileEditSession(config: DockTileConfiguration(name: "A"))
    #expect(s.inspector.searchText.isEmpty)
    #expect(s.inspector.customColor == .blue)
}
@Test func switchingTilesNeverSharesInspectorState() {
    let store = TileEditSessionStore()
    let a = store.session(for: DockTileConfiguration(name: "A"))
    a.inspector.searchText = "star"
    let b = store.session(for: DockTileConfiguration(name: "B"))
    #expect(b.inspector.searchText.isEmpty)
    #expect(a.inspector !== b.inspector)
}
@Test func resetRestoresAFreshInspector() {
    let s = TileEditSession(config: DockTileConfiguration(name: "A"))
    s.inspector.searchText = "star"; s.inspector.customColor = .red
    s.inspector.scroll = ScrollPosition(edge: .bottom); s.inspector.pickerScroll = ScrollPosition(edge: .bottom)
    s.inspector.reset()
    #expect(s.inspector.searchText.isEmpty && s.inspector.customColor == .blue)
    #expect(s.inspector.scroll == ScrollPosition(edge: .top) && s.inspector.pickerScroll == ScrollPosition(edge: .top))
}
// InspectorChangeLogTests:
@Test func inspectorKeepsNoViewState() throws {
    // same file read as inspectorHasNoPerFieldLogHandlers
    #expect(!src.contains("@State"))
}
```

- [ ] **Step 2: Run** both suites → FAIL.
- [ ] **Step 3: Implement.**
  - `CustomiseTileView` takes `@ObservedObject var inspector` (required init parameter) and drops its two `@State`s; the `#Preview` passes `CustomiseInspectorState()`.
  - Scroll positions bind through an **equality-guarded** binding (`@Published` publishes on every set, equal values included): `Binding(get: { inspector.scroll }, set: { if $0 != inspector.scroll { inspector.scroll = $0 } })` on the outer `ScrollView`'s `.scrollPosition(_:)`, the same for `pickerScroll` on the picker card's.
  - `.onChange(of: selectedStyle)` clears `searchText` only when it is not already empty.
  - `CustomiseInspectorColumn` passes `session.inspector`, and calls `session.inspector.reset()` when `isPresented` becomes **false** (spec Decision 4's "reset on reopen", done at close so the reopened view is built fresh in one pass; not `initial: true`, not `onAppear`).
  - `.id(selectedConfig.id)` on `inspectorColumn` stays — no tile-switch behaviour change yet.
- [ ] **Step 4: Check re-render cost.** Temporarily add `let _ = Self._printChanges()` to `CustomiseTileView.body`; launch the signed dev binary from Terminal (ask Karthik first) to see stdout; scroll each scroll view through one gesture: at most one body run per gesture, and no "Publishing changes from within view updates" warning. Remove before commit. More than that → stop and report (the guarded binding is the design; there is no in-view fallback, because view `@State` would carry across tiles).
- [ ] **Step 5: Run** the suite → `** TEST SUCCEEDED **`; signed rebuild; relaunch; check by eye that search filters, a custom colour applies, both scroll views scroll, and close/reopen resets.
- [ ] **Step 6: Record Review Focus 1–5 on this build** (today's behaviour, `.id` still on) in the ledger, then commit (`refactor(ui): the inspector's per-tile state lives on the session`).

### Task 4: Drop the inspector's per-tile identity, measure, hands-on

**Files:**
- Modify: `DockTile/Views/DockTileConfigurationView.swift` (`inspectorColumn`), `DockTile/Views/CustomiseTileView.swift` (`iconSearchField`)

**Interfaces:**
- Consumes: `CustomiseInspectorState` and `TileEditSession.inspector` (Task 3); `changeLogs` (Task 2); `nav-bench.sh` (Task 1).

- [ ] **Step 1: Remove `.id(selectedConfig.id)` from `inspectorColumn`**; give `iconSearchField` `.id(ObjectIdentifier(inspector))`. (Consecutive sessions are distinct live objects — the store builds B while A is alive — so the identifier never repeats across a switch.)
- [ ] **Step 2: Run** the suite → `** TEST SUCCEEDED **`; signed rebuild; relaunch. Check Review Focus 4 now: if tile B does not open at the top (A's and B's positions are both `.top`, so the binding may not change), add `.onChange(of: ObjectIdentifier(inspector))` that calls `inspector.scroll.scrollTo(edge: .top)` and `inspector.pickerScroll.scrollTo(edge: .top)` (an explicit scroll request, which applies even when the stored value already reads `.top`), and re-check; if the result shows a visible jump on the switch, stop and report.
- [ ] **Step 3: Measure** per the protocol: `v2.4.0`, pre-Task-4 branch (Task 3's commit), and this build — `tiles` and `symbols` open, `tiles` closed, `settings` open, `mem` open.
- [ ] **Step 4: Hands-on** (one block, announced): Review Focus 1–5 against the Task 3 record; Symbol ↔ Emoji ↔ App Grid tiles in a row; delete the selected tile with the inspector open; Smart Add → Use This Tile; ⌥⌘I and the hero toggle; Light/Dark switch. macOS 15 cannot be checked on this Mac (scroll reset and `ScrollPosition` behaviour there are unverified; CI runs unit tests only) — say so in the report.
- [ ] **Step 5: Decide.** Pass bar met and the hands-on clean → commit with the table in the message (`perf(ui): the Customise inspector keeps its identity across tiles`). Otherwise revert Tasks 2–4's commits (spec Decision 8) and report the numbers.

### Task 5: Rules and the dev gate

**Files:**
- Modify: `.claude/rules/architecture.md` (inspector bullets: per-session state, reset on reopen, re-keyed search field, switch ≠ edit, focus persists), `.claude/rules/testing.md` (seams `changeLogs`, `CustomiseInspectorState`), `.claude/rules/performance-measurement.md` ("Against the release" table), the spec's status line

- [ ] **Step 1: Full suite** → `** TEST SUCCEEDED **`; signed rebuild passes `codesign --verify`.
- [ ] **Step 2: Rules** updated as listed, with the final table.
- [ ] **Step 3: `stage-gate --dev`**, then commit (`docs(rules): the inspector keeps its identity across tiles`).
