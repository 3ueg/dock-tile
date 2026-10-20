//
//  MainWindowWidthTests.swift
//  DockTileTests
//
//  The main window is horizontally resizable: 768 closed, 768 + 260 = 1028 with the Customise
//  inspector open, 1200 at most. Pins the shared clamp used by every width fix-up site and
//  `windowWillResize`, and the frame arithmetic for opening/closing the inspector.
//

import Testing
import CoreGraphics
@testable import Dock_Tile

@Suite("Main window width clamp")
struct MainWindowWidthTests {

    @Test("Range is exactly 768…1200 with a 260 inspector")
    func range() {
        #expect(AppDelegate.minWindowWidth == 768)
        #expect(AppDelegate.inspectorWidth == 260)
        #expect(AppDelegate.maxWindowWidth == 1200)
    }

    @Test("UserDefaults key is stable", arguments: ["inspectorShown"])
    func key(expected: String) {
        #expect(UserDefaultsKeys.inspectorShown == expected)
    }

    @Test("Clamps into the range", arguments: [
        (CGFloat(700), false, CGFloat(768)),
        (CGFloat(768), false, CGFloat(768)),
        (CGFloat(900), false, CGFloat(900)),
        (CGFloat(1500), false, CGFloat(1200)),
        (CGFloat(700), true, CGFloat(1028)),
        (CGFloat(1000), true, CGFloat(1028)),
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

    @Test("Opening grows by 260 keeping the leading edge")
    func openGrows() {
        let result = open(CGRect(x: 100, y: 200, width: 800, height: 600), on: screen)
        #expect(result == CGRect(x: 100, y: 200, width: 1060, height: 600))
    }

    @Test("Opening clamps to the 1200 maximum")
    func openClampsToMax() {
        let result = open(CGRect(x: 100, y: 200, width: 1100, height: 600), on: screen)
        #expect(result == CGRect(x: 100, y: 200, width: 1200, height: 600))
    }

    @Test("Opening near the right edge shifts left to fit")
    func openShiftsLeft() {
        let result = open(CGRect(x: 1500, y: 200, width: 800, height: 600), on: screen)
        #expect(result == CGRect(x: 940, y: 200, width: 1060, height: 600))
    }

    @Test("Opening on a screen narrower than the window fits the screen")
    func openOnNarrowScreen() {
        let narrow = CGRect(x: 0, y: 0, width: 900, height: 1200)
        let result = open(CGRect(x: 50, y: 200, width: 800, height: 600), on: narrow)
        #expect(result == CGRect(x: 0, y: 200, width: 900, height: 600))
    }

    @Test("Second display: stays put when it fits")
    func openOnSecondDisplay() {
        let second = CGRect(x: 2000, y: 0, width: 1600, height: 1000)
        let result = open(CGRect(x: 2100, y: 100, width: 800, height: 600), on: second)
        #expect(result == CGRect(x: 2100, y: 100, width: 1060, height: 600))
    }

    @Test("Second display: shifts against its own right edge, not the width")
    func openShiftsOnSecondDisplay() {
        let second = CGRect(x: 2000, y: 0, width: 1600, height: 1000)
        let result = open(CGRect(x: 3000, y: 100, width: 800, height: 600), on: second)
        #expect(result == CGRect(x: 2540, y: 100, width: 1060, height: 600))
    }

    @Test("Closing shrinks by 260, x unchanged")
    func closeShrinks() {
        let result = AppDelegate.windowFrame(forInspectorShown: false,
                                             from: CGRect(x: 100, y: 200, width: 1060, height: 600),
                                             visibleFrame: screen)
        #expect(result == CGRect(x: 100, y: 200, width: 800, height: 600))
    }

    @Test("Closing never goes below the closed minimum", arguments: [CGFloat(1028), CGFloat(900)])
    func closeFloor(width: CGFloat) {
        let result = AppDelegate.windowFrame(forInspectorShown: false,
                                             from: CGRect(x: 100, y: 200, width: width, height: 600),
                                             visibleFrame: screen)
        #expect(result == CGRect(x: 100, y: 200, width: 768, height: 600))
    }
}
