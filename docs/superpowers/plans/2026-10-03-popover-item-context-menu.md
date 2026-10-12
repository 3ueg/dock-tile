# Popover Item Context Menu (issue #17) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Right-click or Control-click on an app or folder in a tile's Dock popover shows a native
context menu, in both Grid and List layouts, without changing left-click behaviour. Folders get Open ·
Show in Finder · Get Info · Quick Look · Share…; apps get Open plus Hide · Quit when running (revised
after the spike, D1).

**Architecture:** A transparent AppKit overlay view on each popover cell claims *only* secondary clicks
(right-click, Control-click) and builds a fresh `NSMenu` at click time from a pure, unit-tested seam
(`PopoverItemMenu.entries`). A small `@MainActor` controller performs each action with public AppKit API.
Everything is attached only in the shipped popover (`editing == nil && !isPreview`), so the Tile Detail
editor and the Settings preview are untouched by construction, using the same idiom as `editingOnly`.

**Tech Stack:** Swift 6, SwiftUI + AppKit (`NSMenu`, `NSWorkspace`, `NSRunningApplication`,
`NSSharingServicePicker.standardShareMenuItem`, `NSPerformService`, Quartz `QLPreviewPanel`), Swift Testing.

**Spec:** GitHub issue #17 plus the **Decisions** section below (grilled with Karthik on 2026-10-03).
Research basis: Finder's own context menu cannot be obtained through any public API; Spotlight, Raycast
and Alfred all build curated menus from public pieces.

## Decisions (from the grilling session; binding)

| # | Decision |
|---|---|
| D1 | **Revised 2026-10-10 after the spike** (the original menu, with Show in Finder · Get Info · Quick Look · Share for apps, triggered macOS's App Management alert for every `/Applications` app). **Folder:** `Open` · — · `Show in Finder` · `Get Info` · `Quick Look` · — · `Share…` (no icon on Share). **App:** `Open`; if running, also — · `Hide` (omitted when already hidden) · `Quit` (⌥ swaps in `Force Quit`). An app never gets an item that hands its bundle to another process. |
| D2 | Get Info uses Finder's "Show Info" service via `NSPerformService`. **No AppleScript fallback.** Ships only if the spike passes, and only on macOS 26+ (`#available`); macOS 15 never shows it. |
| D3 | Quick Look: the popover closes, the QL panel stays up on its own, and Space/Esc dismisses it. Ships only if the spike passes. |
| D4 | Every action closes the popover **except Share… and Get Info**. For both, we never close the popover ourselves while the action is under way. If macOS (transient behaviour) or the click-outside monitor closes it because Finder came forward or the user clicked into the share UI, that's accepted (confirmed after the plan gate, 2026-10-03). Share closes it when sharing finishes or fails. Cancelling the menu, or cancelling the share picker, leaves the popover open. No change to `FloatingPanel`'s dismissal. |
| D5 | Mechanism: AppKit `NSMenu` built at right-click time through a thin NSView bridge, **not** SwiftUI `.contextMenu`. VoiceOver gets `.accessibilityAction(.showMenu)`. |
| D6 | No tile-level items (no Remove from Tile, no Configure Tile…). |
| D7 | Missing (uninstalled or deleted) items: no menu at all. |
| D8 | Analytics: one new event `popover_item_action` with `action` and `is_folder` params, plus a verbose `DiagnosticsLog.ui` line per pick. |
| D9 | Verification: hands-on on macOS 27 only. The pure seams run on both CI legs (macOS 26 + macOS 15). **Accepted risk:** the issue's "works across macOS 15.0+" criterion is met by public macOS 13+ APIs plus unit tests on the macOS 15 leg, not by hands-on testing on 15. |
| D10 | While the menu is open, the clicked cell shows the existing keyboard-selection highlight (`selectedContentBackgroundColor`). |

## Global Constraints

- Deployment target macOS 15.0. Every API used must exist on 15 (`standardShareMenuItem` is 13+). Get Info is gated `#available(macOS 26, *)` (D2).
- Helpers must never write the shared config or touch the Dock (architecture.md "Helpers must not touch the Dock").
- The shipped popover's left-click, hover, scroll and keyboard navigation are unchanged.
- Editor (`editing != nil`) and Settings preview (`isPreview == true`) get **no** item menu. The editor keeps its existing Remove `.contextMenu`.
- All user-facing strings go through `AppStrings`, using the same text for en-US, en-GB and en-AU. Edit `.xcstrings` by **textual insert only** (localization-macos.md), never by load-and-redump.
- HIG for context menus: no keyboard-shortcut glyphs; hide items that don't apply rather than dimming them; at most three groups.
- New **app-target** files need manual `project.pbxproj` entries. New `DockTileTests/` files auto-join.
- One `NSPopover` per helper for its whole life (architecture.md). Never construct a popover here.
- **App Management (critical, from the spike):** handing a third-party app bundle to Finder, Quick Look or a share service from a helper makes macOS show "*<tile>* was prevented from modifying apps on your Mac". Helpers can't hold that permission (unentitled; Developer ID doesn't help). So reveal, Get Info, Quick Look and Share are **folder-only**, enforced by the pure seam and its tests.
- **Accepted side effect:** shipped cells become one combined accessibility element (`.accessibilityElement(children: .combine)`), so the cell carries the VoiceOver Show Menu action. VoiceOver then reads each cell as one item (icon + name) for every user, menu or not.
- **Analytics:** a menu Open logs `app_launched_from_tile` with `source: "item_menu"` (left-click keeps `"popover"`) **and** `popover_item_action` with `action: open`. That's two events with different meanings, never counted as a left-click launch.

## Review Focus

1. **Two installs share a bundle id (Chrome PWAs, a beta beside a release).** Hide/Quit must target the
   copy at *this item's* resolved path, never "the first running app with that bundle id". The decision is pinned in Task 2 (`runningMatchIndex` tests). That `make()` actually uses the seam is checked hands-on (Task 5 row G11), because no unit test can catch a regression to `candidates.first`.
2. **App is hidden when right-clicked.** A Hide row for an already-hidden app is a no-op item. Expect it to be omitted. Pinned in Task 2.
3. **Control-click must not also launch.** The cell's `.onTapGesture` must never see a Control-click. The decision is pinned in Task 2 (`claimsEvent`). Only the hands-on rows S2/G5 prove that `hitTest` uses the seam and that the tap gesture really stays silent.
4. **Item deleted while the popover is open.** The menu is built at click time, so a now-missing item
   must yield no menu, not a menu whose actions fail silently. Pinned in Task 2 (`entries(isMissing: true) == []`).
6. **Someone later adds "Show in Finder" (or Quick Look, Get Info, Share) for apps.** The App Management alert would return for every user. Pinned in Task 2 (`appsNeverHandOffTheBundle`), and checked against macOS's own log in Task 5 row G12.
5. **Scrolling and hover over cells with the overlay present.** Scroll-wheel and mouse-moved events must pass through to the grid's `ScrollView` and SwiftUI `onHover`. Pinned in Task 2 (`claimsEvent` returns false for `.scrollWheel` / `.mouseMoved`) and checked hands-on.

---

## File Structure

| File | Responsibility |
|---|---|
| Create `DockTile/UI/PopoverItemMenu.swift` | Everything for the feature: pure seams (`PopoverItemAction`, `PopoverItemMenuEntry`, `PopoverItemMenu`), the event-claim seam + overlay `NSView`, the `@MainActor` action controller, `QuickLookPresenter`, the SwiftUI bridge and the `itemContextMenu` view modifier. Kept in one file so it needs one pbxproj entry and sits beside `NativePopoverViews.swift`. |
| Modify `DockTile/UI/NativePopoverViews.swift` | Pass menu hooks into `StackAppItem` / `ListAppRow`; apply the modifier; union the menu target into `isSelected`. |
| Modify `DockTile/Constants/AppStrings.swift` + `DockTile/Resources/Localizable.xcstrings` | New `AppStrings.ItemMenu` strings. |
| Modify `DockTile/Managers/AnalyticsService.swift` | `AnalyticsEvent.popoverItemAction`. |
| Modify `DockTile/App/HelperAppDelegate.swift` | Quick Look panel controller (`acceptsPreviewPanelControl` / `begin` / `end`): the panel takes its data source from a controller found through the app's chain of responding objects (QLPreviewPanel.h). |
| Modify `DockTile/Utilities/AppLauncher.swift` | `launch(_:source:)`, so a menu Open is attributed `item_menu`. |
| Modify `DockTile.xcodeproj/project.pbxproj` | Register the new app-target file. |
| Create `DockTileTests/Unit/UI/PopoverItemMenuTests.swift` | Seam tests. |
| Modify `DockTileTests/Unit/Constants/AppStringsTests.swift` | New string expectations. |
| Modify `.claude/rules/architecture.md`, `.claude/rules/testing.md` | Document the feature + seams. |

Branches: Task 1 runs on a throwaway `spike/popover-item-menu`. Task 1 Step 5 creates `feat/popover-item-menu` from `main`, and Tasks 2–7 run there.

---

### Task 1: Spike — prove the risky mechanics on a real helper (hands-on gate)

Throwaway code that answers the questions the rest of the plan depends on. **No production code before
this passes.** The spike lives on its own branch and is deleted afterwards.

**Files:**
- Modify (spike branch only): `DockTile/UI/NativePopoverViews.swift` (append at end of file), `DockTile/App/HelperAppDelegate.swift` (Quick Look controller)

- [ ] **Step 1: Create the spike branch**

```bash
git switch -c spike/popover-item-menu
```

- [ ] **Step 2: Add the spike overlay and a hard-coded menu** (append to `NativePopoverViews.swift`)

```swift
import Quartz

// SPIKE (issue #17) — deleted after Task 1.
// The picker delegate is NOT main-actor annotated in the SDK (NSSharingService.h), so it needs
// @preconcurrency under Swift 6 strict concurrency; NSSharingServiceDelegate already is.
final class SpikeMenuView: NSView, NSMenuDelegate, @preconcurrency QLPreviewPanelDataSource,
                           @preconcurrency NSSharingServicePickerDelegate, NSSharingServiceDelegate {
    static var current: SpikeMenuView?   // strong: outlives the popover's content, like Task 4's presenter
    var url: URL = URL(fileURLWithPath: "/Applications/Safari.app")
    private var picker: NSSharingServicePicker?

    override func hitTest(_ point: NSPoint) -> NSView? {
        guard let e = NSApp.currentEvent else { return nil }
        let secondary = e.type == .rightMouseDown || e.type == .rightMouseUp
            || ((e.type == .leftMouseDown || e.type == .leftMouseUp) && e.modifierFlags.contains(.control))
        return secondary ? super.hitTest(point) : nil
    }
    override func menu(for event: NSEvent) -> NSMenu? { buildMenu() }
    override func mouseDown(with event: NSEvent) {
        NSMenu.popUpContextMenu(buildMenu(), with: event, for: self)
    }

    private func buildMenu() -> NSMenu {
        let m = NSMenu(); m.autoenablesItems = false; m.delegate = self
        for (title, sel) in [("Open", #selector(open)), ("Get Info", #selector(getInfo)),
                             ("Quick Look", #selector(quickLook))] {
            let i = NSMenuItem(title: title, action: sel, keyEquivalent: ""); i.target = self; m.addItem(i)
        }
        let p = NSSharingServicePicker(items: [url as NSURL]); p.delegate = self; picker = p
        m.addItem(p.standardShareMenuItem)
        let quit = NSMenuItem(title: "Quit", action: #selector(open), keyEquivalent: ""); quit.target = self
        let force = NSMenuItem(title: "Force Quit", action: #selector(open), keyEquivalent: "")
        force.target = self; force.isAlternate = true; force.keyEquivalentModifierMask = .option
        m.addItem(quit); m.addItem(force)
        return m
    }
    func menuWillOpen(_ menu: NSMenu) { DiagnosticsLog.shared.log("spike", "menuWillOpen") }
    func menuDidClose(_ menu: NSMenu) { DiagnosticsLog.shared.log("spike", "menuDidClose") }

    @objc private func open() { DiagnosticsLog.shared.log("spike", "action fired") }
    @objc private func getInfo() {
        let pb = NSPasteboard(name: NSPasteboard.Name("com.docktile.getinfo"))
        pb.clearContents(); pb.writeObjects([url as NSURL])
        DiagnosticsLog.shared.log("spike", "NSPerformService → \(NSPerformService("Finder/Show Info", pb))")
    }
    @objc private func quickLook() {
        // Supported path: never set dataSource here. The panel finds HelperAppDelegate (below) up
        // the chain of responding objects, and its beginPreviewPanelControl hands over the data source.
        Self.current = self
        QLPreviewPanel.shared()?.makeKeyAndOrderFront(nil)
        NotificationCenter.default.post(name: .dismissLauncher, object: nil)
    }
    func numberOfPreviewItems(in panel: QLPreviewPanel!) -> Int { 1 }
    func previewPanel(_ panel: QLPreviewPanel!, previewItemAt index: Int) -> QLPreviewItem! { url as NSURL }

    func sharingServicePicker(_ p: NSSharingServicePicker, delegateFor s: NSSharingService) -> NSSharingServiceDelegate? { self }
    func sharingServicePicker(_ p: NSSharingServicePicker, didChoose s: NSSharingService?) {
        DiagnosticsLog.shared.log("spike", "share didChoose \(s?.title ?? "nil (cancel)")")
    }
    func sharingService(_ s: NSSharingService, didShareItems items: [Any]) { DiagnosticsLog.shared.log("spike", "share done") }
    func sharingService(_ s: NSSharingService, didFailToShareItems items: [Any], error: Error) {
        DiagnosticsLog.shared.log("spike", "share failed \(error.localizedDescription)")
    }
}

struct SpikeMenuBridge: NSViewRepresentable {
    let path: String?
    func makeNSView(context: Context) -> SpikeMenuView { let v = SpikeMenuView(); if let path { v.url = URL(fileURLWithPath: path) }; return v }
    func updateNSView(_ v: SpikeMenuView, context: Context) {}
}
```

Then in `StackAppItem.body`, directly after `.onHover { isHovered = $0 }`, add:

```swift
.overlay(SpikeMenuBridge(path: app.isFolder ? app.folderPath : AppInstallChecker.resolve(app).resolvedPath))
```

And in `HelperAppDelegate` (add `import Quartz` at the top of that file), the Quick Look panel controller.
These are informal-protocol methods on `NSObject` (nonisolated), so under Swift 6 they are overridden
`nonisolated` and hop with `MainActor.assumeIsolated` (QL calls them on the main thread):

```swift
    // SPIKE — Quick Look panel controller.
    nonisolated override func acceptsPreviewPanelControl(_ panel: QLPreviewPanel!) -> Bool { true }
    // `panel` is not captured: sending a nonisolated parameter into a main-actor closure fails Swift 6.
    nonisolated override func beginPreviewPanelControl(_ panel: QLPreviewPanel!) {
        MainActor.assumeIsolated { QLPreviewPanel.shared()?.dataSource = SpikeMenuView.current }
    }
    nonisolated override func endPreviewPanelControl(_ panel: QLPreviewPanel!) {
        MainActor.assumeIsolated { QLPreviewPanel.shared()?.dataSource = nil }
    }
```

- [ ] **Step 3: Build signed, refresh a dev tile, verify signature**

```bash
xcodebuild -project DockTile.xcodeproj -scheme DockTile -configuration Debug build
codesign --verify "$HOME/Library/Developer/Xcode/DerivedData/DockTile-<hash>/Build/Products/Debug/Dock Tile Dev.app" || echo "UNSIGNED — do not launch"
```

Launch the dev app and open a **Grid** dev tile that contains at least one app that is running (for
example Brave), one that is not running, and one folder. Click **Update** so the helper is rebuilt from
this build (the helper is a copy of the main app; see the "Debug binary is a stub" rule).

- [ ] **Step 4: Run the checklist and record every result** in the "Spike Results" section at the bottom of this plan (PASS/FAIL plus a one-line note)

| ID | Check | Gate |
|---|---|---|
| S1 | Right-click a cell: menu appears at the pointer; popover stays open. | **Hard**: fail → stop, re-plan with Karthik |
| S2 | Control-click a cell: menu appears; the app does **not** launch. | **Hard** |
| S3 | Left-click still launches; hover highlight still tracks; scroll wheel scrolls a long grid; arrow keys + Return still work after Cmd+Tab activation. | **Hard** |
| S4 | Esc or a click outside the menu closes only the menu; popover stays. Clicking a menu item does not trigger the click-outside monitor (the `spike action fired` log line appears before any close). | **Hard** |
| S5 | Get Info (app **and** folder): Finder's info window opens; **no** Automation/TCC prompt; `NSPerformService → true` logged. Note whether the popover closed when Finder came forward. Test in Ghost mode and App mode. | Fail → drop Get Info (Task 6) |
| S6 | Quick Look (controller path): panel appears and stays after the popover closes; Space/Esc dismisses it; a second Quick Look from a new popover works; Console shows no "not controlling the panel" complaint. | Fail → drop Quick Look (Task 6). The supported controller path is the only one tried. |
| S7 | Share submenu lists services; picking one (e.g. Messages / Notes) opens its UI; `didChoose` + `share done` logged; cancelling logs `nil (cancel)`; popover still open after cancel. Record (do not gate on) whether the popover survives clicking into the service UI. Closing there is accepted (D4). | Fail (no services listed, or service UI never appears) → **stop and ask Karthik** |
| S8 | Holding ⌥ with the menu open swaps Quit → Force Quit. | Fail → ship Quit only; record it in Task 7 docs |
| S9 | `menuWillOpen` / `menuDidClose` both log; note the order of `menuDidClose` vs `action fired`. | Informational (Task 4 relies on `menuDidClose` firing) |

- [ ] **Step 5: Discard the spike.** The spike edits are uncommitted, and `git switch` would carry them onto the feature branch, so restore them first:

```bash
git restore DockTile/UI/NativePopoverViews.swift DockTile/App/HelperAppDelegate.swift
git diff --stat
git switch -c feat/popover-item-menu main
git branch -D spike/popover-item-menu
```
Expected after `git diff --stat`: nothing tracked is modified (the plan file is untracked until committed below).

Commit only the plan file with the recorded results:

```bash
git add docs/superpowers/plans/2026-10-03-popover-item-context-menu.md
git commit -m "docs(plan): popover item menu — spike results"
```

---

### Task 2: Pure seams + new file registration (TDD)

**Files:**
- Create: `DockTile/UI/PopoverItemMenu.swift`
- Modify: `DockTile.xcodeproj/project.pbxproj`
- Test: `DockTileTests/Unit/UI/PopoverItemMenuTests.swift`

**Interfaces:**
- Produces:
  - `enum PopoverItemAction: String, CaseIterable, Sendable { open, reveal, getInfo = "get_info", quickLook = "quick_look", share, hide, quit, forceQuit = "force_quit" }`
  - `enum PopoverItemRunState: Equatable, Sendable { case notRunning; case running(isHidden: Bool) }`
  - `enum PopoverItemMenuEntry: Hashable, Sendable { case action(PopoverItemAction); case alternate(PopoverItemAction); case separator }`
  - `enum PopoverItemMenu` with
    `nonisolated static func entries(isFolder: Bool, isMissing: Bool, runState: PopoverItemRunState, includesGetInfo: Bool) -> [PopoverItemMenuEntry]`,
    `nonisolated static func dismissesPopover(after: PopoverItemAction) -> Bool`,
    `nonisolated static func runningMatchIndex(resolvedPath: String, runningBundlePaths: [String?]) -> Int?`,
    `nonisolated static func claimsEvent(type: NSEvent.EventType, modifiers: NSEvent.ModifierFlags) -> Bool`

- [ ] **Step 1: Write the failing tests** (`DockTileTests/Unit/UI/PopoverItemMenuTests.swift`)

```swift
import AppKit
import Testing
@testable import Dock_Tile

@Suite("PopoverItemMenu seams")
struct PopoverItemMenuTests {

    // MARK: entries

    @Test("Not-running app: Open only")
    func appNotRunning() {
        #expect(PopoverItemMenu.entries(isFolder: false, isMissing: false, runState: .notRunning, includesGetInfo: true) == [
            .action(.open),
        ])
    }

    @Test("Running, visible app: Open, then Hide and Quit with a Force Quit alternate")
    func appRunningVisible() {
        #expect(PopoverItemMenu.entries(isFolder: false, isMissing: false, runState: .running(isHidden: false), includesGetInfo: true) == [
            .action(.open), .separator,
            .action(.hide), .action(.quit), .alternate(.forceQuit),
        ])
    }

    @Test("Running but hidden app: no Hide row (Review Focus 2)")
    func appRunningHidden() {
        #expect(PopoverItemMenu.entries(isFolder: false, isMissing: false, runState: .running(isHidden: true), includesGetInfo: true) == [
            .action(.open), .separator,
            .action(.quit), .alternate(.forceQuit),
        ])
    }

    @Test("Apps never get an item that hands the bundle to another process (App Management, Review Focus 6)")
    func appsNeverHandOffTheBundle() {
        let handOffs: Set<PopoverItemMenuEntry> = [.action(.reveal), .action(.getInfo), .action(.quickLook), .action(.share)]
        for state in [PopoverItemRunState.notRunning, .running(isHidden: false), .running(isHidden: true)] {
            for info in [false, true] {
                let entries = PopoverItemMenu.entries(isFolder: false, isMissing: false, runState: state, includesGetInfo: info)
                #expect(handOffs.isDisjoint(with: entries), "app menu for \(state), getInfo=\(info): \(entries)")
            }
        }
    }

    @Test("Folder: the full set, and never running rows even if a run state is passed")
    func folder() {
        #expect(PopoverItemMenu.entries(isFolder: true, isMissing: false, runState: .running(isHidden: false), includesGetInfo: true) == [
            .action(.open), .separator,
            .action(.reveal), .action(.getInfo), .action(.quickLook), .separator,
            .action(.share),
        ])
    }

    @Test("Missing item: no menu at all (D7, Review Focus 4)")
    func missing() {
        #expect(PopoverItemMenu.entries(isFolder: false, isMissing: true, runState: .running(isHidden: false), includesGetInfo: true).isEmpty)
        #expect(PopoverItemMenu.entries(isFolder: true, isMissing: true, runState: .notRunning, includesGetInfo: true).isEmpty)
    }

    @Test("Folder Get Info is omitted when not available (macOS 15, D2)")
    func noGetInfo() {
        #expect(PopoverItemMenu.entries(isFolder: true, isMissing: false, runState: .notRunning, includesGetInfo: false) == [
            .action(.open), .separator,
            .action(.reveal), .action(.quickLook), .separator,
            .action(.share),
        ])
    }

    @Test("Never starts or ends with a separator, never two in a row")
    func separatorHygiene() {
        for folder in [false, true] {
            for state in [PopoverItemRunState.notRunning, .running(isHidden: false), .running(isHidden: true)] {
                for info in [false, true] {
                    let e = PopoverItemMenu.entries(isFolder: folder, isMissing: false, runState: state, includesGetInfo: info)
                    #expect(e.first != .separator)
                    #expect(e.last != .separator)
                    #expect(!zip(e, e.dropFirst()).contains { $0 == .separator && $1 == .separator })
                }
            }
        }
    }

    // MARK: dismissal (D4)

    @Test("Only Share and Get Info keep the popover open")
    func dismissal() {
        let keepsOpen = PopoverItemAction.allCases.filter { !PopoverItemMenu.dismissesPopover(after: $0) }
        #expect(Set(keepsOpen) == [.share, .getInfo])
    }

    // MARK: running-app matching (Review Focus 1)

    @Test("Matches the running copy at THIS item's path, not the first with the bundle id")
    func matchesByPath() {
        let index = PopoverItemMenu.runningMatchIndex(
            resolvedPath: "/Users/k/Applications/Chrome Apps.localized/Gmail.app",
            runningBundlePaths: ["/Users/k/Applications/Chrome Apps.localized/Calendar.app",
                                 "/Users/k/Applications/Chrome Apps.localized/Gmail.app"])
        #expect(index == 1)
    }

    @Test("Path comparison ignores a trailing slash and ./ segments")
    func matchesStandardized() {
        #expect(PopoverItemMenu.runningMatchIndex(resolvedPath: "/Applications/Brave Browser.app/",
                                                  runningBundlePaths: [nil, "/Applications/./Brave Browser.app"]) == 1)
    }

    @Test("No path match → not running, even when bundle ids would match")
    func noMatch() {
        #expect(PopoverItemMenu.runningMatchIndex(resolvedPath: "/Applications/Brave Browser.app",
                                                  runningBundlePaths: ["/Applications/Brave Browser Beta.app", nil]) == nil)
    }

    // MARK: event claiming (Review Focus 3 + 5)

    @Test("Overlay claims right-clicks and Control-clicks only")
    func claims() {
        #expect(PopoverItemMenu.claimsEvent(type: .rightMouseDown, modifiers: []))
        #expect(PopoverItemMenu.claimsEvent(type: .rightMouseUp, modifiers: []))
        #expect(PopoverItemMenu.claimsEvent(type: .leftMouseDown, modifiers: .control))
        #expect(PopoverItemMenu.claimsEvent(type: .leftMouseUp, modifiers: .control))
    }

    @Test("Overlay lets plain clicks, hover, drags and scrolling through")
    func passesThrough() {
        #expect(!PopoverItemMenu.claimsEvent(type: .leftMouseDown, modifiers: []))
        #expect(!PopoverItemMenu.claimsEvent(type: .leftMouseDown, modifiers: .command))
        #expect(!PopoverItemMenu.claimsEvent(type: .mouseMoved, modifiers: .control))
        #expect(!PopoverItemMenu.claimsEvent(type: .scrollWheel, modifiers: []))
        #expect(!PopoverItemMenu.claimsEvent(type: .leftMouseDragged, modifiers: []))
    }

    @Test("Analytics action values are Firebase-safe snake_case")
    func actionRawValues() {
        #expect(PopoverItemAction.allCases.map(\.rawValue) ==
                ["open", "reveal", "get_info", "quick_look", "share", "hide", "quit", "force_quit"])
    }
}
```

- [ ] **Step 2: Run to verify it fails**

```bash
xcodebuild test -project DockTile.xcodeproj -scheme DockTile -configuration Debug \
  -destination 'platform=macOS' -only-testing:DockTileTests/PopoverItemMenuTests CODE_SIGNING_ALLOWED=NO
```
Expected: build failure, `cannot find 'PopoverItemMenu' in scope`.

- [ ] **Step 3: Create `DockTile/UI/PopoverItemMenu.swift` with the seams**

```swift
//
//  PopoverItemMenu.swift
//  DockTile
//
//  Right-click / Control-click context menu for apps and folders in the shipped tile popover
//  (issue #17). Finder's own context menu cannot be borrowed through any public API, so this
//  builds a Spotlight-style menu from public AppKit pieces. The decisions live in the pure seams
//  below; the AppKit plumbing follows.
//  Swift 6 - Strict Concurrency
//

import AppKit
import Quartz
import SwiftUI

/// One thing the item menu can do. The raw value is the `action` param of `popover_item_action`.
enum PopoverItemAction: String, CaseIterable, Sendable {
    case open
    case reveal
    case getInfo = "get_info"
    case quickLook = "quick_look"
    case share
    case hide
    case quit
    case forceQuit = "force_quit"
}

/// Whether the item's app is running, read at the moment of the click (never cached).
enum PopoverItemRunState: Equatable, Sendable {
    case notRunning
    case running(isHidden: Bool)
}

enum PopoverItemMenuEntry: Hashable, Sendable {
    case action(PopoverItemAction)
    /// Replaces the entry before it while ⌥ is held (`NSMenuItem.isAlternate`).
    case alternate(PopoverItemAction)
    case separator
}

enum PopoverItemMenu {

    /// The menu for one item. Missing items get none (nothing on disk to act on). Unavailable
    /// items are omitted, not dimmed (HIG).
    ///
    /// Apps never get Show in Finder / Get Info / Quick Look / Share (critical): handing a
    /// third-party app bundle to another process from a helper makes macOS show "<tile> was
    /// prevented from modifying apps on your Mac" (App Management), and a helper can't hold that
    /// permission. Folders aren't app bundles, so they keep the full set and never get
    /// running-app rows.
    nonisolated static func entries(
        isFolder: Bool, isMissing: Bool, runState: PopoverItemRunState, includesGetInfo: Bool
    ) -> [PopoverItemMenuEntry] {
        guard !isMissing else { return [] }
        var entries: [PopoverItemMenuEntry] = [.action(.open)]
        if isFolder {
            entries += [.separator, .action(.reveal)]
            if includesGetInfo { entries.append(.action(.getInfo)) }
            entries += [.action(.quickLook), .separator, .action(.share)]
        } else if case .running(let isHidden) = runState {
            entries.append(.separator)
            if !isHidden { entries.append(.action(.hide)) }
            entries += [.action(.quit), .alternate(.forceQuit)]
        }
        return entries
    }

    /// Share keeps the popover as the share UI's anchor until sharing ends. Get Info never closes
    /// it from our side (macOS may, when Finder comes forward). Every other action closes it, like
    /// a click-to-launch.
    nonisolated static func dismissesPopover(after action: PopoverItemAction) -> Bool {
        switch action {
        case .share, .getInfo: return false
        default: return true
        }
    }

    /// Which running process is THIS item. Matched by bundle path, never by bundle id alone: PWAs
    /// and side-by-side installs share an id, and Quit must not hit the wrong copy.
    nonisolated static func runningMatchIndex(resolvedPath: String, runningBundlePaths: [String?]) -> Int? {
        let target = standardized(resolvedPath)
        return runningBundlePaths.firstIndex { $0.map(standardized) == target }
    }

    /// Does the overlay take this event? Only secondary clicks. Everything else (left-click, hover,
    /// drag, scroll) must fall through to SwiftUI, or the cell stops launching and scrolling.
    nonisolated static func claimsEvent(type: NSEvent.EventType, modifiers: NSEvent.ModifierFlags) -> Bool {
        switch type {
        case .rightMouseDown, .rightMouseUp: return true
        case .leftMouseDown, .leftMouseUp: return modifiers.contains(.control)
        default: return false
        }
    }

    private nonisolated static func standardized(_ path: String) -> String {
        URL(fileURLWithPath: path).standardizedFileURL.path
    }
}
```

- [ ] **Step 4: Register the file in `project.pbxproj`** (textual edits; IDs `AA0900`/`AA0901` are unused, verified with `grep -c "AA09[0-9][0-9] "` → 0)

1. In `/* Begin PBXBuildFile section */`, next to the `AA0020 /* FloatingPanel.swift in Sources */` line, add:
   `		AA0900 /* PopoverItemMenu.swift in Sources */ = {isa = PBXBuildFile; fileRef = AA0901 /* PopoverItemMenu.swift */; };`
2. In `/* Begin PBXFileReference section */`, next to `AA0021 /* FloatingPanel.swift */ = …`, add:
   `		AA0901 /* PopoverItemMenu.swift */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = PopoverItemMenu.swift; sourceTree = "<group>"; };`
3. In group `AA000E /* UI */` children, after `AANPV02 /* NativePopoverViews.swift */,` add `				AA0901 /* PopoverItemMenu.swift */,`
4. In the app target's Sources build phase, after `AA0020 /* FloatingPanel.swift in Sources */,` add `				AA0900 /* PopoverItemMenu.swift in Sources */,`

- [ ] **Step 5: Run the tests to verify they pass**

Same command as Step 2. Expected: all `PopoverItemMenuTests` pass.

- [ ] **Step 6: Commit**

```bash
git add DockTile/UI/PopoverItemMenu.swift DockTile.xcodeproj/project.pbxproj DockTileTests/Unit/UI/PopoverItemMenuTests.swift
git commit -m "feat(popover): item-menu decision seams (issue #17)"
```

---

### Task 3: Strings + analytics event

**Files:**
- Modify: `DockTile/Constants/AppStrings.swift` (new `enum ItemMenu` after `enum Menu`)
- Modify: `DockTile/Resources/Localizable.xcstrings`
- Modify: `DockTile/Managers/AnalyticsService.swift:28-52`
- Test: `DockTileTests/Unit/Constants/AppStringsTests.swift`

**Interfaces:**
- Produces: `AppStrings.ItemMenu.open`, `.showInFinder`, `.getInfo`, `.quickLook`, `.hide`, `.quit`, `.forceQuit` (all `String`); `AnalyticsEvent.popoverItemAction` (`"popover_item_action"`). Share has no string of its own: `standardShareMenuItem` carries the system-localised "Share…" title.

- [ ] **Step 1: Write the failing test.** In `AppStringsTests.swift`, inside the "All AppStrings keys return non-empty values" test next to line 104 (`AppStrings.Menu.openInFinder`), add:

```swift
        #expect(AppStrings.ItemMenu.open == "Open")
        #expect(AppStrings.ItemMenu.showInFinder == "Show in Finder")
        #expect(AppStrings.ItemMenu.getInfo == "Get Info")
        #expect(AppStrings.ItemMenu.quickLook == "Quick Look")
        #expect(AppStrings.ItemMenu.hide == "Hide")
        #expect(AppStrings.ItemMenu.quit == "Quit")
        #expect(AppStrings.ItemMenu.forceQuit == "Force Quit")
```

The existing `AnalyticsEventNamingTests` (in `AnalyticsServiceTests.swift`) cover the new event automatically (`CaseIterable`).

- [ ] **Step 2: Run to verify it fails**

```bash
xcodebuild test -project DockTile.xcodeproj -scheme DockTile -configuration Debug \
  -destination 'platform=macOS' -only-testing:DockTileTests/AppStringsTests CODE_SIGNING_ALLOWED=NO
```
Expected: `type 'AppStrings' has no member 'ItemMenu'`.

- [ ] **Step 3: Add the accessors** (`AppStrings.swift`, a new sibling enum directly after `enum Menu { … }` closes)

```swift
    // MARK: - Popover Item Menu (right-click on an app/folder in a tile's popover)

    enum ItemMenu {
        static let open = NSLocalizedString("itemMenu.open", value: "Open",
            comment: "Popover item context menu: open the app or folder")
        static let showInFinder = NSLocalizedString("itemMenu.showInFinder", value: "Show in Finder",
            comment: "Popover item context menu: reveal the item in Finder")
        static let getInfo = NSLocalizedString("itemMenu.getInfo", value: "Get Info",
            comment: "Popover item context menu: open Finder's Get Info window")
        static let quickLook = NSLocalizedString("itemMenu.quickLook", value: "Quick Look",
            comment: "Popover item context menu: preview the item with Quick Look")
        static let hide = NSLocalizedString("itemMenu.hide", value: "Hide",
            comment: "Popover item context menu: hide the running app")
        static let quit = NSLocalizedString("itemMenu.quit", value: "Quit",
            comment: "Popover item context menu: quit the running app")
        static let forceQuit = NSLocalizedString("itemMenu.forceQuit", value: "Force Quit",
            comment: "Popover item context menu: force quit (shown while Option is held)")
    }
```

- [ ] **Step 4: Insert the catalog entries textually.** In `Localizable.xcstrings`, insert seven key blocks immediately **before** the `"menu.configure"` key (anchor by text, not by line number). Each block copies the exact shape of `"menu.openInFinder"` (comment, `"extractionState": "manual"`, `en-AU` / `en-GB` / `en-US` `stringUnit`s with `"state": "translated"` and the same value). Example for one key:

```json
    "itemMenu.open": {
      "comment": "Popover item context menu: open the app or folder",
      "extractionState": "manual",
      "localizations": {
        "en-AU": { "stringUnit": { "state": "translated", "value": "Open" } },
        "en-GB": { "stringUnit": { "state": "translated", "value": "Open" } },
        "en-US": { "stringUnit": { "state": "translated", "value": "Open" } }
      }
    },
```

…but expanded to the file's multi-line indentation exactly as `"menu.openInFinder"` is laid out at line 1540. Keys and values: `itemMenu.open` Open · `itemMenu.showInFinder` Show in Finder · `itemMenu.getInfo` Get Info · `itemMenu.quickLook` Quick Look · `itemMenu.hide` Hide · `itemMenu.quit` Quit · `itemMenu.forceQuit` Force Quit. Then validate:

```bash
python3 -c "import json; json.load(open('DockTile/Resources/Localizable.xcstrings')); print('ok')"
git diff --stat DockTile/Resources/Localizable.xcstrings
```
Expected: `ok`, and the diff shows only insertions (≈168 lines added, 0 removed).

- [ ] **Step 5: Add the analytics event** (`AnalyticsService.swift`, after `case appLaunchedFromTile = "app_launched_from_tile"`)

```swift
    case popoverItemAction = "popover_item_action"
```

- [ ] **Step 6: Run the tests to verify they pass**

```bash
xcodebuild test -project DockTile.xcodeproj -scheme DockTile -configuration Debug \
  -destination 'platform=macOS' -only-testing:DockTileTests/AppStringsTests -only-testing:DockTileTests/AnalyticsEventNamingTests CODE_SIGNING_ALLOWED=NO
```
Expected: PASS.

- [ ] **Step 7: Commit**

```bash
git add DockTile/Constants/AppStrings.swift DockTile/Resources/Localizable.xcstrings DockTile/Managers/AnalyticsService.swift DockTileTests/Unit/Constants/AppStringsTests.swift
git commit -m "feat(popover): item-menu strings and popover_item_action event"
```

---

### Task 4: AppKit plumbing: overlay view, controller, Quick Look, SwiftUI bridge

**Files:**
- Modify: `DockTile/UI/PopoverItemMenu.swift` (append)
- Modify: `DockTile/App/HelperAppDelegate.swift` (Quick Look panel controller)
- Modify: `DockTile/Utilities/AppLauncher.swift:15-16` (`source` parameter)

**Interfaces:**
- Consumes: Task 2 seams; Task 3 strings + event; `AppInstallChecker.resolve(_:) -> Resolution` (`status`, `resolvedPath`); `AppLauncher.launch(_:)`; `Notification.Name.dismissLauncher`; `DiagnosticsLog.shared.ui(_:)` / `.log(_:_:)`.
- Produces:
  - `struct PopoverItemMenuHooks { let onOpen: (AppItem) -> Void; let onClose: () -> Void }`
  - `extension View { func itemContextMenu(_ hooks: PopoverItemMenuHooks?, app: AppItem, anchor: PopoverItemMenuAnchor) -> some View }` (returns `self` unchanged when `hooks == nil`)
  - `@MainActor final class PopoverItemMenuAnchor` (cells hold one in `@State`)

Untestable by unit tests (real NSMenu / NSWorkspace / QLPreviewPanel). Correctness comes from the Task 2 seams plus the Task 5 hands-on gate.

- [ ] **Step 1: Append the overlay view**

```swift
// MARK: - Overlay view (claims secondary clicks only)

/// Transparent view over a popover cell. `hitTest` answers only for secondary clicks (see
/// `PopoverItemMenu.claimsEvent`), so left-click launch, hover, drag and scroll reach SwiftUI.
/// The menu is built per click, so running state and install status are live.
final class PopoverItemMenuView: NSView {
    var makeController: () -> PopoverItemMenuController? = { nil }
    /// Keeps the controller alive while its menu is up (NSMenu holds targets/delegates weakly).
    private var activeController: PopoverItemMenuController?

    override func hitTest(_ point: NSPoint) -> NSView? {
        guard let event = NSApp.currentEvent,
              PopoverItemMenu.claimsEvent(type: event.type, modifiers: event.modifierFlags) else { return nil }
        return super.hitTest(point)
    }

    override func menu(for event: NSEvent) -> NSMenu? { freshMenu() }

    /// Control-click arrives as a left mouse-down (claimed only when ⌃ is held).
    override func mouseDown(with event: NSEvent) {
        guard let menu = freshMenu() else { return }
        NSMenu.popUpContextMenu(menu, with: event, for: self)
    }

    /// VoiceOver "Show Menu": no mouse event, so pop up at the cell's centre.
    func popUpAtCenter() {
        guard let menu = freshMenu() else { return }
        menu.popUp(positioning: nil, at: NSPoint(x: bounds.midX, y: bounds.midY), in: self)
    }

    private func freshMenu() -> NSMenu? {
        activeController = makeController()
        return activeController?.buildMenu()
    }
}

/// Lets a cell's VoiceOver action reach its overlay view without a mouse event.
@MainActor
final class PopoverItemMenuAnchor {
    weak var view: PopoverItemMenuView?
    func showMenu() { view?.popUpAtCenter() }
}
```

- [ ] **Step 2: Append the controller**

```swift
// MARK: - Controller (one per opened menu)

@MainActor
final class PopoverItemMenuController: NSObject, NSMenuDelegate, NSSharingServiceDelegate {
    private let app: AppItem
    private let url: URL
    private let runningApp: NSRunningApplication?
    private let onOpen: () -> Void
    private let onClose: () -> Void
    private var sharePicker: NSSharingServicePicker?
    private var shareItem: NSMenuItem?
    /// Share outlives the menu: the picker's service runs after `menuDidClose`, and its delegate is
    /// weak. Held here until sharing finishes, fails or is cancelled.
    private static var sharing: PopoverItemMenuController?

    /// Get Info relies on Finder's undocumented "Show Info" service. Offered on macOS 26+ only, by
    /// decision (plan D2); verified hands-on on macOS 27. macOS 15 never shows it.
    private static var includesGetInfo: Bool {
        if #available(macOS 26, *) { return true } else { return false }
    }

    /// nil for a missing item: no menu (D7). Resolved at click time.
    static func make(for app: AppItem, onOpen: @escaping () -> Void, onClose: @escaping () -> Void) -> PopoverItemMenuController? {
        let resolution = AppInstallChecker.resolve(app)
        guard resolution.status == .installed, let path = resolution.resolvedPath else { return nil }
        var runningApp: NSRunningApplication?
        if !app.isFolder {
            let candidates = NSRunningApplication.runningApplications(withBundleIdentifier: app.bundleIdentifier)
                .filter { !$0.isTerminated }
            if let i = PopoverItemMenu.runningMatchIndex(resolvedPath: path,
                                                         runningBundlePaths: candidates.map { $0.bundleURL?.path }) {
                runningApp = candidates[i]
            }
        }
        return PopoverItemMenuController(app: app, url: URL(fileURLWithPath: path),
                                         runningApp: runningApp, onOpen: onOpen, onClose: onClose)
    }

    private init(app: AppItem, url: URL, runningApp: NSRunningApplication?,
                 onOpen: @escaping () -> Void, onClose: @escaping () -> Void) {
        self.app = app; self.url = url; self.runningApp = runningApp
        self.onOpen = onOpen; self.onClose = onClose
    }

    func buildMenu() -> NSMenu {
        let menu = NSMenu()
        menu.autoenablesItems = false
        menu.delegate = self
        let runState: PopoverItemRunState = runningApp.map { .running(isHidden: $0.isHidden) } ?? .notRunning
        for entry in PopoverItemMenu.entries(isFolder: app.isFolder, isMissing: false,
                                             runState: runState, includesGetInfo: Self.includesGetInfo) {
            switch entry {
            case .separator:
                menu.addItem(.separator())
            case .action(.share):
                let picker = NSSharingServicePicker(items: [url as NSURL])
                picker.delegate = self
                sharePicker = picker
                let share = picker.standardShareMenuItem
                shareItem = share
                menu.addItem(share)
            case .action(let action):
                menu.addItem(item(for: action))
            case .alternate(let action):
                let alt = item(for: action)
                alt.isAlternate = true
                alt.keyEquivalentModifierMask = .option
                menu.addItem(alt)
            }
        }
        return menu
    }

    private func item(for action: PopoverItemAction) -> NSMenuItem {
        let item = NSMenuItem(title: title(for: action), action: #selector(performItem(_:)), keyEquivalent: "")
        item.target = self
        item.representedObject = action.rawValue
        return item
    }

    private func title(for action: PopoverItemAction) -> String {
        switch action {
        case .open: AppStrings.ItemMenu.open
        case .reveal: AppStrings.ItemMenu.showInFinder
        case .getInfo: AppStrings.ItemMenu.getInfo
        case .quickLook: AppStrings.ItemMenu.quickLook
        case .share: "" // never built as a plain item: the system share item carries its own title
        case .hide: AppStrings.ItemMenu.hide
        case .quit: AppStrings.ItemMenu.quit
        case .forceQuit: AppStrings.ItemMenu.forceQuit
        }
    }

    @objc private func performItem(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String, let action = PopoverItemAction(rawValue: raw) else { return }
        record(action)
        switch action {
        case .open: AppLauncher.launch(app, source: "item_menu")
        case .reveal: NSWorkspace.shared.activateFileViewerSelecting([url])
        case .getInfo: Self.showFinderInfo(for: url)
        case .quickLook: QuickLookPresenter.shared.preview(url)
        case .share: break
        case .hide: runningApp?.hide()
        case .quit: runningApp?.terminate()
        case .forceQuit: runningApp?.forceTerminate()
        }
        if PopoverItemMenu.dismissesPopover(after: action) {
            NotificationCenter.default.post(name: .dismissLauncher, object: nil)
        }
    }

    private func record(_ action: PopoverItemAction) {
        DiagnosticsLog.shared.ui("Popover item menu → \(action.rawValue) on '\(app.name)'")
        AnalyticsService.shared.log(.popoverItemAction, ["action": action.rawValue, "is_folder": app.isFolder])
    }

    /// Finder's "Show Info" service: no Automation (TCC) prompt, unlike AppleScript. Each helper is
    /// separately ad-hoc signed, so an AppleScript route would prompt per tile and again after every
    /// rebuild. Undocumented service name, hence the logged failure.
    private static func showFinderInfo(for url: URL) {
        let pasteboard = NSPasteboard(name: NSPasteboard.Name("com.docktile.getinfo"))
        pasteboard.clearContents()
        pasteboard.writeObjects([url as NSURL])
        if !NSPerformService("Finder/Show Info", pasteboard) {
            DiagnosticsLog.shared.log("popover", "Get Info service unavailable for \(url.lastPathComponent)")
        }
    }

    // MARK: NSMenuDelegate — drives the target highlight (D10)

    func menuWillOpen(_ menu: NSMenu) {
        // No icon on Share (Karthik). AppKit re-applies the share glyph after the item is created,
        // so clearing it in buildMenu() doesn't stick; here the menu is final (spike S7).
        shareItem?.image = nil
        onOpen()
    }
    func menuDidClose(_ menu: NSMenu) { onClose() }

    // MARK: Share completion (D4: we close the popover only when sharing ends)

    func sharingService(_ sharingService: NSSharingService, didShareItems items: [Any]) { finishSharing() }
    func sharingService(_ sharingService: NSSharingService, didFailToShareItems items: [Any], error: Error) { finishSharing() }

    fileprivate func beginSharing() {
        record(.share)
        Self.sharing = self
    }

    fileprivate func cancelSharing() { Self.sharing = nil }   // popover stays open

    private func finishSharing() {
        Self.sharing = nil
        NotificationCenter.default.post(name: .dismissLauncher, object: nil)
    }
}

/// The picker delegate is NOT main-actor annotated in the SDK (NSSharingService.h:304–316), unlike
/// NSSharingServiceDelegate. Hence @preconcurrency for Swift 6 (AppKit calls it on the main thread).
extension PopoverItemMenuController: @preconcurrency NSSharingServicePickerDelegate {
    func sharingServicePicker(_ picker: NSSharingServicePicker, delegateFor sharingService: NSSharingService) -> NSSharingServiceDelegate? { self }

    func sharingServicePicker(_ picker: NSSharingServicePicker, didChoose service: NSSharingService?) {
        if service == nil { cancelSharing() } else { beginSharing() }
    }
}
```

Add the `source` parameter to `AppLauncher.launch` (`DockTile/Utilities/AppLauncher.swift:15-16`), so a menu Open is not counted as a left-click launch. Existing callers keep the default:

```swift
    /// Launch an app or open a folder for the given AppItem. `source` attributes the launch in
    /// analytics: "popover" for a left-click / Return, "item_menu" for the context menu's Open.
    static func launch(_ app: AppItem, source: String = "popover") {
        AnalyticsService.shared.log(.appLaunchedFromTile, ["source": source, "is_folder": app.isFolder])
```

- [ ] **Step 3: Append the Quick Look presenter**

```swift
// MARK: - Quick Look (D3: outlives the popover)

/// Process-lifetime data source, so the panel keeps its item after the popover's SwiftUI tree is
/// released on close. It never sets the panel's data source itself: QLPreviewPanel takes it from
/// the controller it finds through the app's chain of responding objects (HelperAppDelegate,
/// below). Apple's header says not to modify panel state without controlling it.
@MainActor
final class QuickLookPresenter: NSObject {
    static let shared = QuickLookPresenter()
    private var url: URL?

    func preview(_ url: URL) {
        self.url = url
        guard let panel = QLPreviewPanel.shared() else { return }
        if panel.isVisible { panel.reloadData() } else { panel.makeKeyAndOrderFront(nil) }
    }
}

extension QuickLookPresenter: @preconcurrency QLPreviewPanelDataSource {
    func numberOfPreviewItems(in panel: QLPreviewPanel!) -> Int { url == nil ? 0 : 1 }
    func previewPanel(_ panel: QLPreviewPanel!, previewItemAt index: Int) -> QLPreviewItem! { url as NSURL? }
}
```

Add the panel controller to `HelperAppDelegate` (`DockTile/App/HelperAppDelegate.swift`; add `import Quartz` beside `import AppKit`, and put these methods in the class body). These are informal-protocol methods on `NSObject` (nonisolated), so under Swift 6 they are overridden `nonisolated` and hop with `MainActor.assumeIsolated`. Quick Look calls them on the main thread, which is the same pattern as `FloatingPanel.popoverDidClose`:

```swift
    // MARK: - Quick Look panel control (popover item menu, issue #17)

    /// QLPreviewPanel takes its data source from a controller up the chain of responding objects;
    /// in an accessory helper that is this delegate.
    nonisolated override func acceptsPreviewPanelControl(_ panel: QLPreviewPanel!) -> Bool { true }

    // `panel` is deliberately not captured: sending a nonisolated parameter into a main-actor
    // closure fails Swift 6 strict concurrency. The panel is a singleton, so re-fetch it.
    nonisolated override func beginPreviewPanelControl(_ panel: QLPreviewPanel!) {
        MainActor.assumeIsolated { QLPreviewPanel.shared()?.dataSource = QuickLookPresenter.shared }
    }

    nonisolated override func endPreviewPanelControl(_ panel: QLPreviewPanel!) {
        MainActor.assumeIsolated { QLPreviewPanel.shared()?.dataSource = nil }
    }
```

- [ ] **Step 4: Append the SwiftUI bridge and modifier**

```swift
// MARK: - SwiftUI bridge

/// What a cell needs to host the menu. nil (editor, Settings preview) → no menu at all.
struct PopoverItemMenuHooks {
    let onOpen: (AppItem) -> Void
    let onClose: () -> Void
}

struct PopoverItemMenuBridge: NSViewRepresentable {
    let app: AppItem
    let hooks: PopoverItemMenuHooks
    let anchor: PopoverItemMenuAnchor

    func makeNSView(context: Context) -> PopoverItemMenuView { configure(PopoverItemMenuView()) }
    func updateNSView(_ view: PopoverItemMenuView, context: Context) { _ = configure(view) }

    private func configure(_ view: PopoverItemMenuView) -> PopoverItemMenuView {
        anchor.view = view
        let app = app, hooks = hooks
        view.makeController = {
            PopoverItemMenuController.make(for: app, onOpen: { hooks.onOpen(app) }, onClose: hooks.onClose)
        }
        return view
    }
}

extension View {
    /// The shipped popover's item menu. `hooks == nil` leaves the view tree untouched (same idiom
    /// as `editingOnly`), so the editor and the Settings preview never carry it.
    @ViewBuilder func itemContextMenu(_ hooks: PopoverItemMenuHooks?, app: AppItem,
                                      anchor: PopoverItemMenuAnchor) -> some View {
        if let hooks {
            self
                .overlay(PopoverItemMenuBridge(app: app, hooks: hooks, anchor: anchor).accessibilityHidden(true))
                .accessibilityElement(children: .combine)
                .accessibilityAction(.showMenu) { anchor.showMenu() }
        } else {
            self
        }
    }
}
```

- [ ] **Step 5: Build**

```bash
xcodebuild -project DockTile.xcodeproj -scheme DockTile -configuration Debug build
```
Expected: `** BUILD SUCCEEDED **` with no new warnings in `PopoverItemMenu.swift` or `HelperAppDelegate.swift`. If Swift 6 rejects
`@preconcurrency` on the QL data-source or share-picker conformance, mark those methods `nonisolated` and wrap their
bodies in `MainActor.assumeIsolated { … }`, the same pattern `FloatingPanel.popoverDidClose` uses.

- [ ] **Step 6: Commit**

```bash
git add DockTile/UI/PopoverItemMenu.swift DockTile/App/HelperAppDelegate.swift DockTile/Utilities/AppLauncher.swift
git commit -m "feat(popover): item-menu overlay, actions, Quick Look and share plumbing"
```

---

### Task 5: Wire into Grid and List, with the target highlight; then the hands-on gate

**Files:**
- Modify: `DockTile/UI/NativePopoverViews.swift` (`StackPopoverView` ~287–583, `StackAppItem` ~587–751, `ListPopoverView` ~757–965, `ListAppRow` ~969–1071)

**Interfaces:**
- Consumes: `PopoverItemMenuHooks`, `PopoverItemMenuAnchor`, `View.itemContextMenu(_:app:anchor:)` from Task 4.

- [ ] **Step 1: `StackPopoverView`: track the menu target and build hooks.** Next to `@State private var draggedItem`:

```swift
    /// The cell whose context menu is open — shown with the selection highlight (D10).
    @State private var menuTargetID: AppItem.ID? = nil

    /// Item menu only in the shipped popover: never in the editor or the Settings preview.
    private var itemMenuHooks: PopoverItemMenuHooks? {
        actionsDisabled ? nil : PopoverItemMenuHooks(onOpen: { menuTargetID = $0.id },
                                                      onClose: { menuTargetID = nil })
    }
```

In `gridContent`, change the `StackAppItem(...)` call: `isSelected: selectedIndex == index || menuTargetID == app.id,` and add the argument `itemMenu: itemMenuHooks,` after `editing: editing,`.

- [ ] **Step 2: `StackAppItem`: accept and apply.** Add a property after `var editing: PopoverEditing? = nil`:

```swift
    /// Shipped-popover context menu hooks; nil in the editor and the Settings preview.
    var itemMenu: PopoverItemMenuHooks? = nil
    @State private var menuAnchor = PopoverItemMenuAnchor()
```

In `body`, directly after `.onHover { isHovered = $0 }`, add:

```swift
        .itemContextMenu(itemMenu, app: app, anchor: menuAnchor)
```

- [ ] **Step 3: `ListPopoverView` and `ListAppRow`: same three edits.** In `ListPopoverView` add the identical `menuTargetID` state and `itemMenuHooks` property (copy from Step 1). In the `ListAppRow(...)` call set `isSelected: selectedIndex == index || menuTargetID == app.id,` and add `itemMenu: itemMenuHooks,` after `editing: editing,`. In `ListAppRow` add the same `itemMenu` property and `menuAnchor` state (copy from Step 2) and, directly after `.onHover { hovering in isHovered = hovering }`, add `.itemContextMenu(itemMenu, app: app, anchor: menuAnchor)`. The utility rows (`Configure…`, `Open in Finder`) get no item menu.

- [ ] **Step 4: Run the full unit suite**

```bash
xcodebuild test -project DockTile.xcodeproj -scheme DockTile -configuration Debug \
  -destination 'platform=macOS' -only-testing:DockTileTests CODE_SIGNING_ALLOWED=NO
```
Expected: all pass (editor and preview tests unaffected, because `itemMenu` defaults to nil).

- [ ] **Step 5: Rebuild signed and refresh dev tiles** (tests leave the product unsigned; see driving-the-dev-build.md)

```bash
xcodebuild -project DockTile.xcodeproj -scheme DockTile -configuration Debug build
codesign --verify "$HOME/Library/Developer/Xcode/DerivedData/DockTile-<hash>/Build/Products/Debug/Dock Tile Dev.app" || echo "UNSIGNED — do not launch"
```
Launch the dev app; **Update** one Grid dev tile and one List dev tile. Each tile must contain a running app, a non-running app, a folder, and (if available) an uninstalled app.

- [ ] **Step 6: Hands-on gate (macOS 27). Every row must pass.** Capture screenshots by window ID only (`Scripts/dev-capture.sh`), never by screen rect.

| # | Check (do it in Grid AND List) |
|---|---|
| G1 | Right-click a non-running app → **Open only**. The cell shows the accent highlight while the menu is open; the highlight clears on close. |
| G2 | **Ghost mode and App mode.** Right-click a running app → adds — · Hide · Quit; ⌥ swaps Quit ↔ Force Quit. Hide one, right-click again → no Hide row. Repeat with a running **Safari** (system-volume app) and a running **`/System/Applications` app** (e.g. Calculator): Hide/Quit must appear for both. If they don't, the paths differ in form: change `PopoverItemMenu.standardized` to `URL(fileURLWithPath: path).resolvingSymlinksInPath().standardizedFileURL.path`, re-run Task 2's tests, and repeat this row. |
| G3 | Right-click a folder → Open · — · Show in Finder · Get Info · Quick Look · — · Share, with **no icon on Share** and no running rows. Open opens it in Finder; Show in Finder reveals it in its parent; Get Info opens Finder's Info window; Quick Look shows the folder and stays after the popover closes. |
| G4 | Right-click an uninstalled app (dashed placeholder) → nothing happens. |
| G5 | Control-click → same menu, and the app does **not** launch. Left-click still launches; hover, scroll and arrow-key navigation unchanged. |
| G6 | **Ghost mode and App mode.** Open / Show in Finder / Quick Look / Hide / Quit each close the popover. Share and Get Info (folders) do not close it from our side (macOS closing it when Finder or the share UI takes focus is accepted, D4). Esc on the menu leaves the popover open. |
| G7 | Folder → Share → pick a service → the share completes; the popover is closed afterwards (by us on completion, or earlier by macOS — both accepted). Cancel the picker → popover stays open. |
| G8 | Tile Detail editor still shows only "Remove" on right-click; the Settings → Popover preview shows no menu. |
| G9 | **Ghost mode and App mode.** VoiceOver on, focus a cell, VO-Shift-M → the same menu opens. |
| G10 | Copy Diagnostics shows `ui` lines `Popover item menu → …` for each pick. |
| G11 | Two installs sharing one bundle id (e.g. two Chrome web apps, both running, both in the tile): Quit on one quits **that** one only, and the other stays running. If no such pair is available, record "not tested" in the commit message. Do not mark it passed. |
| G12 | **No App Management checks.** Run every menu action on a folder and every app action (Open, Hide, Quit) on a `/Applications` app, then read macOS's own log for that window: `/usr/bin/log show --start "<t0>" --end "<t1>" --style compact --predicate 'process == "tccd" AND eventMessage CONTAINS "SystemPolicyAppBundles"' > <scratch>.log 2>&1`, and look for an `AUTHREQ_CTX … preflight=no` line or "does not allow prompting for unentitled binaries" whose neighbouring `AUTHREQ_ATTRIBUTION` names a `com.docktile.dev.` helper. Pass = none. The alert itself is not the test: it shows only once per tile identity. |

Any failure → fix in this task and re-run the gate. Do not proceed with a failing row.

- [ ] **Step 6b: Same-session performance A/B** (performance-measurement.md: same session, same tile, same Mac, minutes apart; record build kind = Debug)

Use the largest dev tile available (record its app count). **A** = helper built from `main` (Update the tile from a `main` Debug build), **B** = this branch (Update again). For each build:
1. Quit the helper, relaunch it, click the tile once and read the first-open time from the `✔ Show popover (Nms)` diagnostics line.
2. Open and close the popover 10 times, then run `footprint <helper pid>` after opens 1, 5 and 10.

Pass: B's first-open time is within noise of A's, and B's footprint is flat across opens 6–10 (the A/B difference stays constant, not growing). Record both builds' numbers in the commit message. A growing B footprint is a defect: find the retained objects with `leaks --outputGraph` / `heap --diffFrom` before theorising.

- [ ] **Step 7: Commit**

```bash
git add DockTile/UI/NativePopoverViews.swift
git commit -m "feat(popover): native-style item context menu in Grid and List (issue #17)"
```

---

### Task 6: Apply the spike outcomes (only if S5, S6 or S8 failed)

**Superseded (2026-10-10): skip.** S8 passed. S5 and S6 failed for *apps* only, and D1 was revised
instead: Get Info and Quick Look stay, folder-only, through the Task 2 seam. Nothing below is executed;
it is kept for the record.

Skip this task entirely if the Task 1 results show S5, S6 and S8 all PASS.

**Files:** `DockTile/UI/PopoverItemMenu.swift`, `DockTileTests/Unit/UI/PopoverItemMenuTests.swift`, `DockTile/Constants/AppStrings.swift`, `Localizable.xcstrings`, `AppStringsTests.swift`

- [ ] **If S5 (Get Info) failed:** delete `case getInfo` from `PopoverItemAction`, the `includesGetInfo` parameter from `entries` (and its `if`), `includesGetInfo` + `showFinderInfo` from the controller, `.getInfo` from `dismissesPopover` (it becomes `case .share: return false`), `AppStrings.ItemMenu.getInfo`, its catalog block and its test line. Update the tests: remove `.action(.getInfo)` from every expected array, delete `noGetInfo`, change the `separatorHygiene` loop to drop the `info` axis, `dismissal` expects `[.share]`, `actionRawValues` drops `"get_info"`.
- [ ] **If S6 (Quick Look) failed:** delete `case quickLook`, its entry in `entries`, its `perform` branch, `QuickLookPresenter`, the `import Quartz` in both files, the three `…PreviewPanelControl` methods in `HelperAppDelegate`, `AppStrings.ItemMenu.quickLook`, its catalog block and its test line; remove `.action(.quickLook)` from every expected array and `"quick_look"` from `actionRawValues`.
- [ ] **If S8 (⌥ Force Quit) failed:** delete `case alternate` and `case forceQuit`, the `.alternate(.forceQuit)` entry, its `buildMenu` branch and `perform` branch, `AppStrings.ItemMenu.forceQuit`, its catalog block and its test line; remove `.alternate(.forceQuit)` from expected arrays and `"force_quit"` from `actionRawValues`.
- [ ] Run the full suite (Task 5 Step 4 command), re-run gate rows G1–G3 and G6 for the affected layout, and commit: `git commit -m "feat(popover): drop <item> from item menu — failed spike <S#>"`.

---

### Task 7: Documentation + gates

**Files:**
- Modify: `.claude/rules/architecture.md` (new section after "Popover Configure Gear Icon")
- Modify: `.claude/rules/testing.md` (seam list)

- [ ] **Step 1: Add the architecture section**

```markdown
## Popover Item Context Menu (issue #17)

Right-click / Control-click on an app or folder in the SHIPPED popover shows a native context menu
([PopoverItemMenu.swift](../../DockTile/UI/PopoverItemMenu.swift)). Finder's own context menu cannot be
obtained through any public API (Spotlight, Raycast and Alfred all build curated menus), so this is
built from public AppKit pieces.

- **Apps never get Show in Finder / Get Info / Quick Look / Share (critical, App Management)**: handing
  a third-party app bundle (`/Applications`) to Finder, Quick Look, a share service or even
  `/usr/bin/open -R` from a helper makes macOS check `kTCCServiceSystemPolicyAppBundles` for the helper,
  refuse ("does not allow prompting for unentitled binaries"), and show "*<tile>* was prevented from
  modifying apps on your Mac", once per tile identity. Verified 2026-10-05; re-signing a helper with
  Developer ID did not help. Launching (`openApplication`) never triggers it, nor do folders or apps on
  the read-only system volume. Enforced by `entries` + `appsNeverHandOffTheBundle`. Prove a change
  against tccd's log, never by watching for the alert, which shows only once per identity.

- **Built at click time, AppKit `NSMenu`, not SwiftUI `.contextMenu` (critical)**: a transparent overlay
  `NSView` claims only secondary clicks (`PopoverItemMenu.claimsEvent`); left-click, hover, drag and
  scroll fall through to SwiftUI. Building per click keeps install status and running state live and
  enables the ⌥ Force Quit alternate and the system Share submenu.
- **Composition** = pure seam `PopoverItemMenu.entries`. Folder: Open · Show in Finder · Get Info
  (macOS 26+ only) · Quick Look · Share (no icon; AppKit re-applies it, so it is cleared in
  `menuWillOpen`). App: Open, then Hide (omitted when hidden) · Quit/⌥Force Quit when running.
  Missing items get **no menu**. No tile-level items.
- **Running app = matched by bundle PATH, never bundle id alone** (`runningMatchIndex`): PWAs and
  side-by-side installs share an id.
- **Get Info = Finder's "Show Info" service via `NSPerformService`, never AppleScript (critical)**: each
  helper is separately ad-hoc signed, so Automation consent would prompt per tile and re-prompt after
  every rebuild.
- **Dismissal** (`dismissesPopover`): every action closes the popover except Share and Get Info, which
  we never close mid-action. macOS or the click-outside monitor may still close it when Finder or the share UI
  takes focus, which is accepted. Do not add `FloatingPanel` dismissal special cases for this.
- **Quick Look uses the supported controller path**: `HelperAppDelegate` implements
  `acceptsPreviewPanelControl` / `begin…` / `end…` (nonisolated + `MainActor.assumeIsolated`) and
  hands the panel the process-lifetime `QuickLookPresenter`. Never set `QLPreviewPanel.dataSource`
  without controlling the panel.
- **Shipped popover only**: hooks are nil when `editing != nil` or `isPreview`; the editor keeps its own
  Remove menu. VoiceOver: `.accessibilityAction(.showMenu)`. Analytics: `popover_item_action`.
```

(Delete the Get Info / Quick Look / Force Quit clauses that Task 6 removed, if any.)

- [ ] **Step 2: Extend the testing.md seam list** (append to the "Existing seams" paragraph, before `MacOSFloorGuardTests`):

```markdown
`PopoverItemMenu.entries` / `.dismissesPopover` / `.runningMatchIndex` / `.claimsEvent` (popover item context menu — missing → no menu, apps never get a bundle hand-off item (App Management alert), folders never get running rows, hidden app → no Hide, running match by bundle path not id, overlay claims only right-/Control-clicks so left-click launch and scrolling stay SwiftUI's; guarded by `PopoverItemMenuTests`),
```

- [ ] **Step 3: Full verification**

```bash
xcodebuild test -project DockTile.xcodeproj -scheme DockTile -configuration Debug \
  -destination 'platform=macOS' -only-testing:DockTileTests CODE_SIGNING_ALLOWED=NO
```
Expected: all pass. Then rebuild signed (Task 5 Step 5) so the dev app is launchable afterwards.

- [ ] **Step 4: Commit**

```bash
git add .claude/rules/architecture.md .claude/rules/testing.md
git commit -m "docs(rules): popover item context menu"
```

- [ ] **Step 5: Gates.** Run `/stage-gate --dev` (fresh reviewer) before pushing. Push the branch and run CI on it (`gh workflow run ci.yml --ref feat/popover-item-menu`); the macOS 15 leg must be green. Register `action` and `is_folder` as GA4 custom definitions for `popover_item_action` (analytics.md: unregistered params are discarded). Karthik decides merge and release.

---

## Spike Results

Run 2026-10-05 on macOS 27, dev tiles "Dev Tile" (7 items) and "Work" (100 items), Ghost mode.

| ID | Result | Note |
|---|---|---|
| S1 | PASS | Menu at the pointer, popover stays open (Karthik + `menuWillOpen` log). |
| S2 | PASS | Control-click opens the menu and does not launch. |
| S3 | PASS | Left-click, hover, scrolling in the 100-app tile and keyboard navigation are unchanged. |
| S4 | PASS | Esc or a click away closes only the menu. A click outside the popover closes both, as expected. |
| S5 | **FAIL for apps / PASS for folders** | `NSPerformService("Finder/Show Info")` works (Finder's Info window opens, no Automation prompt). But for a third-party app in `/Applications`, macOS checks **App Management** (`kTCCServiceSystemPolicyAppBundles`) for the helper, refuses ("does not allow prompting for unentitled binaries"), and shows "*Work.app* was prevented from modifying apps on your Mac" once per tile. No check for a folder (Media) or for an app on the read-only system volume (Terminal, Automator). |
| S6 | **FAIL for apps** | The Quick Look controller path works (panel shows and outlives the popover), but it triggers the same App Management denial for a `/Applications` app. Folder Quick Look still needs a check in the Task 5 gate. |
| S7 | Partial | The share submenu populates. `standardShareMenuItem` comes with an icon that AppKit re-applies after creation; setting `image = nil` in `menuWillOpen` removes it (Karthik asked for no icon). Completion and cancel were not exercised. Moved to the Task 5 gate (folders only now). |
| S8 | PASS | ⌥ swaps Quit → Force Quit. |
| S9 | Info | `menuDidClose` fires **before** the item's action (1–135 ms). |
| Extra | **Every hand-off of a `/Applications` app is denied** | Show in Finder via `NSWorkspace.activateFileViewerSelecting` and via `/usr/bin/open -R` both trigger the same App Management denial. Re-signing the helper with **Developer ID** (team R68RHN3HF5) did not help either. Launching apps (`openApplication`) never triggers it. Probe from the VS Code terminal (which has App Management) left Figma.app's `com.apple.macl` unchanged, so the write is caller-specific (inference: macOS records the handing-off app's access on the bundle). |

**Outcome (Karthik, 2026-10-10): D1 revised.** Folders keep the full menu; apps get Open plus Hide · Quit when running. No item that hands an app bundle to another process may appear for apps. Spike also found: an `@objc` action named like an `NSView`/`NSObject` method (`quickLook`, `perform`) is ambiguous in `#selector`, so Task 4 uses `performItem(_:)`.
