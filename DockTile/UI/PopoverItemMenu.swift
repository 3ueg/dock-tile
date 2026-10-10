//
//  PopoverItemMenu.swift
//  DockTile
//
//  Right-click / Control-click context menu for apps and folders in the shipped tile popover
//  (issue #17). Finder's own context menu cannot be borrowed through any public API, so this
//  builds a native menu from public AppKit pieces. The decisions live in the pure seams below;
//  the AppKit plumbing follows.
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
