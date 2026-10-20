//
//  AppearanceColorViewTests.swift
//  DockTileTests
//
//  `NSColorBackgroundView` paints panel and card backgrounds with a dynamic AppKit colour. It used
//  to resolve that colour to a fixed CGColor once, so a view built in Dark Mode stayed dark after
//  the system switched to Light (the Customise Tile inspector, 2026-10-21). The backing view must
//  re-resolve on every effective-appearance change.
//

import Testing
import AppKit
@testable import Dock_Tile

@Suite("Background colour follows the appearance")
@MainActor
struct AppearanceColorViewTests {

    private func resolved(_ color: NSColor, in name: NSAppearance.Name) throws -> CGColor {
        let appearance = try #require(NSAppearance(named: name))
        var cg: CGColor?
        appearance.performAsCurrentDrawingAppearance { cg = color.cgColor }
        return try #require(cg)
    }

    @Test("Switching Dark → Light → Dark repaints the layer each time")
    func followsAppearanceChanges() throws {
        let view = AppearanceColorView(color: .windowBackgroundColor)
        view.frame = NSRect(x: 0, y: 0, width: 10, height: 10)

        view.appearance = NSAppearance(named: .darkAqua)
        view.displayIfNeeded()
        let dark = try #require(view.layer?.backgroundColor)
        #expect(dark == (try resolved(.windowBackgroundColor, in: .darkAqua)))

        view.appearance = NSAppearance(named: .aqua)
        view.displayIfNeeded()
        let light = try #require(view.layer?.backgroundColor)
        #expect(light == (try resolved(.windowBackgroundColor, in: .aqua)))
        #expect(light != dark)

        view.appearance = NSAppearance(named: .darkAqua)
        view.displayIfNeeded()
        #expect(view.layer?.backgroundColor == dark)
    }

    @Test("Changing the colour repaints with the current appearance")
    func colourChange() throws {
        let view = AppearanceColorView(color: .windowBackgroundColor)
        view.frame = NSRect(x: 0, y: 0, width: 10, height: 10)
        view.appearance = NSAppearance(named: .darkAqua)
        view.color = .quaternarySystemFill
        view.displayIfNeeded()
        #expect(view.layer?.backgroundColor == (try resolved(.quaternarySystemFill, in: .darkAqua)))
    }
}
