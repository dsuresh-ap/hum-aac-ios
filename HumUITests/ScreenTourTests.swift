// Copyright 2026 The Hum Authors
// SPDX-License-Identifier: Apache-2.0

import XCTest

/// Walks every screen and keeps a screenshot of each in the test results, for a person to review the
/// layout, text and sizes by eye (Xcode → Report navigator → the test → Attachments).
/// These only check that each screen can be reached; the behavior checks live in the other test files.
final class ScreenTourTests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = true
    }

    @MainActor
    func testTourFirstRun() {
        let app = launchHum()
        shot(app, "01 welcome")
        el(app, "firstRun.start").tap()
        shot(app, "02 voice")
        app.buttons["Next"].firstMatch.tap()
        shot(app, "03 grid size")
        app.buttons["Next"].firstMatch.tap()
        shot(app, "04 start choice")
        el(app, "firstRun.starter").tap()
        XCTAssertTrue(el(app, "tile.hi").waitForExistence(timeout: 5))
        shot(app, "05 starter board")
    }

    @MainActor
    func testTourChildMode() {
        let app = launchHum(["-skipFirstRun", "-demoFolder", "-demoHistory"])
        XCTAssertTrue(el(app, "tile.hi").waitForExistence(timeout: 5))
        shot(app, "10 child home with history")
        el(app, "editGate").press(forDuration: 1.5)
        shot(app, "11 lock half held")
        el(app, "tile.snack").tap()
        XCTAssertTrue(el(app, "tile.crackers").waitForExistence(timeout: 3))
        shot(app, "12 folder open")
        app.terminate()

        let dark = launchHum(["-skipFirstRun", "-darkMode"])
        XCTAssertTrue(el(dark, "tile.hi").waitForExistence(timeout: 5))
        shot(dark, "13 child dark")
    }

    @MainActor
    func testTourEditor() {
        let app = launchHum(["-skipFirstRun", "-demoFolder"])
        openParentMode(app)
        shot(app, "20 editor")
        el(app, "addMenu").tap()
        shot(app, "21 add menu")
        app.buttons["New tile"].firstMatch.tap()
        XCTAssertTrue(el(app, "spokenTextField").waitForExistence(timeout: 3))
        shot(app, "22 new tile empty")
        el(app, "spokenTextField").typeText("Let's go to the playground!")
        shot(app, "23 new tile typed")
        // Swipe the form itself: with the keyboard up, iOS 18 doesn't scroll it for a swipe on the app.
        let more = app.buttons["More options"].firstMatch
        for _ in 0..<6 where !(more.exists && more.isHittable) {
            app.cells.allElementsBoundByIndex.first { $0.isHittable }?.swipeUp()
        }
        more.tap()
        app.swipeUp()
        shot(app, "24 new tile more options")
        app.buttons["Cancel"].firstMatch.tap()
        shot(app, "25 discard dialog")
        app.buttons["Discard changes"].firstMatch.tap()

        contextMenu(app, "editTile.snack", "Edit tile")
        XCTAssertTrue(app.navigationBars["Edit folder"].waitForExistence(timeout: 3))
        shot(app, "26 edit folder")
        app.buttons["Choose emoji…"].firstMatch.tap()
        shot(app, "27 emoji picker")
        app.buttons["Cancel"].firstMatch.tap()
        app.buttons["Cancel"].firstMatch.tap()

        el(app, "editTile.hi").press(forDuration: 1.2)
        shot(app, "28 tile context menu")
        app.buttons["Edit tile"].firstMatch.tap()
        app.buttons["Cancel"].firstMatch.tap()

        el(app, "gridSize").tap()
        shot(app, "29 grid size sheet")
        app.buttons["Cancel"].firstMatch.tap()

        el(app, "editTile.snack").press(forDuration: 1.2)
        app.buttons["Open folder"].firstMatch.tap()
        shot(app, "30 editing folder")
    }

    @MainActor
    func testTourSheets() {
        let app = launchHum(["-skipFirstRun", "-demoHistory"])
        openParentMode(app)
        el(app, "boardsMenu").tap()
        shot(app, "40 boards menu")
        app.buttons["Home & folders…"].firstMatch.tap()
        shot(app, "41 home and folders")
        boardRow(app, "Home").tap()
        shot(app, "42 board detail")
        goBack(app, from: "Home & folders")
        closeSheet(app)

        tapToolbar(app, "history", label: "History")
        shot(app, "43 history")
        closeSheet(app)

        tapToolbar(app, "setupSharing", label: "Setup & sharing")
        shot(app, "44 setup and sharing")
        app.swipeUp()
        shot(app, "45 setup and sharing bottom")
        closeSheet(app)

        tapToolbar(app, "settings", label: "Settings")
        shot(app, "46 settings top")
        for i in 1...8 {
            app.swipeUp()
            shot(app, "47 settings \(i)")
        }
        closeSheet(app)

        el(app, "addMenu").tap()
        app.buttons["Paste phrases…"].firstMatch.tap()
        app.typeText("Let's go to the park!\nGood job\nNo thank you\nTo infinity and beyond!")
        shot(app, "49 paste phrases")
        app.buttons["Cancel"].firstMatch.tap()
        app.buttons["Discard"].firstMatch.tap()

        // Only devices with Apple Intelligence have the helper (none on iOS 18).
        guard tapToolbarIfPresent(app, "aiHelper", label: "Help me set up") else { return }
        shot(app, "50 ai helper off")
        el(app, "turnOnAI").tap()
        shot(app, "51 ai helper on")
    }

    /// Needs TestFixtures/Local/Express2-v2.hum (a big real-world setup); skipped without it.
    @MainActor
    func testTourBigImport() throws {
        guard let path = Self.localFixture("Express2-v2.hum") else { throw XCTSkip("No TestFixtures/Local/Express2-v2.hum") }
        let app = launchHum(["-skipFirstRun", "-startInParent", "-importFile", path])
        let summary = el(app, "importSummary")
        XCTAssertTrue(summary.waitForExistence(timeout: 30))
        shot(app, "60 import preview merge")
        app.buttons["Replace everything"].firstMatch.tap()
        shot(app, "62 import preview replace")
        app.swipeUp()
        shot(app, "61 import preview scrolled")
        el(app, "applyImport").tap()
        shot(app, "63 replace confirm")
        app.buttons.matching(NSPredicate(format: "label == %@", "Replace everything")).lastMatch.tap()
        sleep(2)
        shot(app, "64 importing")
        XCTAssertTrue(el(app, "importSummary").waitForNonExistence(timeout: 180))
        shot(app, "65 editor after import")
        el(app, "exitParentMode").tap()
        sleep(2)
        shot(app, "66 child after import")
    }
}

extension XCUIElementQuery {
    var lastMatch: XCUIElement { element(boundBy: count - 1) }
}
