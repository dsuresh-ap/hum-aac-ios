// Copyright 2026 The Hum Authors
// SPDX-License-Identifier: Apache-2.0

import XCTest

/// "Home & folders": making, renaming, duplicating and deleting folders, and choosing Home.
final class BoardsUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    private func openBoards(_ app: XCUIApplication) {
        el(app, "boardsMenu").tap()
        labeled(app, "Home & folders…").firstMatch.tap()
        XCTAssertTrue(app.navigationBars["Home & folders"].waitForExistence(timeout: 3))
    }

    /// Scenario: the parent makes a "Food" folder. A folder tile appears on Home and the new folder
    /// opens so they can fill it.
    @MainActor
    func testMakeAFolder() {
        let app = launchHum(["-skipFirstRun", "-startInParent"])
        openBoards(app)
        let name = app.textFields["Folder name, e.g. Food or Outside"]
        name.tap()
        name.typeText("Food")
        app.buttons["Make folder"].firstMatch.tap()
        XCTAssertTrue(app.staticTexts["Editing Food"].waitForExistence(timeout: 3), "The new folder opens to be filled")
        app.buttons["Back to Home"].firstMatch.tap()
        XCTAssertTrue(el(app, "editTile.Food").waitForExistence(timeout: 3), "A folder tile is on Home")
        finishEditing(app)
        el(app, "tile.Food").tap()
        XCTAssertTrue(app.staticTexts["Food"].waitForExistence(timeout: 3), "The child can open it")
    }

    /// Scenario: renaming a folder in Home & folders. The child sees the folder's tile, so its label
    /// should follow.
    @MainActor
    func testRenamingAFolderRenamesItsTile() {
        let app = launchHum(["-skipFirstRun", "-startInParent"])
        openBoards(app)
        let new = app.textFields["Folder name, e.g. Food or Outside"]
        new.tap()
        new.typeText("Food")
        app.buttons["Make folder"].firstMatch.tap()
        XCTAssertTrue(app.staticTexts["Editing Food"].waitForExistence(timeout: 3))
        openBoards(app)
        boardRow(app, "Food").tap()
        let field = app.textFields["Name"].firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 3))
        field.tap()
        field.typeText(" and drink\n")
        goBack(app, from: "Home & folders")
        XCTAssertTrue(app.staticTexts["Food and drink"].waitForExistence(timeout: 3))
        closeSheet(app)
        app.buttons["Back to Home"].firstMatch.tap()
        XCTAssertTrue(el(app, "editTile.Food").waitForExistence(timeout: 3) || el(app, "editTile.Food and drink").exists)
        XCTExpectFailure("HUM-039: renaming a folder in Home & folders leaves its folder tile with the old name") {
            XCTAssertTrue(el(app, "editTile.Food and drink").waitForExistence(timeout: 3))
        }
    }

    /// Scenario: Duplicate makes "Home copy". No tile opens it yet, and the list says so.
    @MainActor
    func testDuplicateIsFlaggedAsUnreachable() {
        let app = launchHum(["-skipFirstRun", "-startInParent"])
        openBoards(app)
        boardRow(app, "Home").press(forDuration: 1.2)
        app.buttons["Duplicate"].firstMatch.tap()
        XCTAssertTrue(app.staticTexts["Home copy"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["No tile opens this folder yet"].exists)
    }

    /// Scenario: deleting a folder asks first. Its folder tile stays on Home and still speaks.
    @MainActor
    func testDeleteAFolderKeepsItsTile() {
        let app = launchHum(["-skipFirstRun", "-demoFolder", "-startInParent"])
        openBoards(app)
        boardRow(app, "Food").press(forDuration: 1.2)
        app.buttons["Delete…"].firstMatch.tap()
        XCTAssertTrue(app.staticTexts["Delete Food?"].waitForExistence(timeout: 3), "Deleting a folder asks first")
        dialogButton(app, "Delete folder").tap()
        XCTAssertTrue(app.staticTexts["Food"].waitForNonExistence(timeout: 3))
        closeSheet(app)
        finishEditing(app)
        let snack = el(app, "tile.snack")
        XCTAssertTrue(snack.waitForExistence(timeout: 3), "The tile that opened it stays")
        snack.tap()
        XCTAssertTrue(el(app, "tile.hi").exists, "It just speaks now; the child stays on Home")
    }

    /// Scenario: the parent makes a folder the Home board. The child starts there, and Home goes there.
    /// Protest tiles should still be reachable; Hum doesn't warn when the new Home has none.
    @MainActor
    func testMakeAFolderHome() {
        let app = launchHum(["-skipFirstRun", "-demoFolder", "-startInParent"])
        openBoards(app)
        boardRow(app, "Food").press(forDuration: 1.2)
        app.buttons["Make Home board"].firstMatch.tap()
        XCTExpectFailure("HUM-040: making a board without “stop”/“no thank you” the Home board gives no warning") {
            XCTAssertTrue(app.alerts.firstMatch.waitForExistence(timeout: 2))
        }
        closeSheet(app)
        finishEditing(app)
        el(app, "home").tap()
        XCTAssertTrue(el(app, "tile.crackers").waitForExistence(timeout: 3), "Home now goes to Food")
    }
}
