#!/usr/bin/env swift
// Synthetic Apps-face layer: nine flat coloured rounded squares on the spike's 3×3 grid.
// Usage: swift make-appgrid-layer.swift <output.png>
import AppKit

let canvas = 1024
let cellOrigins: [CGFloat] = [224, 429, 634]        // 100 + 124 + k × (166 + 39)
let cell: CGFloat = 166
let colours: [NSColor] = [.systemRed, .systemOrange, .systemYellow, .systemGreen, .systemTeal,
                          .systemBlue, .systemIndigo, .systemPurple, .systemGray]

guard CommandLine.arguments.count == 2 else { fputs("usage: make-appgrid-layer.swift <output.png>\n", stderr); exit(2) }
guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: canvas, pixelsHigh: canvas, bitsPerSample: 8,
                                 samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                 colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0),
      let ctx = NSGraphicsContext(bitmapImageRep: rep) else { exit(1) }
rep.size = CGSize(width: canvas, height: canvas)
let cg = ctx.cgContext
cg.clear(CGRect(x: 0, y: 0, width: canvas, height: canvas))
for (i, colour) in colours.enumerated() {
    // Bitmap contexts are y-up: row 0 of the grid is the TOP, so flip the row index.
    let x = cellOrigins[i % 3]
    let y = CGFloat(canvas) - cellOrigins[i / 3] - cell
    let path = CGPath(roundedRect: CGRect(x: x, y: y, width: cell, height: cell),
                      cornerWidth: cell * 0.225, cornerHeight: cell * 0.225, transform: nil)
    cg.addPath(path)
    cg.setFillColor(colour.usingColorSpace(.sRGB)!.cgColor)
    cg.fillPath()
}
guard let png = rep.representation(using: .png, properties: [:]) else { exit(1) }
try! png.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
