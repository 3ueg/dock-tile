# Configure gear reveals its tile with Customise open (issue #31)

**Goal:** a tile's Configure gear (`docktile://configure?bundleId=…` / `?id=…`) always lands the main window on that tile with the Customise Tile inspector open, from any prior state.

**Root cause (issue #31):** the deep link only sets `ConfigurationManager.selectedConfigId`; the sidebar follows it via `.onChange(of: configManager.selectedConfigId)`, which does not fire when the value is unchanged. A Settings pane keeps `selectedConfigId` on the last tile, so configuring that tile is a no-op for the sidebar. Reproduced on v2.5.0 Release by hand (Settings → Popover, gear on the last-selected tile).

## Plan-gate answers (2026-10-23, Needs answers → resolved)

1. **Cold launch (F1):** `AppDelegate.configManager` is nil until the window's `onAppear`, and the URL can arrive first. `handleDeepLink` stores the URL in `pendingDeepLink` when `configManager` is nil (no window call: a launch presents the window itself), and `configManager`'s `didSet` replays it.
2. **API (F2):** `selectConfiguration(bundleId:)` keeps returning `Bool`; on `true` the reveal reads `configManager.selectedConfigId`. `ConfigurationManagerTests` untouched.
3. **Scope (F4, Karthik):** yes to both. The gear saves "Customise shown" (one inspector state, like Xcode), and the helper's Dock-menu Configure… (same deep link) gets the same behaviour. The main app's own Dock-menu item is unchanged.
4. **Redundant open (F3):** the receiver calls `setInspectorShown(true)` only when the stored flag is off; scenario 4 expects no `Inspector →` line.
- F6: the inspector opens in the same closure as the selection change, so `.transaction(value: selection)` strips its animation too. Not animated like a user toggle (the safer side: both inspector crash classes came from animated transitions).
- Simpler path rejected: resetting `selectedConfigId` to force `onChange` would clear edit sessions and flash the placeholder.

## Change (one task)

**Files**
- `DockTile/UI/LauncherView.swift`: add `static let revealTile = Notification.Name("revealTile")` beside `openSettingsPane` (object: the tile's `UUID`).
- `DockTile/App/AppDelegate.swift` `handleDeepLink`: hold the URL while `configManager` is nil (answer 1). Otherwise keep `selectConfiguration` (it persists the choice), call `showConfigurationWindow()`, and when it returned `true` post `.revealTile` with `configManager.selectedConfigId` on the next runloop turn (`DispatchQueue.main.async`), the same ordering `DockTileApp.openSettingsPane` uses so a just-recreated view is subscribed. On `false`, behaviour is unchanged (window shown, no reveal).
- `DockTile/Views/DockTileConfigurationView.swift`: `.onReceive(.revealTile)` beside the `.openSettingsPane` receiver: `selection = .tile(id)`, then `setInspectorShown(true)` only when the stored flag is off (answer 4; the single writer that also grows the window to the 960 pt open minimum). Opening only, never a toggle.
- `.claude/rules/architecture.md` "Popover Configure Gear Icon": one sentence: the gear reveals the tile with Customise open via `.revealTile`, never via `selectedConfigId`'s `onChange` alone (equal value → no change → Settings pane stayed up).

**Not changed:** `.onChange(of: selectedConfigId)` (create/delete/duplicate still rely on it); the ⌘N / + paths; #29's window-recreation path.

## Verification

- Build Debug; `codesign --verify` the product; relaunch the dev app.
- No new unit test: the defect is notification-vs-`onChange` wiring inside a view, and the only pure seam available (`.tile(id)` + `true`) would pass for the broken code too — decorative per testing.md "A guard must be able to fail". Existing seams untouched; full `xcodebuild test` suite runs before commit (Karthik's go-ahead first).
- Hands-on (Karthik, dev build, dev tile gear), each must end on the gear's tile with Customise open:
  1. Window on Settings → Popover, gear on the last-selected tile (the #31 repro).
  2. Window on another tile, Customise closed.
  3. Window on the same tile, Customise closed.
  4. Window on the same tile, Customise already open (stays open, no flicker/toggle).
  5. Main app not running (cold launch).
  6. Dock Lock on, window closed, app resident (window recreated). A failure with NO window is #29's path, not this change.
  7. `open -a <dev app> "docktile://configure?bundleId=bogus"`: window shows, selection and inspector unchanged.
- Read `diagnostics.log` after each: `[deeplink] Received …` then `[ui] Inspector → shown` (or none in 4) and the tile selection line.

## Review focus

- A crash/constraint loop from collapsing-to-tile and opening the inspector in one turn (both crash classes in architecture.md came from inspector transitions). Selection changes are animation-free via `.transaction(value: selection)`; the inspector open is the user-toggle path. Scenario 1 exercises it.
- Window narrower than 960 on a reveal: `setInspectorShown(true)` grows it (existing behaviour of the toggle).
- A deep link for an unknown tile must not open the inspector on whatever tile is selected.
