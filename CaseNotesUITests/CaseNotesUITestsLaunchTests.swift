//
//  CaseNotesUITestsLaunchTests.swift
//  CaseNotesUITests
//
//  Created by q on 8/27/26.
//

import XCTest

/// Captures a launch screenshot for each target application UI configuration.
///
/// Kept as an attachment-producing smoke test: it proves the app launches
/// without crashing and leaves an artifact worth looking at after a run.
final class CaseNotesUITestsLaunchTests: XCTestCase {
    override class var runsForEachTargetApplicationUIConfiguration: Bool {
        true
    }

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testLaunch() throws {
        let app = XCUIApplication()
        app.launch()

        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "Launch Screen"
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
