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

    /// Every localization the app ships. Pinned so dropping or adding one is a deliberate edit here.
    static let languages: Set<String> = ["en-AU", "en-GB", "en-US"]
    static let source = "en-GB"

    static let repoRoot: String = {
        var url = URL(fileURLWithPath: #filePath)
        for _ in 0..<4 { url.deleteLastPathComponent() }   // file → Constants → Unit → DockTileTests
        return url.path
    }()

    static func catalog() throws -> [String: [String: Any]] {
        let data = try Data(contentsOf: URL(fileURLWithPath: repoRoot + "/DockTile/Resources/Localizable.xcstrings"))
        let json = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        return try #require(json["strings"] as? [String: [String: Any]])
    }

    static func localizations(_ entry: [String: Any]) -> [String: String] {
        guard let locs = entry["localizations"] as? [String: [String: Any]] else { return [:] }
        var out: [String: String] = [:]
        for (lang, loc) in locs {
            if let unit = loc["stringUnit"] as? [String: Any], let value = unit["value"] as? String {
                out[lang] = value
            }
        }
        return out
    }

    static func codeKeys() throws -> Set<String> {
        let path = repoRoot + "/DockTile/Constants/AppStrings.swift"
        let text = try String(contentsOfFile: path, encoding: .utf8)
        let regex = try NSRegularExpression(pattern: #"NSLocalizedString\(\s*"([^"]+)""#)
        let matches = regex.matches(in: text, range: NSRange(text.startIndex..., in: text))
        return Set(matches.compactMap { Range($0.range(at: 1), in: text).map { String(text[$0]) } })
    }

    /// `%@`, `%d`, `%lld`, `%1$@`, `%.1f` … in order of appearance.
    static func specifiers(_ value: String) -> [String] {
        let regex = try! NSRegularExpression(pattern: #"%(?:\d+\$)?[0-9.]*(?:ll|l|h)?[@dfsux]"#)
        return regex.matches(in: value, range: NSRange(value.startIndex..., in: value))
            .compactMap { Range($0.range, in: value).map { String(value[$0]) } }
    }

    @Test("Every key AppStrings references exists in the catalog")
    func codeKeysExistInCatalog() throws {
        let missing = try Self.codeKeys().subtracting(try Self.catalog().keys)
        #expect(missing.isEmpty, "run: python3 -I Scripts/l10n/l10n.py sync-keys — missing \(missing.sorted())")
    }

    @Test("The catalog's language set is exactly the pinned one")
    func languageSetIsPinned() throws {
        var found: Set<String> = []
        for entry in try Self.catalog().values { found.formUnion(Self.localizations(entry).keys) }
        #expect(found == Self.languages)
    }

    @Test("Every language has every key, with a non-empty value")
    func everyLanguageHasEveryKey() throws {
        var gaps: [String] = []
        for (key, entry) in try Self.catalog() {
            let locs = Self.localizations(entry)
            for lang in Self.languages where (locs[lang] ?? "").isEmpty { gaps.append("\(lang):\(key)") }
        }
        #expect(gaps.isEmpty, "\(gaps.sorted())")
    }

    @Test("Format placeholders survive translation in every language")
    func formatSpecifiersMatchSource() throws {
        var broken: [String] = []
        for (key, entry) in try Self.catalog() {
            let locs = Self.localizations(entry)
            let expected = Self.specifiers(locs[Self.source] ?? "").sorted()
            for (lang, value) in locs where Self.specifiers(value).sorted() != expected {
                broken.append("\(lang):\(key)")
            }
        }
        #expect(broken.isEmpty, "\(broken.sorted())")
    }

    @Test("The specifier scanner sees the shapes the app uses")
    func specifierScanner() {
        #expect(Self.specifiers("Version %@") == ["%@"])
        #expect(Self.specifiers("%lld apps in %@") == ["%lld", "%@"])
        #expect(Self.specifiers("%2$@ before %1$@") == ["%2$@", "%1$@"])
        #expect(Self.specifiers("100% done") == [])
    }
}
