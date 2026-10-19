//  AppsFacePreviewTests.swift — renders the REAL DockTileIconPreview in Apps mode through
//  ImageRenderer (as IconPreviewGeometryTests does) and scans pixels.
import AppKit
import SwiftUI
import Testing
@testable import Dock_Tile

@MainActor
@Suite("Apps face preview")
struct AppsFacePreviewTests {
    private static let side: CGFloat = 256
    private static let finder = AppItem(bundleIdentifier: "com.apple.finder", name: "Finder",
                                        lastKnownPath: "/System/Library/CoreServices/Finder.app")
    private static let ghost = AppItem(bundleIdentifier: "com.example.not-installed", name: "Nope")

    private func preview(items: [AppItem], style: IconStyle) -> DockTileIconPreview {
        DockTileIconPreview(
            tintColor: .blue, iconType: .sfSymbol, iconValue: "star.fill", iconScale: 14,
            iconWeight: .medium, background: .colour, size: Self.side, appsFaceItems: items
        ).forcing(style)
    }
    private func renderWithImageRenderer(items: [AppItem], style: IconStyle) throws -> NSBitmapImageRep {
        let renderer = ImageRenderer(content: preview(items: items, style: style))
        renderer.scale = 1
        return NSBitmapImageRep(cgImage: try #require(renderer.cgImage))
    }
    private func render(items: [AppItem], style: IconStyle) throws -> NSBitmapImageRep {
        let view = preview(items: items, style: style)
        // NSHostingView + cacheDisplay (an 8-bit sRGB bitmap), NOT ImageRenderer: a mini's bitmap
        // from IconServices is 16-bit extended sRGB, which makes ImageRenderer emit its whole
        // output as ITU-R 2100 PQ, and PQ read back as sRGB lifts dark values by up to 0.06 (a
        // pixel scan would measure a veil that no window shows).
        let host = NSHostingView(rootView: view)
        host.frame = CGRect(x: 0, y: 0, width: Self.side, height: Self.side)
        host.layoutSubtreeIfNeeded()
        // One pixel per point, so the scan coordinates below are plain frame coordinates.
        let px = Int(Self.side)
        let rep = try #require(NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8,
            samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
            bytesPerRow: 0, bitsPerPixel: 0))
        rep.size = host.bounds.size
        host.cacheDisplay(in: host.bounds, to: rep)
        return rep
    }
    private func png(_ rep: NSBitmapImageRep) throws -> Data {
        try #require(rep.representation(using: .png, properties: [:]))
    }
    private func srgb(_ rep: NSBitmapImageRep, _ x: Int, _ y: Int) throws -> NSColor {
        try #require(rep.colorAt(x: x, y: y)?.usingColorSpace(.sRGB))
    }
    private static let frame = CGRect(x: 0, y: 0, width: side, height: side)
    private static func cell(_ i: Int, count: Int) -> CGRect {
        AppsFaceGrid.rect(AppsFaceGrid.cells(count: count)[i], in: frame, yUp: false)
    }
    /// Highest saturation along the cell's centre row — Finder's icon is half dark blue, half
    /// white face, so a single centre pixel could land on the seam between them.
    private func maxSaturation(_ rep: NSBitmapImageRep, in cell: CGRect) throws -> CGFloat {
        try [0.2, 0.35, 0.5, 0.65, 0.8].map { f in
            try srgb(rep, Int(cell.minX + cell.width * f), Int(cell.midY)).saturationComponent
        }.max() ?? 0
    }

    @Test("One installed app: light glass fills the frame, the mini sits top-left, the other cells are glass")
    func oneAppOnLightGlass() throws {
        let rep = try render(items: [Self.finder], style: .defaultStyle)
        let top = try srgb(rep, 128, 4)                      // full-frame shape, no icon-grid margin
        #expect(top.redComponent > 0.97 && abs(top.redComponent - top.blueComponent) < 0.02)
        let bottom = try srgb(rep, 128, 251)
        #expect(abs(bottom.redComponent - 0.925) < 0.03)
        let cell0 = Self.cell(0, count: 1)                 // the single centred 0.60 cell (51…205 px)
        #expect(abs(cell0.midX - 128) < 1)
        #expect(try maxSaturation(rep, in: cell0) > 0.3, "the centred cell shows glass, not Finder")
        // Inside the shape, left of the mini's draw box (33…223 px): empty glass.
        let glass = try srgb(rep, 20, 128)
        #expect(glass.saturationComponent < 0.03 && glass.redComponent > 0.9, "beside the mini is not empty glass: \(glass)")
    }

    @Test("Forced Dark draws the dark pair")
    func darkGlass() throws {
        let rep = try render(items: [Self.finder], style: .dark)
        #expect(abs(try srgb(rep, 128, 4).redComponent - 0.192) < 0.03)
        #expect(abs(try srgb(rep, 128, 251).redComponent - 0.078) < 0.03)
    }

    @Test("Clear / Tinted previews keep the light glass and drain the minis' colour")
    func clearAndTintedDesaturate() throws {
        // Positive control: the same ImageRenderer scan must SEE colour on Default, or the
        // "< 0.05" checks below would pass for a view that always desaturates.
        let coloured = try renderWithImageRenderer(items: [Self.finder], style: .defaultStyle)
        #expect(try maxSaturation(coloured, in: Self.cell(0, count: 1)) > 0.15, "default keeps colour")
        for style in [IconStyle.clear, .tinted] {
            let rep = try render(items: [Self.finder], style: style)
            #expect(try srgb(rep, 128, 4).redComponent > 0.97, "\(style)")
            // The saturation filter is a layer filter that cacheDisplay does not apply, so the
            // colour scan goes through ImageRenderer (equal-channel greys survive its PQ output).
            let drained = try renderWithImageRenderer(items: [Self.finder], style: style)
            #expect(try maxSaturation(drained, in: Self.cell(0, count: 1)) < 0.05, "\(style)")
        }
    }

    @Test("unresolvableItemsFallBackToGlyph: every item missing renders the glyph face byte-for-byte")
    func unresolvableItemsFallBackToGlyph() throws {
        let apps = try png(try render(items: [Self.ghost, Self.ghost], style: .defaultStyle))
        let glyph = try png(try render(items: [], style: .defaultStyle))
        #expect(apps == glyph)
    }

    @Test("fromConfig routes the items only for an Apps-face tile")
    func fromConfigRoutesByFace() {
        var config = DockTileConfiguration(name: "Work", iconFace: .glyph, appItems: [Self.finder])
        #expect(DockTileIconPreview.fromConfig(config, size: 44).appsFaceItems.isEmpty)
        config.iconFace = .apps
        #expect(DockTileIconPreview.fromConfig(config, size: 44).appsFaceItems == [Self.finder])
    }
}
