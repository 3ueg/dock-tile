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

// MARK: - Overlay view (claims secondary clicks only)

/// Transparent view over a popover cell. `hitTest` answers only for secondary clicks (see
/// `PopoverItemMenu.claimsEvent`), so left-click launch, hover, drag and scroll reach SwiftUI.
/// The menu is built per click, so running state and install status are live.
final class PopoverItemMenuView: NSView {
    var makeController: @MainActor () -> PopoverItemMenuController? = { nil }
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
