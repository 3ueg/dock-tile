//
//  IconLiftTests.swift
//  DockTileTests
//
//  The App Store-style lift (rim + shadow) on every tile icon in the app scales with the icon's
//  size. The 122 pt row pins the Tile Detail hero exactly as it shipped (rim 1, shadow 8 / 4,
//  0.45 dark / 0.16 light), so a change to the small-size curve cannot silently restyle the hero.
//

import Testing
import CoreGraphics
@testable import Dock_Tile

@Suite("Icon lift metrics")
struct IconLiftTests {

    @Test("Hero (122 pt) keeps the shipped values")
    func hero() {
        #expect(IconLift.metrics(size: 122) == IconLift.Metrics(rimWidth: 1, shadowRadius: 8, shadowY: 4,
                                                                 darkOpacity: 0.45, lightOpacity: 0.16))
    }

    @Test("Small icons get a hairline rim and a scaled, fainter shadow", arguments: [
        (CGFloat(58), CGFloat(4), CGFloat(2)),
        (CGFloat(44), CGFloat(3), CGFloat(1.5)),
        (CGFloat(32), CGFloat(2), CGFloat(1)),
        (CGFloat(24), CGFloat(1.5), CGFloat(1))
    ])
    func small(size: CGFloat, radius: CGFloat, y: CGFloat) {
        #expect(IconLift.metrics(size: size) == IconLift.Metrics(rimWidth: 0.5, shadowRadius: radius, shadowY: y,
                                                                  darkOpacity: 0.32, lightOpacity: 0.14))
    }

    @Test("Light Mode's hairline is 0.5 at every size (the shipped hero's value)")
    func lightHairline() {
        #expect(IconLift.lightHairline == 0.5)
    }

    @Test("64 pt is the first size drawn like the hero")
    func threshold() {
        #expect(IconLift.metrics(size: 63).rimWidth == 0.5)
        #expect(IconLift.metrics(size: 64).rimWidth == 1)
        #expect(IconLift.metrics(size: 64).darkOpacity == 0.45)
    }
}
