import AppKit
import Testing
@testable import Dock_Tile

@Suite("PopoverItemMenu seams")
struct PopoverItemMenuTests {

    // MARK: entries

    @Test("Not-running app: Open only")
    func appNotRunning() {
        #expect(PopoverItemMenu.entries(isFolder: false, runState: .notRunning, includesGetInfo: true) == [
            .action(.open),
        ])
    }

    @Test("Running, visible app: Open, then Hide and Quit with a Force Quit alternate")
    func appRunningVisible() {
        #expect(PopoverItemMenu.entries(isFolder: false, runState: .running(isHidden: false), includesGetInfo: true) == [
            .action(.open), .separator,
            .action(.hide), .action(.quit), .alternate(.forceQuit),
        ])
    }

    @Test("Running but hidden app: no Hide row (Review Focus 2)")
    func appRunningHidden() {
        #expect(PopoverItemMenu.entries(isFolder: false, runState: .running(isHidden: true), includesGetInfo: true) == [
            .action(.open), .separator,
            .action(.quit), .alternate(.forceQuit),
        ])
    }

    @Test("Apps never get an item that hands the bundle to another process (App Management, Review Focus 6)")
    func appsNeverHandOffTheBundle() {
        let handOffs: Set<PopoverItemMenuEntry> = [.action(.reveal), .action(.getInfo), .action(.quickLook), .action(.share)]
        for state in [PopoverItemRunState.notRunning, .running(isHidden: false), .running(isHidden: true)] {
            for info in [false, true] {
                let entries = PopoverItemMenu.entries(isFolder: false, runState: state, includesGetInfo: info)
                #expect(handOffs.isDisjoint(with: entries), "app menu for \(state), getInfo=\(info): \(entries)")
            }
        }
    }

    @Test("Folder: the full set, and never running rows even if a run state is passed")
    func folder() {
        #expect(PopoverItemMenu.entries(isFolder: true, runState: .running(isHidden: false), includesGetInfo: true) == [
            .action(.open), .separator,
            .action(.reveal), .action(.getInfo), .action(.quickLook), .separator,
            .action(.share),
        ])
    }

    // MARK: target path — which on-disk item the menu acts on (D7, Review Focus 1 + 4)

    @Test("Missing item: no target, so no menu at all — even when stale paths are known")
    func targetPathMissing() {
        #expect(PopoverItemMenu.targetPath(isFolder: false, isInstalled: false, resolvedPath: "/Applications/Foo.app",
                                           lastKnownPath: "/Applications/Foo.app", lastKnownPathExists: true) == nil)
        #expect(PopoverItemMenu.targetPath(isFolder: true, isInstalled: false, resolvedPath: nil,
                                           lastKnownPath: nil, lastKnownPathExists: false) == nil)
    }

    @Test("Installed but unresolved: no target")
    func targetPathUnresolved() {
        #expect(PopoverItemMenu.targetPath(isFolder: false, isInstalled: true, resolvedPath: nil,
                                           lastKnownPath: nil, lastKnownPathExists: false) == nil)
    }

    @Test("App: the copy at lastKnownPath wins over Launch Services, as AppLauncher.launch does")
    func targetPathPrefersLastKnownPath() {
        #expect(PopoverItemMenu.targetPath(isFolder: false, isInstalled: true, resolvedPath: "/Applications/Foo.app",
                                           lastKnownPath: "/Users/k/Applications/Foo.app", lastKnownPathExists: true)
                == "/Users/k/Applications/Foo.app")
    }

    @Test("App: a stale lastKnownPath falls back to the Launch Services copy")
    func targetPathFallsBackToLaunchServices() {
        #expect(PopoverItemMenu.targetPath(isFolder: false, isInstalled: true, resolvedPath: "/Applications/Foo.app",
                                           lastKnownPath: "/Users/k/Applications/Foo.app", lastKnownPathExists: false)
                == "/Applications/Foo.app")
    }

    @Test("Folder: its resolved path; lastKnownPath (an app field) is ignored")
    func targetPathFolder() {
        #expect(PopoverItemMenu.targetPath(isFolder: true, isInstalled: true, resolvedPath: "/Users/k/Media",
                                           lastKnownPath: "/Users/k/Other", lastKnownPathExists: true) == "/Users/k/Media")
    }

    @Test("Folder Get Info is omitted when not available (macOS 15, D2)")
    func noGetInfo() {
        #expect(PopoverItemMenu.entries(isFolder: true, runState: .notRunning, includesGetInfo: false) == [
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
                    let e = PopoverItemMenu.entries(isFolder: folder, runState: state, includesGetInfo: info)
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
