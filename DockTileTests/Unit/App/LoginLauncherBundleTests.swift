//
//  LoginLauncherBundleTests.swift
//  DockTileTests
//
//  Each build must carry ONLY its own start-at-login launcher plist. Until 2026-10-18 one Copy Files
//  phase bundled both (`com.docktile.app…` and `com.docktile.dev.app…`) into every build, including
//  the shipped release. Inert — SMAppService registers by the exact `<bundleId>.tilelauncher.plist`
//  name — but a release app should not ship a dev agent. The per-configuration exclusion lives in
//  Dev.xcconfig / Release.xcconfig (`EXCLUDED_SOURCE_FILE_NAMES`).
//
//  Two guards: the built test host (the dev app) proves the Debug side end to end; the config-text
//  test pins BOTH sides, including Release, which no test can build here.
//  If `onlyOwnLauncherPlist` fails on an old local build: Copy Files never deletes a file an earlier
//  build put there — clean the build product (CI always builds clean).
//

import Testing
import Foundation
@testable import Dock_Tile

@Suite("Login launcher bundling")
struct LoginLauncherBundleTests {
    private static let root = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent().deletingLastPathComponent()

    @Test("The built app carries exactly its own launcher plist")
    func onlyOwnLauncherPlist() throws {
        let dir = Bundle.main.bundleURL.appendingPathComponent("Contents/Library/LaunchAgents")
        let names = try FileManager.default.contentsOfDirectory(atPath: dir.path).sorted()
        #expect(names == ["\(AppEnvironment.mainAppBundleId).tilelauncher.plist"])
    }

    @Test("Each configuration excludes the OTHER build's launcher plist", arguments: [
        ("Dev.xcconfig", "com.docktile.app.tilelauncher.plist"),
        ("Release.xcconfig", "com.docktile.dev.app.tilelauncher.plist"),
    ])
    func configExcludesOtherPlist(file: String, excluded: String) throws {
        let url = Self.root.appendingPathComponent("DockTile/Config/\(file)")
        let lines = try String(contentsOf: url, encoding: .utf8).split(separator: "\n")
        let setting = try #require(lines.first { $0.hasPrefix("EXCLUDED_SOURCE_FILE_NAMES") })
        #expect(setting.split(separator: "=").last?.trimmingCharacters(in: .whitespaces) == excluded)
    }
}
