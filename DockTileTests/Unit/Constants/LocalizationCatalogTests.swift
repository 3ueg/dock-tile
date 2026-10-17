//
//  LocalizationCatalogTests.swift
//  DockTileTests
//
//  Guards the String Catalog against the regressions a machine-first translation pipeline invites.
//  Reads the repo through #filePath like AppStringsTests; reads the built product through Bundle.main
//  (the test host IS the dev app).
//

import Testing
import Foundation
@testable import Dock_Tile

@Suite("Localization catalog")
struct LocalizationCatalogTests {
    @Test("The catalog ships in the bundle; InfoPlist.strings deliberately does not")
    func catalogShipsAndInfoPlistStringsDoesNot() {
        // Until 2026-10-17 neither .xcstrings was in the target — no .lproj ever shipped.
        #expect(Bundle.main.url(forResource: "Localizable", withExtension: "strings",
                                subdirectory: nil, localization: "en-GB") != nil)
        // A localized InfoPlist.strings overrides Info.plist for Launch Services, and helper
        // bundles are copies with CFBundleName rewritten to the tile's name — shipping it would
        // make every tile read "Dock Tile" in ⌘Tab and Finder. It stays out on purpose.
        #expect(Bundle.main.url(forResource: "InfoPlist", withExtension: "strings") == nil)
    }
}
