# Flush a pending tile edit on quit (issue #30)

**Goal:** an edit made less than 300 ms before the app terminates (⌘Q, logout, Sparkle's install-on-quit) is saved, through Tile Detail's existing single save path.

**Root cause (proven 2026-10-23, temporary experiment build, debounce stretched to 5 s, never committed):** Tile Detail persists an edit only from the debounced `.task(id: saveGeneration)` or from `.onDisappear`. On ⌘Q neither runs: the log showed only `applicationWillTerminate`, no `onDisappear`, and the config kept `Work` after the user typed `WorkY`.

**Fix proven by the same experiment:** a `.onReceive(NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification))` on Tile Detail that calls `persistEdits()` when `hasPendingSave`. Logged at 00:16:55: `applicationWillTerminate` (.095) → receiver `pending=true name=WorkY` (.096) → done (.097); the config then held `WorkY`. So SwiftUI delivers the notification synchronously inside `terminate`, and `persistEdits` → `ConfigurationManager.updateConfiguration` → `saveConfigurations()` writes synchronously (`Data.write(.atomic)`).

## Change (one task)

- `DockTile/Views/DockTileDetailView.swift`: beside `.onDisappear`, add the `willTerminate` receiver: `if hasPendingSave { persistEdits() }`, with a one-line comment (quit cancels the debounce and delivers no onDisappear; #30). Same guard as `onDisappear`, so nothing new is saved when no edit is pending.
- `.claude/rules/architecture.md`, "One edit session" bullet: add "quit flush" to the list of the save path's parts (`300 ms debounce, onDisappear flush, willTerminate flush, …`).

**Simpler/other paths considered:** flushing from `AppDelegate.applicationShouldTerminate` would need the delegate to reach the view's private state or a second save path (the plan keeps one). `TileEditSession` could own the flush, but `hasPendingSave` and `persistEdits` live in the view; moving them is a refactor the bug doesn't need.

**Plan-gate notes (Ready to build):** also update the two comments that name only `onDisappear` (the `hasPendingSave` doc comment and the debounce task's comment). Releasing #30 together with #31 (version bump, tag) is a separate step after this branch.

**Assumptions:** the app does not opt into sudden or automatic termination (Info.plist has neither key; no `enableSuddenTermination` call), so logout and Sparkle install-on-quit go through `terminate` and post `willTerminate`. Only ⌘Q is observed; logout is inferred. A crash or force-quit still loses a pending edit (accepted; nothing can flush then).

## Verification

- Build Debug, `codesign --verify`, relaunch the dev app.
- Hands-on (Karthik), shipped 300 ms debounce: rename the Work tile and ⌘Q at once, then read the dev config: the new name is there. Repeat with a Customise edit (e.g. tile colour) and ⌘Q at once.
- Full `xcodebuild test` suite before commit (Default icon style), then rebuild signed.
- No new unit test: the defect is a lifecycle event the view never heard; a seam would only restate `hasPendingSave` (testing.md "A guard must be able to fail"). The experiment log above is the evidence the mechanism works.
