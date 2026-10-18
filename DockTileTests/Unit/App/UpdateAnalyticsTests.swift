//
//  UpdateAnalyticsTests.swift
//  DockTileTests
//
//  Guards the mapping from Sparkle callbacks to the update analytics events. These events exist to
//  answer one question (2026-10-18): why do most users stay on old versions? A wrong mapping would
//  answer it wrongly — above all, counting Sparkle's routine "no update found" (error 1001, which it
//  ALSO reports through didAbortWithError) as a failed check would flood `update_check` with errors.
//

import Testing
import Foundation
import Sparkle
@testable import Dock_Tile

@Suite("Update analytics mapping")
struct UpdateAnalyticsTests {
    @Test("Sparkle's 'no update found' abort is not counted again as an error")
    func noUpdateAbortIsNotAnError() {
        let noUpdate = NSError(domain: SUSparkleErrorDomain, code: 1001)
        #expect(UpdateAnalytics.abortResult(for: noUpdate) == nil)
    }

    @Test("A declined or deferred install authorization is 'declined', not an error")
    func declinedAuthorizationIsNotAnError() {
        // Under silent installs a Mac that needs an admin password asks the user; saying no (4007)
        // or "later" (4008) is a choice, and counting it as an error would blur the update signal.
        #expect(UpdateAnalytics.abortResult(for: NSError(domain: SUSparkleErrorDomain, code: 4007)) == "declined")
        #expect(UpdateAnalytics.abortResult(for: NSError(domain: SUSparkleErrorDomain, code: 4008)) == "declined")
    }

    @Test("A real abort counts as an error, whatever its domain")
    func realAbortIsAnError() {
        #expect(UpdateAnalytics.abortResult(for: NSError(domain: SUSparkleErrorDomain, code: 2001)) == "error")
        #expect(UpdateAnalytics.abortResult(for: NSError(domain: NSURLErrorDomain, code: -1009)) == "error")
        // 1001 from another domain is NOT Sparkle's no-update signal.
        #expect(UpdateAnalytics.abortResult(for: NSError(domain: NSURLErrorDomain, code: 1001)) == "error")
    }

    @Test("Each user choice maps to its own stable value", arguments: [
        (SPUUserUpdateChoice.install, "install"),
        (SPUUserUpdateChoice.skip, "skip"),
        (SPUUserUpdateChoice.dismiss, "dismiss"),
    ])
    func choiceValues(choice: SPUUserUpdateChoice, value: String) {
        #expect(UpdateAnalytics.choiceValue(choice) == value)
    }

    @Test("The three update events are registered with Firebase-safe names")
    func eventNames() {
        #expect(AnalyticsEvent.updateCheck.rawValue == "update_check")
        #expect(AnalyticsEvent.updateChoice.rawValue == "update_choice")
        #expect(AnalyticsEvent.updateInstalling.rawValue == "update_installing")
    }
}
