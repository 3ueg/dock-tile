//
//  MainWindowWidthTests.swift
//  DockTileTests
//
//  The main window is horizontally resizable between 782 and 1200 pt (was fixed at 768).
//  Pins the shared clamp used by every width fix-up site and `windowWillResize`.
//

import Testing
import CoreGraphics
@testable import Dock_Tile

@Suite("Main window width clamp")
struct MainWindowWidthTests {

    @Test("Range is exactly 782…1200")
    func range() {
        #expect(AppDelegate.minWindowWidth == 782)
        #expect(AppDelegate.maxWindowWidth == 1200)
    }

    @Test("Clamps into the range", arguments: [
        (CGFloat(700), CGFloat(782)),
        (CGFloat(768), CGFloat(782)),
        (CGFloat(782), CGFloat(782)),
        (CGFloat(900), CGFloat(900)),
        (CGFloat(1200), CGFloat(1200)),
        (CGFloat(1500), CGFloat(1200))
    ])
    func clamps(input: CGFloat, expected: CGFloat) {
        #expect(AppDelegate.clampedWindowWidth(input) == expected)
    }
}
