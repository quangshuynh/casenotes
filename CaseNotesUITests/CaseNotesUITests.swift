//
//  CaseNotesUITests.swift
//  CaseNotesUITests
//
//  Created by q on 8/27/26.
//

import XCTest

/// End-to-end coverage for the one behavior unit tests cannot reach: that a
/// launched app really does put the lock in front of the notes.
///
/// Everything else worth asserting about notes, folders, Markdown, export, and
/// drawings is covered by unit tests, which are faster and do not depend on the
/// state of a particular simulator.
final class CaseNotesUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    /// The app must never show note content before the user authenticates.
    ///
    /// Assertions use `exists` rather than hit testing on purpose: when the
    /// simulator has biometry enrolled, the system authentication sheet is
    /// covering the app's own interface at this point, and the test should pass
    /// either way.
    @MainActor
    func testLaunchingShowsTheLockScreenAndNoNotes() throws {
        let app = XCUIApplication()
        app.launch()

        XCTAssertTrue(
            app.staticTexts["CaseNotes Locked"].waitForExistence(timeout: 30),
            "The lock screen should be presented on launch."
        )
        XCTAssertTrue(
            app.buttons["Unlock"].exists,
            "A locked app should offer a way to authenticate."
        )
        XCTAssertFalse(
            app.searchFields["Search notes"].exists,
            "Notes must not be reachable before authenticating."
        )
        XCTAssertFalse(
            app.buttons["New Note"].exists,
            "Note creation must not be reachable before authenticating."
        )
    }
}
