//
//  MainWindowWidthTests.swift
//  DockTileTests
//
//  The main window is horizontally resizable: 700 closed, 700 + 260 = 960 with the Customise
//  inspector open, 1200 at most. Pins the shared clamp used by every width fix-up site and
//  `windowWillResize`, and the frame arithmetic for opening/closing the inspector: the window keeps
//  its width, except that opening grows a narrower window to 960; closing never moves the frame.
//  Also pins that the split view's own minimum fits inside those window minimums.
//

import Testing
import CoreGraphics
@testable import Dock_Tile

@Suite("Main window width clamp")
struct MainWindowWidthTests {

    @Test("Range is exactly 700…1200 with a 260 inspector")
    func range() {
        #expect(AppDelegate.minWindowWidth == 700)
        #expect(AppDelegate.inspectorWidth == 260)
        #expect(AppDelegate.maxWindowWidth == 1200)
    }

    @Test("UserDefaults key is stable")
    func key() {
        #expect(UserDefaultsKeys.inspectorShown == "inspectorShown")
    }

    @Test("Clamps into the range", arguments: [
        (CGFloat(650), false, CGFloat(700)),
        (CGFloat(700), false, CGFloat(700)),
        (CGFloat(900), false, CGFloat(900)),
        (CGFloat(1500), false, CGFloat(1200)),
        (CGFloat(650), true, CGFloat(960)),
        (CGFloat(950), true, CGFloat(960)),
        (CGFloat(1100), true, CGFloat(1100)),
        (CGFloat(1500), true, CGFloat(1200))
    ])
    func clamps(input: CGFloat, inspectorShown: Bool, expected: CGFloat) {
        #expect(AppDelegate.clampedWindowWidth(input, inspectorShown: inspectorShown) == expected)
    }

    // MARK: - Frame arithmetic

    private let screen = CGRect(x: 0, y: 0, width: 2000, height: 1200)

    private func open(_ frame: CGRect, on visible: CGRect) -> CGRect {
        AppDelegate.windowFrame(forInspectorShown: true, from: frame, visibleFrame: visible)
    }

    @Test("Opening grows a narrower window to exactly 960, keeping the leading edge")
    func openGrowsToOpenMinimum() {
        let result = open(CGRect(x: 100, y: 200, width: 800, height: 600), on: screen)
        #expect(result == CGRect(x: 100, y: 200, width: 960, height: 600))
    }

    @Test("Opening keeps a window already at least 960 wide", arguments: [CGFloat(1060), CGFloat(1100)])
    func openKeepsWidth(width: CGFloat) {
        let frame = CGRect(x: 100, y: 200, width: width, height: 600)
        #expect(open(frame, on: screen) == frame)
    }

    @Test("Opening near the right edge shifts left to fit")
    func openShiftsLeft() {
        let result = open(CGRect(x: 1500, y: 200, width: 800, height: 600), on: screen)
        #expect(result == CGRect(x: 1040, y: 200, width: 960, height: 600))
    }

    @Test("Opening past the left edge shifts right to fit")
    func openShiftsRight() {
        let result = open(CGRect(x: -100, y: 200, width: 800, height: 600), on: screen)
        #expect(result == CGRect(x: 0, y: 200, width: 960, height: 600))
    }

    @Test("Opening on a screen narrower than 960 fits the screen")
    func openOnNarrowScreen() {
        let narrow = CGRect(x: 0, y: 0, width: 900, height: 1200)
        let result = open(CGRect(x: 50, y: 200, width: 800, height: 600), on: narrow)
        #expect(result == CGRect(x: 0, y: 200, width: 900, height: 600))
    }

    @Test("Second display: stays put when it fits")
    func openOnSecondDisplay() {
        let second = CGRect(x: 2000, y: 0, width: 1600, height: 1000)
        let result = open(CGRect(x: 2100, y: 100, width: 800, height: 600), on: second)
        #expect(result == CGRect(x: 2100, y: 100, width: 960, height: 600))
    }

    @Test("Second display: shifts against its own right edge, not the width")
    func openShiftsOnSecondDisplay() {
        let second = CGRect(x: 2000, y: 0, width: 1600, height: 1000)
        let result = open(CGRect(x: 3000, y: 100, width: 800, height: 600), on: second)
        #expect(result == CGRect(x: 2640, y: 100, width: 960, height: 600))
    }

    @Test("Closing never changes the frame", arguments: [CGFloat(1060), CGFloat(960)])
    func closeKeepsFrame(width: CGFloat) {
        let frame = CGRect(x: 100, y: 200, width: width, height: 600)
        #expect(AppDelegate.windowFrame(forInspectorShown: false, from: frame, visibleFrame: screen) == frame)
    }

    // MARK: - The split view fits inside the window minimums

    /// The split view's minimum width counts the inspector TWICE. Measured on macOS 27 (2026-10-20)
    /// by logging each `NSSplitViewItem` view's `fittingSize`: closed, the minimum is exactly
    /// sidebar + Tile Detail (502 = 228 + 274); open, it is sidebar + Tile Detail + 2 × 260
    /// (1022 = 228 + 274 + 520). The SwiftUI hosting view's fitting size includes the inspector (its
    /// safe-area inset), and the NSSplitView adds the inspector column again. So the open inequality
    /// below bills `2 * inspectorWidth`, never a literal: the overhead IS the inspector width.
    /// The AX widths of the three columns still sum to the window width (no visible gap).
    /// Minimum room between the split view's own minimum and the window minimum.
    private let slack: CGFloat = 8

    @Test("Sidebar column range is 220…280")
    func sidebarRange() {
        #expect(AppDelegate.sidebarMinWidth == 220)
        #expect(AppDelegate.sidebarMaxWidth == 280)
    }

    @Test("Detail column minimum is 150")
    func detailMinimum() {
        #expect(AppDelegate.detailColumnMinWidth == 150)
    }

    /// The sidebar can be dragged to its maximum, so the widest sidebar is the binding case.
    @Test("Closed: sidebar + detail minimum fits the 700 minimum", arguments: [AppDelegate.sidebarMinWidth, AppDelegate.sidebarMaxWidth])
    func closedFits(sidebar: CGFloat) {
        #expect(sidebar + AppDelegate.detailColumnMinWidth + slack <= AppDelegate.minWindowWidth)
    }

    @Test("Open: sidebar + detail minimum + the inspector counted twice fits the 960 minimum", arguments: [AppDelegate.sidebarMinWidth, AppDelegate.sidebarMaxWidth])
    func openFits(sidebar: CGFloat) {
        let openMinimum = AppDelegate.clampedWindowWidth(0, inspectorShown: true)
        #expect(sidebar + AppDelegate.detailColumnMinWidth + 2 * AppDelegate.inspectorWidth + slack <= openMinimum)
    }

    /// The detail column's minimum is set below Tile Detail's content on purpose (see above); the
    /// content's room comes from the window minimum instead. The narrowest visible detail column
    /// (window minimum, widest sidebar, inspector open or closed) must still hold the hero row with
    /// its labels whole: 20 + 122 hero + 16 + the "Show in App Switcher" row (10 + 132 + 16 + 8 + 16
    /// + 36 + 10) + 20 = 406 pt, English, measured by AX.
    @Test("Narrowest visible detail column still holds the hero row", arguments: [false, true])
    func narrowestDetailHoldsHeroRow(inspectorShown: Bool) {
        let window = AppDelegate.clampedWindowWidth(0, inspectorShown: inspectorShown)
        let detail = window - AppDelegate.sidebarMaxWidth - (inspectorShown ? AppDelegate.inspectorWidth : 0)
        #expect(detail == 420)
        #expect(detail >= 406)
    }
}
