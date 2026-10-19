//  AppIconLoaderSymlinkTests.swift — /Applications/Safari.app is a symlink on macOS 27 and
//  NSWorkspace.icon(forFile:) on a symlink returns the icon with an alias-arrow badge.
import AppKit
import Testing
@testable import Dock_Tile

@MainActor
@Suite("AppIconLoader symlink resolution")
struct AppIconLoaderSymlinkTests {
    private func png(_ image: NSImage) throws -> Data {
        var rect = CGRect(x: 0, y: 0, width: 128, height: 128)
        let cg = try #require(image.cgImage(forProposedRect: &rect, context: nil, hints: nil))
        return try #require(NSBitmapImageRep(cgImage: cg).representation(using: .png, properties: [:]))
    }

    @Test("symlinkedAppIconHasNoAliasBadge: a symlink to Finder yields Finder's own icon bytes")
    func symlinkedAppIconHasNoAliasBadge() throws {
        let real = "/System/Library/CoreServices/Finder.app"
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let link = dir.appendingPathComponent("Finder.app")
        try FileManager.default.createSymbolicLink(atPath: link.path, withDestinationPath: real)

        // A bundle id Launch Services cannot resolve, so the loader takes the last-known-path branch.
        let item = AppItem(bundleIdentifier: "com.example.not-registered", name: "Finder", lastKnownPath: link.path)
        let viaLink = try png(try #require(AppIconLoader.icon(for: item)))
        let direct = try png(NSWorkspace.shared.icon(forFile: real))
        #expect(viaLink == direct)
        // Control (the badge was observed on macOS 27; earlier OSes are unverified, so only pin it
        // there): without the fix the loader returned exactly these alias-badged bytes.
        if #available(macOS 27.0, *) {
            let badged = try png(NSWorkspace.shared.icon(forFile: link.path))
            #expect(badged != direct, "the control is broken: the symlink's icon should carry an alias badge")
        }
    }
}
