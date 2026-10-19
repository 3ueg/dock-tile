//  AppsFaceRenderTests.swift — pixel guards for the Apps face through the REAL renderers
//  (generateAppsLayerPNG → drawAppsGrid → AppsFaceGrid), in the style of GlyphLayerRenderTests.
import AppKit
import SwiftUI
import Testing
@testable import Dock_Tile

@MainActor
@Suite("Apps face rendering")
struct AppsFaceRenderTests {
    static let canvas = 1024
    static let shape = CGRect(x: 100, y: 100, width: 824, height: 824)   // 1024 inset by 25/256

    /// A stand-in app icon: an opaque squircle on Apple's icon grid (transparent margin) — or
    /// full-bleed, which is what a Finder folder glyph's bounds look like to the renderer.
    static func mini(_ colour: NSColor, fullBleed: Bool = false, side: Int = 256) -> NSImage {
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: side, pixelsHigh: side, bitsPerSample: 8,
                                   samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                   colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        rep.size = CGSize(width: side, height: side)
        let ctx = NSGraphicsContext(bitmapImageRep: rep)!
        let full = CGRect(x: 0, y: 0, width: side, height: side)
        let inset = fullBleed ? 0 : CGFloat(side) * IconDepthMetrics.contentInsetRatio
        let r = full.insetBy(dx: inset, dy: inset)
        ctx.cgContext.clear(full)
        ctx.cgContext.addPath(RoundedRectangle(cornerRadius: r.width * 0.225, style: .continuous).path(in: r).cgPath)
        ctx.cgContext.setFillColor(colour.cgColor)
        ctx.cgContext.fillPath()
        let image = NSImage(size: rep.size); image.addRepresentation(rep); return image
    }

    static func bitmap(_ png: Data) throws -> NSBitmapImageRep { try #require(NSBitmapImageRep(data: png)) }

    /// Centre of cell `i` for `count` items, in y-down pixel coordinates of the 1024 canvas.
    static func centre(_ i: Int, count: Int) -> (x: Int, y: Int) {
        let r = AppsFaceGrid.rect(AppsFaceGrid.cells(count: count)[i], in: shape, yUp: false)
        return (Int(r.midX), Int(r.midY))
    }

    static func alpha(_ rep: NSBitmapImageRep, _ x: Int, _ y: Int) -> CGFloat {
        rep.colorAt(x: x, y: y)?.alphaComponent ?? 0
    }

    /// Width of the opaque run along row `y` starting from the first opaque pixel at or after `fromX`.
    static func opaqueRun(_ rep: NSBitmapImageRep, y: Int, fromX: Int) -> Int {
        var x = fromX
        while x < rep.pixelsWide, alpha(rep, x, y) < 0.5 { x += 1 }
        let start = x
        while x < rep.pixelsWide, alpha(rep, x, y) >= 0.5 { x += 1 }
        return x - start
    }

    @Test("oneAppIsCentredAtSixtyPercent: one app is one centred icon at 0.60 of the shape; the canvas is 1024² with transparent margin")
    func oneAppIsCentredAtSixtyPercent() throws {
        let rep = try Self.bitmap(try IconGenerator.generateAppsLayerPNG(
            minis: [.init(image: Self.mini(.systemBlue), isFolder: false)]))
        #expect(rep.pixelsWide == Self.canvas && rep.pixelsHigh == Self.canvas)
        for (x, y) in [(2, 2), (1021, 2), (2, 1021), (1021, 1021), (512, 104), (104, 512), (358, 230)] {
            #expect(Self.alpha(rep, x, y) == 0, "(\(x),\(y)) painted")   // (358,230) = where a 2×2 cell 0 would start
        }
        #expect(Self.alpha(rep, 512, 512) == 1)
        let c0 = Self.centre(0, count: 1)
        #expect(c0.x == 512 && c0.y == 512)                     // independent pin: centred
        let run = Self.opaqueRun(rep, y: 512, fromX: 0)
        #expect(abs(run - 494) <= 4, "visible squircle is \(run) px, 0.60 of 824 is 494")
    }

    @Test("Two apps paint the top row of a 2×2 and leave the bottom row glass")
    func twoAppsPaintTheTopRow() throws {
        let rep = try Self.bitmap(try IconGenerator.generateAppsLayerPNG(
            minis: (0..<2).map { _ in .init(image: Self.mini(.systemBlue), isFolder: false) }))
        for i in 0...1 { let c = Self.centre(i, count: 2); #expect(Self.alpha(rep, c.x, c.y) == 1, "cell \(i) empty") }
        for i in 2...3 { let c = Self.centre(i, count: 4); #expect(Self.alpha(rep, c.x, c.y) == 0, "cell \(i) is not empty glass") }
        let c0 = Self.centre(0, count: 2)
        #expect(c0.x == 358 && c0.y == 358)                     // independent pin of the 2×2 origin
    }

    @Test("The visible squircle lands on the cell: an app's margin is absorbed by the ÷0.805 box")
    func appSquircleFillsItsCell() throws {
        let rep = try Self.bitmap(try IconGenerator.generateAppsLayerPNG(
            minis: (0..<2).map { _ in .init(image: Self.mini(.systemRed), isFolder: false) }))
        let c0 = Self.centre(0, count: 2)
        let expected = Int(AppsFaceGrid.cellRatio(columns: 2) * Self.shape.width)   // 269
        let run = Self.opaqueRun(rep, y: c0.y, fromX: 0)
        #expect(abs(run - expected) <= 4, "visible squircle is \(run) px, cell is \(expected)")
    }

    @Test("folderMiniFitsItsCell: a full-bleed folder glyph is fitted to the cell, not enlarged")
    func folderMiniFitsItsCell() throws {
        let rep = try Self.bitmap(try IconGenerator.generateAppsLayerPNG(
            minis: [.init(image: Self.mini(.systemOrange, fullBleed: true), isFolder: true)]))
        let run = Self.opaqueRun(rep, y: 512, fromX: 0)
        #expect(abs(run - 494) <= 4, "folder drew \(run) px; fitted to the 494 px cell, not the 614 px app box")
    }

    @Test("Nine apps fill a 3×3; a tenth is dropped; adjacent minis do not touch")
    func nineAppsFillTheGrid() throws {
        let minis = (0..<10).map { _ in IconGenerator.AppsFaceMini(image: Self.mini(.systemGreen), isFolder: false) }
        let rep = try Self.bitmap(try IconGenerator.generateAppsLayerPNG(minis: minis))
        for i in 0..<9 {
            let c = Self.centre(i, count: 9)
            #expect(Self.alpha(rep, c.x, c.y) == 1, "cell \(i) empty")
        }
        // The gap between cell 0 and cell 1 (midpoint of the gap, on the cells' centre row) is glass:
        // a mini body is alpha 1; only the two 0.35-alpha shadows can feather into the 38 px gap.
        let a = AppsFaceGrid.rect(AppsFaceGrid.cells(count: 9)[0], in: Self.shape, yUp: false)
        let b = AppsFaceGrid.rect(AppsFaceGrid.cells(count: 9)[1], in: Self.shape, yUp: false)
        #expect(Self.alpha(rep, Int((a.maxX + b.minX) / 2), Int(a.midY)) < 0.3)
    }

    @Test("Five apps on a 3×3 leave the bottom row's last two cells and the whole third row empty")
    func fiveAppsAreAnL() throws {
        let minis = (0..<5).map { _ in IconGenerator.AppsFaceMini(image: Self.mini(.systemIndigo), isFolder: false) }
        let rep = try Self.bitmap(try IconGenerator.generateAppsLayerPNG(minis: minis))
        for i in 0..<5 { let c = Self.centre(i, count: 9); #expect(Self.alpha(rep, c.x, c.y) == 1) }
        for i in 5..<9 { let c = Self.centre(i, count: 9); #expect(Self.alpha(rep, c.x, c.y) == 0) }
    }

    @Test("miniCastsAContactShadow: soft shadow below a mini, none above it")
    func miniCastsAContactShadow() throws {
        let rep = try Self.bitmap(try IconGenerator.generateAppsLayerPNG(
            minis: [.init(image: Self.mini(.white, fullBleed: true), isFolder: true)]))   // full-bleed: the body reaches the cell edge
        let cell = AppsFaceGrid.rect(AppsFaceGrid.cells(count: 1)[0], in: Self.shape, yUp: false)
        let below = Self.alpha(rep, Int(cell.midX), Int(cell.maxY) + 5)
        let above = Self.alpha(rep, Int(cell.midX), Int(cell.minY) - 5)
        #expect(below > 0.05 && below < 0.4, "shadow below: \(below)")
        // The shadow is OFFSET downward (6 px at 1024), so the row 5 px above the mini carries far
        // less of it than the row 5 px below — a relative check that a blur-radius detail can't trip.
        #expect(above < below / 2, "shadow above \(above) vs below \(below)")
        let shadowColour = try #require(rep.colorAt(x: Int(cell.midX), y: Int(cell.maxY) + 5)?.usingColorSpace(.sRGB))
        #expect(shadowColour.brightnessComponent < 0.2)       // black, not a smeared mini
    }

    @Test("No minis → an entirely transparent layer (the caller must have fallen back to the glyph face)")
    func emptyLayerIsTransparent() throws {
        let rep = try Self.bitmap(try IconGenerator.generateAppsLayerPNG(minis: []))
        #expect(Self.alpha(rep, 512, 512) == 0 && Self.alpha(rep, 358, 358) == 0)
    }
    // MARK: - Fallback .icns and the legacy bake (same renderer, four styles)

    static func gray(_ rep: NSBitmapImageRep, _ x: Int, _ y: Int) throws -> CGFloat {
        // A rep read back from an .icns is sRGB-tagged, and on macOS 27 its `colorAt` comes back
        // labelled calibrated, so converting it to sRGB lifts 0.192 to 0.251. Read the bytes.
        if rep.colorSpace == .sRGB, rep.bitsPerPixel == 32, let data = rep.bitmapData {
            let o = y * rep.bytesPerRow + x * 4
            #expect(data[o] == data[o + 1] && data[o + 1] == data[o + 2], "not gray at (\(x),\(y))")
            return CGFloat(data[o]) / 255
        }
        let c = try #require(rep.colorAt(x: x, y: y)?.usingColorSpace(.sRGB))
        #expect(abs(c.redComponent - c.greenComponent) < 0.01 && abs(c.greenComponent - c.blueComponent) < 0.01,
                "not gray at (\(x),\(y)): \(c)")
        return c.redComponent
    }

    static func bake(_ style: IconStyle, minis: [IconGenerator.AppsFaceMini]) throws -> NSBitmapImageRep {
        let image = IconGenerator.appsIcon(minis: minis, size: CGSize(width: canvas, height: canvas), iconStyle: style)
        return try #require(image.representations.compactMap { $0 as? NSBitmapImageRep }.first)
    }

    @Test("Every style bakes the icon-grid margin and the system gray pair, top stop at the top",
          arguments: IconStyle.allCases)
    func bakeIsMarginedOnSystemGrays(_ style: IconStyle) throws {
        let rep = try Self.bake(style, minis: [.init(image: Self.mini(.systemBlue), isFolder: false)])
        #expect(Self.alpha(rep, 1, 512) == 0, "\(style): mid-edge painted — no margin")
        #expect(Self.alpha(rep, 512, 512) == 1)
        let run = Self.opaqueRun(rep, y: 512, fromX: 0)
        #expect(abs(run - 824) <= 2, "\(style): shape is \(run) px wide")
        let expected = AppsFaceGrid.fillGrays(style: style)
        #expect(abs(try Self.gray(rep, 512, 106) - expected.top) < 0.02, "\(style) top")
        #expect(abs(try Self.gray(rep, 512, 917) - expected.bottom) < 0.02, "\(style) bottom")
    }

    @Test("Dark is the dark pair, Default the light pair — independent pins")
    func grayPairsPinned() throws {
        let dark = try Self.bake(.dark, minis: [])
        #expect(abs(try Self.gray(dark, 512, 106) - 0.192) < 0.02)
        #expect(abs(try Self.gray(dark, 512, 917) - 0.078) < 0.02)
        let light = try Self.bake(.defaultStyle, minis: [])
        #expect(try Self.gray(light, 512, 106) > 0.98)
        #expect(abs(try Self.gray(light, 512, 917) - 0.925) < 0.02)
    }

    @Test("clearAndTintedVariantsDesaturateMinis: Default/Dark keep the mini's colour, Clear/Tinted are grayscale")
    func clearAndTintedVariantsDesaturateMinis() throws {
        let red = IconGenerator.AppsFaceMini(image: Self.mini(.systemRed, fullBleed: true), isFolder: true)
        let c0 = Self.centre(0, count: 1)
        for style in IconStyle.allCases {
            let c = try #require(try Self.bake(style, minis: [red]).colorAt(x: c0.x, y: c0.y)?.usingColorSpace(.sRGB))
            #expect(c.alphaComponent == 1)
            if AppsFaceGrid.desaturatesMinis(style: style) {
                #expect(c.saturationComponent < 0.05, "\(style) mini still coloured: \(c)")
            } else {
                #expect(c.saturationComponent > 0.6, "\(style) mini lost its colour: \(c)")
            }
        }
    }

    @Test("The written fallback .icns carries the margin and the light pair in its largest rendition")
    func fallbackIcnsFile() throws {
        let out = FileManager.default.temporaryDirectory.appendingPathComponent("docktile-apps-\(UUID().uuidString).icns")
        defer { try? FileManager.default.removeItem(at: out) }
        try IconGenerator.generateAppsFallbackIcns(
            minis: [.init(image: Self.mini(.systemBlue), isFolder: false)], outputURL: out)
        let image = try #require(NSImage(contentsOf: out))
        let rep = try #require(image.representations.compactMap { $0 as? NSBitmapImageRep }.max(by: { $0.pixelsWide < $1.pixelsWide }))
        #expect(rep.pixelsWide == 1024)
        #expect(Self.alpha(rep, 1, 512) == 0)
        #expect(try Self.gray(rep, 512, 106) > 0.98)
    }

    @Test("The legacy variant file is written for a non-default style")
    func legacyVariantFile() throws {
        let out = FileManager.default.temporaryDirectory.appendingPathComponent("docktile-apps-dark-\(UUID().uuidString).icns")
        defer { try? FileManager.default.removeItem(at: out) }
        try IconGenerator.generateAppsIcns(minis: [.init(image: Self.mini(.systemBlue), isFolder: false)],
                                           outputURL: out, iconStyle: .dark)
        let image = try #require(NSImage(contentsOf: out))
        let rep = try #require(image.representations.compactMap { $0 as? NSBitmapImageRep }.max(by: { $0.pixelsWide < $1.pixelsWide }))
        #expect(abs(try Self.gray(rep, 512, 106) - 0.192) < 0.02)
    }
}
