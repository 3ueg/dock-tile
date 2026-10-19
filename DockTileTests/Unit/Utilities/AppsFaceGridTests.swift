//  AppsFaceGridTests.swift — the one geometry/material seam all four Apps-face renderers read.
import CoreGraphics
import Testing
@testable import Dock_Tile

struct AppsFaceGridTests {
    private func close(_ a: CGFloat, _ b: CGFloat, _ tolerance: CGFloat = 1e-9,
                       sourceLocation: SourceLocation = #_sourceLocation) {
        #expect(abs(a - b) < tolerance, "expected \(b), got \(a)", sourceLocation: sourceLocation)
    }

    @Test("Columns: 1 for a single item, 2 for two to four, 3 from five — both flips pinned")
    func columnFlip() {
        #expect(AppsFaceGrid.columns(count: 1) == 1)
        #expect(AppsFaceGrid.columns(count: 2) == 2)                       // 1 → 2 flip
        for n in 2...4 { #expect(AppsFaceGrid.columns(count: n) == 2, "\(n)") }
        #expect(AppsFaceGrid.columns(count: 5) == 3)                       // 4 → 5 flip
        for n in 5...12 { #expect(AppsFaceGrid.columns(count: n) == 3, "\(n)") }
    }

    @Test("Cell sizes: 0.60 single, then the iOS folder / App Library minis")
    func cellSizes() {
        close(AppsFaceGrid.cellRatio(columns: 1), 0.60)
        close(AppsFaceGrid.cellRatio(columns: 2), 0.3265, 1e-4)   // (0.70 − 0.047) / 2
        close(AppsFaceGrid.cellRatio(columns: 3), 0.2020, 1e-4)   // (0.70 − 2 × 0.047) / 3
        close(AppsFaceGrid.appIconContentRatio, 206.0 / 256.0)
    }

    @Test("Cell counts and layout for 1, 2, 3, 4, 5, 9 and 10 items")
    func cellLayouts() {
        let one = AppsFaceGrid.cells(count: 1)
        #expect(one.count == 1)
        close(one[0].minX, 0.20); close(one[0].minY, 0.20); close(one[0].width, 0.60); close(one[0].midX, 0.5)

        let two = AppsFaceGrid.cells(count: 2)
        #expect(two.count == 2)
        close(two[0].minX, 0.15); close(two[0].width, AppsFaceGrid.cellRatio(columns: 2))
        close(two[1].minY, two[0].minY)                  // the top row of a 2×2

        let three = AppsFaceGrid.cells(count: 3)
        #expect(three.count == 3)
        close(three[1].minY, three[0].minY)              // two on top…
        #expect(three[1].minX > three[0].minX)
        close(three[2].minX, three[0].minX)              // …one bottom-left
        #expect(three[2].minY > three[0].minY)

        let four = AppsFaceGrid.cells(count: 4)
        #expect(four.count == 4)
        close(four[3].maxX, 0.85); close(four[3].maxY, 0.85)   // the block spans exactly 0.70

        let five = AppsFaceGrid.cells(count: 5)
        #expect(five.count == 5)
        close(five[0].width, AppsFaceGrid.cellRatio(columns: 3))
        close(five[2].maxX, 0.85)                         // third column exists
        close(five[3].minX, 0.15); #expect(five[3].minY > five[2].minY)   // row-major wrap

        let nine = AppsFaceGrid.cells(count: 9)
        #expect(nine.count == 9)
        close(nine[8].maxX, 0.85); close(nine[8].maxY, 0.85)

        #expect(AppsFaceGrid.cells(count: 10).count == 9)
        #expect(AppsFaceGrid.cells(count: 0).isEmpty)
    }

    @Test("Cells never overlap on either grid")
    func cellsDisjoint() {
        for count in [4, 9] {
            let cells = AppsFaceGrid.cells(count: count)
            for i in cells.indices { for j in cells.indices where i < j {
                #expect(!cells[i].insetBy(dx: 1e-6, dy: 1e-6).intersects(cells[j]), "\(count): \(i) overlaps \(j)")
            } }
        }
    }

    @Test("An app's draw box is its cell ÷ the icon-grid content ratio; a folder's box is the cell")
    func drawBoxes() {
        let cell = AppsFaceGrid.cells(count: 9)[4]
        let app = AppsFaceGrid.drawBox(for: cell, isFolder: false)
        close(app.width, cell.width / AppsFaceGrid.appIconContentRatio)
        close(app.midX, cell.midX); close(app.midY, cell.midY)
        #expect(AppsFaceGrid.drawBox(for: cell, isFolder: true) == cell)
    }

    @Test("folderBoxIsTheCell: a 2×2 app box is 334 px on the 824 px shape, the folder box 269 px; single: 614 vs 494")
    func folderBoxIsTheCell() {
        let shape = CGRect(x: 100, y: 100, width: 824, height: 824)
        let cell = AppsFaceGrid.cells(count: 2)[0]
        let appBox = AppsFaceGrid.rect(AppsFaceGrid.drawBox(for: cell, isFolder: false), in: shape, yUp: false)
        let folderBox = AppsFaceGrid.rect(AppsFaceGrid.drawBox(for: cell, isFolder: true), in: shape, yUp: false)
        close(appBox.width, 334, 1.0)
        close(folderBox.width, 269, 1.0)
        // Independent pins, not derived from the seam: the first cell of a 2×2, and the single
        // centred cell, on a 1024 canvas.
        close(folderBox.minX, 223.6, 0.5); close(folderBox.minY, 223.6, 0.5)
        let single = AppsFaceGrid.cells(count: 1)[0]
        let singleFolder = AppsFaceGrid.rect(AppsFaceGrid.drawBox(for: single, isFolder: true), in: shape, yUp: false)
        let singleApp = AppsFaceGrid.rect(AppsFaceGrid.drawBox(for: single, isFolder: false), in: shape, yUp: false)
        close(singleFolder.minX, 264.8, 0.5); close(singleFolder.width, 494.4, 0.5)
        close(singleApp.width, 614.4, 1.0); close(singleApp.midX, 512, 0.5)
    }

    @Test("rect(in:yUp:) flips the vertical axis for AppKit bitmaps")
    func rectMapping() {
        let shape = CGRect(x: 0, y: 0, width: 100, height: 100)
        let unit = CGRect(x: 0.1, y: 0.2, width: 0.3, height: 0.3)
        let down = AppsFaceGrid.rect(unit, in: shape, yUp: false)
        let up = AppsFaceGrid.rect(unit, in: shape, yUp: true)
        close(down.minY, 20); close(up.minY, 50)          // 100 − (20 + 30)
        close(down.minX, up.minX); close(down.width, 30)
    }

    @Test("miniShadowMagnitudes: the contact shadow is 0.35 / 6 px / 12 px at 1024 and absent below the detail gate")
    func miniShadowMagnitudes() throws {
        let s = try #require(AppsFaceGrid.miniShadow(nominalSize: 1024))
        #expect(s == IconDepthMetrics.GlyphShadow(blackAlpha: 0.35, offset: 6, blur: 12))
        let small = try #require(AppsFaceGrid.miniShadow(nominalSize: 256))
        close(small.offset, 1.5); close(small.blur, 3)
        #expect(AppsFaceGrid.miniShadow(nominalSize: 16) == nil)
        #expect(AppsFaceGrid.miniShadow(nominalSize: IconDepthMetrics.minDetailSize) != nil)
    }

    @Test("Material: the system gray pairs by style, grayscale minis for Clear/Tinted")
    func material() {
        for style in [IconStyle.defaultStyle, .clear, .tinted] {
            let g = AppsFaceGrid.fillGrays(style: style)
            #expect(g.top == 1.0 && g.bottom == 0.925, "\(style): \(g)")
        }
        let dark = AppsFaceGrid.fillGrays(style: .dark)
        #expect(dark.top == 0.192 && dark.bottom == 0.078)
        #expect(AppsFaceGrid.lightGrays.top == 1.0 && AppsFaceGrid.darkGrays.bottom == 0.078)
        #expect(!AppsFaceGrid.desaturatesMinis(style: .defaultStyle) && !AppsFaceGrid.desaturatesMinis(style: .dark))
        #expect(AppsFaceGrid.desaturatesMinis(style: .clear) && AppsFaceGrid.desaturatesMinis(style: .tinted))
    }

    @Test("Selection skips missing items so the next installed one takes the cell, caps at nine, counts the skipped")
    func selection() {
        let items = (1...12).map { AppItem(bundleIdentifier: "com.example.\($0)", name: "\($0)") }
        let missing: Set<String> = ["com.example.2", "com.example.11"]
        let out = AppsFaceGrid.select(items: items) { !missing.contains($0.bundleIdentifier) }
        #expect(out.selected.map(\.bundleIdentifier) == ["com.example.1", "com.example.3", "com.example.4", "com.example.5",
                                                        "com.example.6", "com.example.7", "com.example.8", "com.example.9", "com.example.10"])
        #expect(out.skipped == 2)
    }

    @Test("allMissingSelectsNothing: zero installed → empty selection (the caller falls back to the glyph face)")
    func allMissingSelectsNothing() {
        let items = [AppItem(bundleIdentifier: "a", name: "A"), AppItem(bundleIdentifier: "b", name: "B")]
        let out = AppsFaceGrid.select(items: items) { _ in false }
        #expect(out.selected.isEmpty && out.skipped == 2)
        #expect(AppsFaceGrid.select(items: [], isInstalled: { _ in true }).selected.isEmpty)
    }
}
