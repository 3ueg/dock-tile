import Foundation
import Testing
@testable import Dock_Tile

/// Guards the in-app Tinted tile face (issue #22). macOS draws the Tinted style in a colour no
/// public API exposes, so the app shows the icon macOS itself renders for the tile's helper —
/// but ONLY while that helper was built from the tile's current look. Failing values: a helper
/// built from an older look (edits not yet applied with Update) shown as if current; a helper
/// with no recorded look trusted; the system icon shown outside Tinted.
@Suite("Tile face (Tinted system icon)")
struct TileFaceTests {

    // MARK: - iconSignature

    @Test("Every field that shapes the Dock icon changes the signature")
    func everyIconFieldCounts() {
        let base = DockTileConfiguration(name: "Dev", tintColor: .preset(.blue), iconType: .sfSymbol,
                                         iconValue: "star", iconScale: 14, iconWeight: .medium,
                                         background: .colour)
        var variants: [DockTileConfiguration] = []
        var v = base; v.tintColor = .preset(.red); variants.append(v)
        v = base; v.tintColor = .custom("#123456"); variants.append(v)
        v = base; v.iconType = .emoji; variants.append(v)
        v = base; v.iconValue = "heart"; variants.append(v)
        v = base; v.iconScale = 15; variants.append(v)
        v = base; v.iconWeight = .bold; variants.append(v)
        v = base; v.background = .mono; variants.append(v)
        for variant in variants {
            #expect(variant.iconSignature != base.iconSignature)
        }
        #expect(Set(variants.map(\.iconSignature)).count == variants.count)
    }

    @Test("Fields that don't reach the Dock icon leave the signature alone")
    func nonIconFieldsIgnored() {
        let base = DockTileConfiguration(name: "Dev", iconFace: .glyph)
        var other = base
        other.name = "Renamed"
        other.layoutMode = .list
        other.isVisibleInDock = false
        other.showInAppSwitcher = true
        other.appItems = [AppItem(bundleIdentifier: "com.example.one", name: "One")]
        #expect(other.iconSignature == base.iconSignature)
    }

    @Test("Two tiles with the same look share a signature (stable, not per-instance)")
    func sameLookSameSignature() {
        let a = DockTileConfiguration(name: "A", tintColor: .custom("#FF5733"), iconValue: "bolt", iconFace: .glyph)
        let b = DockTileConfiguration(name: "B", tintColor: .custom("#FF5733"), iconValue: "bolt", iconFace: .glyph)
        #expect(a.id != b.id)
        #expect(a.iconSignature == b.iconSignature)
        #expect(a.iconSignature == "#FF5733|sfSymbol|bolt|\(a.iconScale)|\(a.iconWeight.rawValue)|colour")
    }

    @Test("The glyph face leaves existing signatures byte-identical; Apps appends the face and the first nine identities")
    func appsFaceJoinsTheSignature() {
        let items = (1...10).map { AppItem(bundleIdentifier: "com.example.app\($0)", name: "App \($0)") }
        var glyph = DockTileConfiguration(name: "Work", tintColor: .custom("#FF5733"), iconValue: "bolt", iconFace: .glyph, appItems: items)
        let glyphSignature = glyph.iconSignature
        #expect(glyphSignature == "#FF5733|sfSymbol|bolt|\(glyph.iconScale)|medium|colour")

        glyph.iconFace = .apps
        let nine = (1...9).map { "com.example.app\($0)" }.joined(separator: ",")
        #expect(glyph.iconSignature == glyphSignature + "|apps|" + nine)
        #expect(glyph.appsFaceIdentities.count == 9)
    }

    @Test("On the Apps face the list order, a removal and a folder path all move the signature")
    func appsFaceListChangesMoveTheSignature() {
        let a = AppItem(bundleIdentifier: "com.example.a", name: "A")
        let b = AppItem(bundleIdentifier: "com.example.b", name: "B")
        let folder = AppItem(bundleIdentifier: "folder.1", name: "Docs", isFolder: true, folderPath: "/Users/x/Docs")
        let base = DockTileConfiguration(name: "Work", iconFace: .apps, appItems: [a, b, folder])
        var reordered = base; reordered.appItems = [b, a, folder]
        var removed = base; removed.appItems = [a, folder]
        var moved = base; moved.appItems = [a, b, AppItem(bundleIdentifier: "folder.1", name: "Docs", isFolder: true, folderPath: "/Users/x/Docs2")]
        #expect(Set([base, reordered, removed, moved].map(\.iconSignature)).count == 4)
        #expect(base.iconSignature.hasSuffix("|apps|com.example.a,com.example.b,/Users/x/Docs"))
    }

    // MARK: - Helper Info.plist stamp

    @Test("The helper's Info.plist records the look it was built from")
    func plistRecordsLook() {
        let out = HelperBundleManager.helperInfoPlist(
            from: ["CFBundleIdentifier": "com.docktile.app"], bundleId: "com.docktile.helper.x",
            appName: "Dev", showInAppSwitcher: false, declarative: true, iconSignature: "sig-1")
        #expect(out[HelperBundleManager.iconSignatureKey] as? String == "sig-1")
        #expect(HelperBundleManager.iconSignatureKey == "DTIconSignature")
    }

    // MARK: - showsSystemIcon

    @Test("Tinted or Clear + helper built from this look → the system's own icon")
    func tintedOrClearMatchShowsSystem() {
        #expect(TileFace.showsSystemIcon(style: .tinted, helperSignature: "s", tileSignature: "s"))
        #expect(TileFace.showsSystemIcon(style: .clear, helperSignature: "s", tileSignature: "s"))
    }

    @Test("Tinted or Clear but the helper is stale, unstamped or absent → our own drawing")
    func tintedOrClearMismatchDraws() {
        for style in [IconStyle.tinted, .clear] {
            #expect(!TileFace.showsSystemIcon(style: style, helperSignature: "old", tileSignature: "new"))
            #expect(!TileFace.showsSystemIcon(style: style, helperSignature: nil, tileSignature: "new"))
        }
    }

    @Test("Default and Dark keep our own drawing, even with a current helper")
    func otherStylesDraw() {
        for style in [IconStyle.defaultStyle, .dark] {
            #expect(!TileFace.showsSystemIcon(style: style, helperSignature: "s", tileSignature: "s"))
        }
    }
}
