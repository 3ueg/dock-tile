//
//  MainWindowWidthTests.swift
//  DockTileTests
//
//  The main window is horizontally resizable: 728 closed, 728 + 260 = 988 with the Customise
//  inspector open, 1200 at most. Pins the shared clamp used by every width fix-up site and
//  `windowWillResize`, and the frame arithmetic for opening/closing the inspector: the window keeps
//  its width, except that opening grows a narrower window to 988; closing never moves the frame.
//

import Testing
import CoreGraphics
@testable import Dock_Tile

@Suite("Main window width clamp")
struct MainWindowWidthTests {

    @Test("Range is exactly 728…1200 with a 260 inspector")
    func range() {
        #expect(AppDelegate.minWindowWidth == 728)
        #expect(AppDelegate.inspectorWidth == 260)
        #expect(AppDelegate.maxWindowWidth == 1200)
    }

    @Test("UserDefaults key is stable")
    func key() {
        #expect(UserDefaultsKeys.inspectorShown == "inspectorShown")
    }

    @Test("Clamps into the range", arguments: [
        (CGFloat(700), false, CGFloat(728)),
        (CGFloat(728), false, CGFloat(728)),
        (CGFloat(900), false, CGFloat(900)),
        (CGFloat(1500), false, CGFloat(1200)),
        (CGFloat(700), true, CGFloat(988)),
        (CGFloat(950), true, CGFloat(988)),
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

    @Test("Opening grows a narrower window to exactly 988, keeping the leading edge")
    func openGrowsToOpenMinimum() {
        let result = open(CGRect(x: 100, y: 200, width: 800, height: 600), on: screen)
        #expect(result == CGRect(x: 100, y: 200, width: 988, height: 600))
    }

    @Test("Opening keeps a window already at least 988 wide", arguments: [CGFloat(1060), CGFloat(1100)])
    func openKeepsWidth(width: CGFloat) {
        let frame = CGRect(x: 100, y: 200, width: width, height: 600)
        #expect(open(frame, on: screen) == frame)
    }

    @Test("Opening near the right edge shifts left to fit")
    func openShiftsLeft() {
        let result = open(CGRect(x: 1500, y: 200, width: 800, height: 600), on: screen)
        #expect(result == CGRect(x: 1012, y: 200, width: 988, height: 600))
    }

    @Test("Opening past the left edge shifts right to fit")
    func openShiftsRight() {
        let result = open(CGRect(x: -100, y: 200, width: 800, height: 600), on: screen)
        #expect(result == CGRect(x: 0, y: 200, width: 988, height: 600))
    }

    @Test("Opening on a screen narrower than 988 fits the screen")
    func openOnNarrowScreen() {
        let narrow = CGRect(x: 0, y: 0, width: 900, height: 1200)
        let result = open(CGRect(x: 50, y: 200, width: 800, height: 600), on: narrow)
        #expect(result == CGRect(x: 0, y: 200, width: 900, height: 600))
    }

    @Test("Second display: stays put when it fits")
    func openOnSecondDisplay() {
        let second = CGRect(x: 2000, y: 0, width: 1600, height: 1000)
        let result = open(CGRect(x: 2100, y: 100, width: 800, height: 600), on: second)
        #expect(result == CGRect(x: 2100, y: 100, width: 988, height: 600))
    }

    @Test("Second display: shifts against its own right edge, not the width")
    func openShiftsOnSecondDisplay() {
        let second = CGRect(x: 2000, y: 0, width: 1600, height: 1000)
        let result = open(CGRect(x: 3000, y: 100, width: 800, height: 600), on: second)
        #expect(result == CGRect(x: 2612, y: 100, width: 988, height: 600))
    }

    @Test("Closing never changes the frame", arguments: [CGFloat(1060), CGFloat(988)])
    func closeKeepsFrame(width: CGFloat) {
        let frame = CGRect(x: 100, y: 200, width: width, height: 600)
        #expect(AppDelegate.windowFrame(forInspectorShown: false, from: frame, visibleFrame: screen) == frame)
    }
}
