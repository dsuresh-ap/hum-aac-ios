// Copyright 2026 The Hum Authors
// SPDX-License-Identifier: Apache-2.0

import XCTest

/// End-to-end flows. Every launch uses -uiTesting: an in-memory store and fresh settings.
final class HumUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    private func launch(_ args: String...) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTesting"] + args
        app.launch()
        return app
    }

    @MainActor
    private func element(_ app: XCUIApplication, _ id: String) -> XCUIElement {
        app.descendants(matching: .any)[id].firstMatch
    }

    @MainActor
    private func openParentMode(_ app: XCUIApplication) {
        element(app, "editGate").press(forDuration: 3.5)
        XCTAssertTrue(element(app, "exitParentMode").waitForExistence(timeout: 5), "Holding the lock should open grown-up settings")
    }

    @MainActor
    func testFirstRunWithStarterBoard() {
        let app = launch()
        element(app, "firstRun.start").tap()
        app.buttons["Next"].firstMatch.tap()   // voice
        app.buttons["Next"].firstMatch.tap()   // grid size
        element(app, "firstRun.starter").tap()
        XCTAssertTrue(element(app, "tile.hi").waitForExistence(timeout: 5))
        XCTAssertTrue(element(app, "tile.no thank you").exists, "Protest tiles must be on Home")
    }

    @MainActor
    func testTapTileSpeaksIntoHistory() {
        let app = launch("-skipFirstRun", "-demoHistory")
        element(app, "tile.snack").tap()
        XCTAssertTrue(app.buttons["Said: Let's have a snack. Say it again."].waitForExistence(timeout: 3))
    }

    @MainActor
    func testQuickHoldDoesNotOpenParentMode() {
        let app = launch("-skipFirstRun")
        element(app, "editGate").press(forDuration: 1)
        XCTAssertFalse(element(app, "exitParentMode").waitForExistence(timeout: 2))
    }

    @MainActor
    func testEditGateAddTileAndUndo() {
        let app = launch("-skipFirstRun")
        openParentMode(app)
        element(app, "emptySlot.3.3").tap()
        let field = element(app, "spokenTextField")
        XCTAssertTrue(field.waitForExistence(timeout: 3))
        field.tap()
        field.typeText("All aboard!")
        element(app, "saveTile").tap()
        XCTAssertTrue(element(app, "editTile.All aboard").waitForExistence(timeout: 3))
        app.buttons["Undo"].firstMatch.tap()
        XCTAssertTrue(element(app, "emptySlot.3.3").waitForExistence(timeout: 3), "Undo should remove the new tile")
    }

    @MainActor
    func testFolderOpensAndBackReturns() {
        let app = launch("-skipFirstRun", "-demoFolder")
        element(app, "tile.snack").tap()
        XCTAssertTrue(element(app, "tile.crackers").waitForExistence(timeout: 3))
        element(app, "back").tap()
        XCTAssertTrue(element(app, "tile.hi").waitForExistence(timeout: 3))
    }

    @MainActor
    func testImportPreviewApplyAndUndo() {
        let app = launch("-skipFirstRun", "-demoPendingImport", "-startInParent")
        let summary = element(app, "importSummary")
        XCTAssertTrue(summary.waitForExistence(timeout: 5))
        XCTAssertTrue(summary.label.contains("No tiles will move."))
        element(app, "applyImport").tap()
        XCTAssertTrue(element(app, "editTile.all aboard").waitForExistence(timeout: 3))
        app.buttons["Undo"].firstMatch.tap()
        XCTAssertTrue(element(app, "emptySlot.3.3").waitForExistence(timeout: 3), "Undo should remove the imported tile")
    }
}
