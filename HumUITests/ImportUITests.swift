// Copyright 2026 The Hum Authors
// SPDX-License-Identifier: Apache-2.0

import XCTest

/// Importing setups: a big real-world file (Merge and Replace), Undo, and broken files.
/// The big file is TestFixtures/Local/Express2-v2.hum (not in git); those tests skip without it.
final class ImportUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    /// A small file written for this test. The simulator can read the Mac's temporary folder.
    private func writeTemp(_ name: String, _ contents: String) throws -> String {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(name)
        try Data(contents.utf8).write(to: url)
        return url.path
    }

    @MainActor
    private func bigFixture() throws -> String {
        guard let path = Self.localFixture("Express2-v2.hum") else {
            throw XCTSkip("Put Express2-v2.hum in TestFixtures/Local to run this test")
        }
        return path
    }

    /// Waits for the import sheet to finish and close (1,581 pictures take ~20 s on a simulator).
    @MainActor
    private func applyAndWait(_ app: XCUIApplication) {
        el(app, "applyImport").tap()
        XCTAssertTrue(el(app, "applyImport").waitForNonExistence(timeout: 180), "The import should finish and close")
    }

    /// Scenario: the preview tells the parent what will change before anything does.
    @MainActor
    func testPreviewSummarizesTheBigFile() throws {
        let app = launchHum(["-skipFirstRun", "-startInParent", "-importFile", try bigFixture()])
        let summary = el(app, "importSummary")
        XCTAssertTrue(summary.waitForExistence(timeout: 30))
        // 1,866 tiles from the file, plus the folder tile on Home that opens the file's Home (HUM-001).
        XCTAssertEqual(summary.label, "115 new boards, 1867 new tiles, 0 changed tiles, 0 removed. No tiles will move. "
                       + "The file's Home becomes a folder called “Express2-v2” on your Home.")
        // HUM-011: folder tiles say so, instead of empty quotes; the list says how many more there are.
        XCTAssertFalse(app.staticTexts["Chat: “”"].exists)
        let chat = app.staticTexts["Chat (opens a folder)"]
        scrollTo(app, chat)
        XCTAssertTrue(chat.exists)
        app.buttons["Cancel"].firstMatch.tap()
        XCTAssertTrue(el(app, "editTile.hi").waitForExistence(timeout: 3), "Cancel changes nothing")
    }

    /// Scenario: a parent merges a whole setup into the starter board (the default choice).
    /// The child must be able to reach what was imported.
    @MainActor
    func testMergedSetupIsReachableFromHome() throws {
        let app = launchHum(["-skipFirstRun", "-startInParent", "-importFile", try bigFixture()])
        XCTAssertTrue(el(app, "importSummary").waitForExistence(timeout: 30))
        applyAndWait(app)
        XCTAssertTrue(el(app, "editTile.hi").exists, "The starter tiles stay where they were")
        // HUM-001 and HUM-027: a folder tile on Home opens the file's Home, and a banner says where it went.
        XCTAssertTrue(el(app, "importBanner").waitForExistence(timeout: 5), "A banner says where the boards went")
        shot(app, "after merge")
        XCTAssertTrue(el(app, "editTile.Express2-v2").exists, "A folder tile on Home opens the imported setup")
        el(app, "openImported").tap()
        XCTAssertTrue(app.staticTexts["Editing Express2-v2"].waitForExistence(timeout: 5))
        el(app, "boardsMenu").tap()
        let homes = app.buttons.matching(NSPredicate(format: "label == 'Home'"))
        XCTAssertTrue(homes.firstMatch.waitForExistence(timeout: 3))
        XCTAssertEqual(homes.count, 1, "Only one board is called Home")
    }

    /// Scenario: "Replace everything" asks first, then the child's Home is the file's Home, shown in
    /// pages on iPhone, and its folders open.
    @MainActor
    func testReplaceEverythingThenUndo() throws {
        // UI-test launches turn the iPhone page layout off unless asked for.
        let app = launchHum(["-skipFirstRun", "-startInParent", "-importFile", try bigFixture()] + (isPad ? [] : ["-phoneLayout"]))
        XCTAssertTrue(el(app, "importSummary").waitForExistence(timeout: 30))
        app.buttons["Replace everything"].firstMatch.tap()
        el(app, "applyImport").tap()
        XCTAssertTrue(app.staticTexts["Replace all your boards?"].waitForExistence(timeout: 3), "Replace must ask first")
        dialogButton(app, "Replace everything").tap()
        XCTAssertTrue(el(app, "applyImport").waitForNonExistence(timeout: 180))
        XCTAssertFalse(el(app, "editTile.hi").exists, "The starter board is replaced")

        finishEditing(app)
        let chat = el(app, "tile.Chat")
        XCTAssertTrue(chat.waitForExistence(timeout: 10), "The file's Home is now the child's Home")
        shot(app, "child home after replace")
        if !isPad {
            XCTAssertGreaterThanOrEqual(chat.frame.width, 88, "On iPhone the 6 × 8 Home is shown in pages with big tiles")
        }
        chat.tap()
        XCTAssertTrue(el(app, "back").waitForExistence(timeout: 3))
        XCTAssertTrue(el(app, "back").isHittable, "A folder opened")
        shot(app, "chat folder")

        // Undo brings the old boards back (the backup promised in the dialog).
        el(app, "home").tap()
        openParentMode(app)
        tapUndo(app)
        XCTAssertTrue(el(app, "editTile.hi").waitForExistence(timeout: 30), "Undo restores the starter board (HUM-038)")
    }

    /// Scenario: a broken file shows a friendly message and changes nothing.
    @MainActor
    func testBrokenFileIsExplained() throws {
        let path = try writeTemp("broken.hum", "this is not a zip file")
        let app = launchHum(["-skipFirstRun", "-startInParent", "-importFile", path])
        let alert = app.alerts["This file couldn't be imported"]
        XCTAssertTrue(alert.waitForExistence(timeout: 10))
        shot(app, "broken file")
        alert.buttons["OK"].tap()
        XCTAssertTrue(el(app, "editTile.hi").exists)
    }

    /// Scenario: a file from a newer Hum asks the parent to update, in plain words.
    @MainActor
    func testNewerFormatAsksToUpdate() throws {
        let path = try writeTemp("future.json", #"{"formatVersion": 99, "boards": []}"#)
        let app = launchHum(["-skipFirstRun", "-startInParent", "-importFile", path])
        let alert = app.alerts["This file couldn't be imported"]
        XCTAssertTrue(alert.waitForExistence(timeout: 10))
        XCTAssertTrue(alert.staticTexts.matching(NSPredicate(format: "label CONTAINS[c] 'update Hum'")).firstMatch.exists,
                      "Should say the file needs a newer Hum")
    }

    /// Scenario: a file with a tile that has no words gets the friendly validation message.
    @MainActor
    func testInvalidTileIsNamed() throws {
        let json = """
        {"formatVersion": 1, "boards": [{"id": "6F1C2D4E-1111-4A1A-9C1A-1A2B3C4D5E6F", "name": "Home", "rows": 2, "columns": 2,
          "isHome": true, "tiles": [{"id": "6F1C2D4E-2222-4A1A-9C1A-1A2B3C4D5E6F", "label": "snack", "spokenText": "", "row": 0, "column": 0}]}]}
        """
        let path = try writeTemp("nowords.json", json)
        let app = launchHum(["-skipFirstRun", "-startInParent", "-importFile", path])
        let alert = app.alerts["This file couldn't be imported"]
        XCTAssertTrue(alert.waitForExistence(timeout: 10))
        shot(app, "invalid tile")
        XCTAssertTrue(alert.staticTexts.matching(NSPredicate(format: "label CONTAINS 'snack'")).firstMatch.exists,
                      "The message names the tile")
    }

    /// Scenario: an import that arrives while the child is using Hum waits for grown-up mode.
    @MainActor
    func testImportWaitsForParentMode() throws {
        let path = try writeTemp("one.json", """
        {"formatVersion": 1, "boards": [{"id": "6F1C2D4E-1111-4A1A-9C1A-1A2B3C4D5E6F", "name": "Trains", "rows": 2, "columns": 2,
          "isHome": false, "tiles": [{"id": "6F1C2D4E-2222-4A1A-9C1A-1A2B3C4D5E6F", "label": "all aboard", "spokenText": "All aboard!", "row": 0, "column": 0}]}]}
        """)
        let app = launchHum(["-skipFirstRun", "-importFile", path])
        XCTAssertTrue(el(app, "tile.hi").waitForExistence(timeout: 5))
        XCTAssertFalse(el(app, "importSummary").waitForExistence(timeout: 3), "The child never sees the import preview")
        openParentMode(app)
        XCTAssertTrue(el(app, "importSummary").waitForExistence(timeout: 5), "The preview shows once a parent opens edit mode")
    }
}
