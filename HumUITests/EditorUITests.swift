// Copyright 2026 The Hum Authors
// SPDX-License-Identifier: Apache-2.0

import XCTest

/// A parent editing boards: adding, changing, hiding, deleting and moving tiles, and grid sizes.
final class EditorUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    /// Scenario: a new tile's label fills in from the phrase; Save stays off until there are words.
    @MainActor
    func testLabelFollowsThePhraseAndSaveNeedsWords() {
        let app = launchHum(["-skipFirstRun", "-startInParent"])
        el(app, "emptySlot.3.3").tap()
        let field = el(app, "spokenTextField")
        XCTAssertTrue(field.waitForExistence(timeout: 3))
        XCTAssertFalse(app.buttons["saveTile"].firstMatch.isEnabled, "Nothing to say yet, so nothing to save")
        field.typeText("Let's go to the park!")
        XCTAssertTrue(app.buttons["saveTile"].firstMatch.isEnabled)
        // HUM-018: the label doesn't end on a dangling "the".
        XCTAssertEqual(el(app, "labelField").value as? String, "Let's go")
        // Once the parent types their own label, the phrase no longer overwrites it.
        let label = el(app, "labelField")
        label.tap()
        label.press(forDuration: 1.0)
        if app.menuItems["Select All"].waitForExistence(timeout: 2) { app.menuItems["Select All"].tap() }
        label.typeText("park")
        field.tap()
        field.typeText(" Now")
        XCTAssertEqual(label.value as? String, "park", "A label the parent typed must stay")
    }

    /// Scenario: the parent adds a tile, finishes editing, and the child can tap it right away.
    @MainActor
    func testNewTileReachesTheChild() {
        let app = launchHum(["-skipFirstRun", "-startInParent"])
        el(app, "emptySlot.3.3").tap()
        typePhraseAndSave(app, "All aboard!")
        XCTAssertTrue(el(app, "editTile.All aboard").waitForExistence(timeout: 3))
        finishEditing(app)
        let tile = el(app, "tile.All aboard")
        XCTAssertTrue(tile.waitForExistence(timeout: 3))
        XCTAssertEqual(tile.label, "All aboard!")
    }

    /// Scenario: the parent changes what a tile says. The tile keeps its spot.
    @MainActor
    func testEditingAPhraseKeepsTheSpot() {
        let app = launchHum(["-skipFirstRun", "-startInParent"])
        let tile = el(app, "editTile.play")
        XCTAssertTrue(tile.waitForExistence(timeout: 5))
        let spot = tile.frame
        tile.tap()
        let field = el(app, "spokenTextField")
        XCTAssertTrue(field.waitForExistence(timeout: 3))
        // Tap just after the text, so the words go at the end.
        field.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap()
        field.typeText(" with trains")
        el(app, "saveTile").tap()
        let edited = el(app, "editTile.play")
        XCTAssertTrue(edited.waitForExistence(timeout: 3))
        XCTAssertEqual(edited.label, "play. Says: Let's play with trains")
        XCTAssertEqual(edited.frame, spot, "Editing never moves a tile")
    }

    /// Scenario: the parent types a praise phrase. Hum gently suggests the child's own words instead.
    @MainActor
    func testPraisePhraseGetsAGentleWarning() {
        let app = launchHum(["-skipFirstRun", "-startInParent"])
        el(app, "emptySlot.3.3").tap()
        let field = el(app, "spokenTextField")
        XCTAssertTrue(field.waitForExistence(timeout: 3))
        field.typeText("Good job!")
        let warning = app.staticTexts.matching(NSPredicate(format: "label CONTAINS 'sounds like praise or an instruction'")).firstMatch
        XCTAssertTrue(warning.waitForExistence(timeout: 3))
    }

    /// Scenario: Cancel after typing asks before throwing the words away; Discard leaves the board as it was.
    @MainActor
    func testCancelAsksBeforeDiscarding() {
        let app = launchHum(["-skipFirstRun", "-startInParent"])
        el(app, "emptySlot.3.3").tap()
        let field = el(app, "spokenTextField")
        XCTAssertTrue(field.waitForExistence(timeout: 3))
        field.typeText("Choo choo")
        app.buttons["Cancel"].firstMatch.tap()
        XCTAssertTrue(app.staticTexts["Discard your changes?"].waitForExistence(timeout: 3))
        dialogButton(app, "Discard changes").tap()
        XCTAssertTrue(el(app, "emptySlot.3.3").waitForExistence(timeout: 3))
    }

    /// Scenario: delete from the tile editor asks first, leaves an empty spot, and Undo brings it back.
    @MainActor
    func testDeleteFromEditorConfirmsAndUndoes() {
        let app = launchHum(["-skipFirstRun", "-startInParent"])
        el(app, "editTile.up").tap()
        XCTAssertTrue(el(app, "spokenTextField").waitForExistence(timeout: 3))
        let more = app.buttons["More options"].firstMatch
        scrollTo(app, more)
        more.tap()
        let delete = app.buttons["Delete tile"].firstMatch
        scrollTo(app, delete)
        delete.tap()
        XCTAssertTrue(app.staticTexts["Delete this tile?"].waitForExistence(timeout: 3), "Delete must ask first")
        dialogButton(app, "Delete tile").tap()
        XCTAssertTrue(el(app, "emptySlot.1.3").waitForExistence(timeout: 3), "Its spot is empty")
        XCTAssertTrue(el(app, "editTile.up").waitForNonExistence(timeout: 2))
        tapUndo(app)
        XCTAssertTrue(el(app, "editTile.up").waitForExistence(timeout: 3), "Undo brings the tile back (HUM-002)")
    }

    /// Scenario: delete from the long-press menu, then Undo.
    @MainActor
    func testUndoAfterMenuDelete() {
        let app = launchHum(["-skipFirstRun", "-startInParent"])
        contextMenu(app, "editTile.up", "Delete tile")
        dialogButton(app, "Delete tile").tap()
        XCTAssertTrue(el(app, "emptySlot.1.3").waitForExistence(timeout: 3))
        tapUndo(app)
        XCTAssertTrue(el(app, "editTile.up").waitForExistence(timeout: 3), "Undo brings the tile back in the editor (HUM-002)")
        // Is the tile really back, or just redrawn? The child's board is rebuilt from the store.
        finishEditing(app)
        XCTAssertTrue(el(app, "tile.up").waitForExistence(timeout: 3), "Undo brings the tile back for the child")
    }

    /// Scenario: delete from the long-press menu. The spec says every delete asks to confirm.
    @MainActor
    func testDeleteFromMenuAsksFirst() {
        let app = launchHum(["-skipFirstRun", "-startInParent"])
        contextMenu(app, "editTile.up", "Delete tile")
        XCTAssertTrue(app.staticTexts["Delete this tile?"].waitForExistence(timeout: 2), "Delete asks first (HUM-008)")
        XCTAssertTrue(el(app, "editTile.up").exists, "Nothing is deleted until the parent confirms")
    }

    /// Scenario: Duplicate puts a copy in the first empty spot and moves nothing.
    @MainActor
    func testDuplicateTakesAnEmptySpot() {
        let app = launchHum(["-skipFirstRun", "-startInParent"])
        let spot = el(app, "editTile.hi").frame
        contextMenu(app, "editTile.hi", "Duplicate")
        let copies = app.buttons.matching(identifier: "editTile.hi")
        XCTAssertTrue(copies.element(boundBy: 1).waitForExistence(timeout: 3))
        XCTAssertEqual(copies.count, 2)
        XCTAssertFalse(el(app, "emptySlot.3.3").exists, "The copy fills the first empty spot")
        XCTAssertEqual(copies.element(boundBy: 0).frame, spot, "The original doesn't move")
    }

    /// Scenario: "Move to folder" takes the tile into the folder, says so, and offers to open it.
    @MainActor
    func testMoveToFolder() {
        let app = launchHum(["-skipFirstRun", "-demoFolder", "-startInParent"])
        el(app, "editTile.outside").press(forDuration: 1.2)
        app.buttons["Move to folder"].firstMatch.tap()
        app.buttons["Food"].firstMatch.tap()
        XCTAssertTrue(app.staticTexts["Moved “outside” into Food."].waitForExistence(timeout: 3))
        XCTAssertTrue(el(app, "emptySlot.2.3").exists, "Its old spot is empty; nothing slides in")
        app.buttons["Open folder"].firstMatch.tap()
        XCTAssertTrue(app.staticTexts["Editing Food"].waitForExistence(timeout: 3))
        XCTAssertTrue(el(app, "editTile.outside").exists)
    }

    /// Scenario: the parent taps a folder tile to rename it.
    @MainActor
    func testTappingAFolderTileEditsIt() {
        let app = launchHum(["-skipFirstRun", "-demoFolder", "-startInParent"])
        el(app, "editTile.snack").tap()
        // HUM-006: on narrow tiles the Open button sits in a corner, so the picture edits the tile.
        XCTAssertTrue(app.navigationBars["Edit folder"].waitForExistence(timeout: 3), "Tapping a tile edits it")
    }

    /// Scenario: inside a folder, the band's Back button returns to Home.
    @MainActor
    func testBackFromAFolderInTheEditor() {
        let app = launchHum(["-skipFirstRun", "-demoFolder", "-startInParent"])
        contextMenu(app, "editTile.snack", "Open folder")
        XCTAssertTrue(app.staticTexts["Editing Food"].waitForExistence(timeout: 3))
        app.buttons["Back to Home"].firstMatch.tap()
        XCTAssertTrue(app.staticTexts["Editing Home"].waitForExistence(timeout: 3))
    }

    /// Scenario: a bigger grid adds empty spots at the bottom and right.
    @MainActor
    func testGrowingTheGridAddsEmptySpots() {
        let app = launchHum(["-skipFirstRun", "-startInParent"])
        el(app, "gridSize").tap()
        let rowsUp = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Rows:' AND identifier == 'Increment'")).firstMatch
        XCTAssertTrue(rowsUp.waitForExistence(timeout: 3))
        rowsUp.tap()
        el(app, "applyGridSize").tap()
        XCTAssertTrue(el(app, "gridSize").label.contains("6 rows, 4 columns"))
        XCTAssertTrue(el(app, "editTile.hi").exists)
        // On iPhone a 6 × 4 board still fits the phone, so the new row shows here.
        if !isPad { XCTAssertTrue(el(app, "emptySlot.5.0").waitForExistence(timeout: 3)) }
    }

    /// Scenario: shrinking cuts off tiles. Hum names them and puts them in the "needs a spot" tray only
    /// if the parent agrees; nothing is deleted.
    @MainActor
    func testShrinkingAsksAndUsesTheTray() {
        let app = launchHum(["-skipFirstRun", "-startInParent"])
        el(app, "gridSize").tap()
        let rowsDown = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Rows:' AND identifier == 'Decrement'")).firstMatch
        XCTAssertTrue(rowsDown.waitForExistence(timeout: 3))
        rowsDown.tap()
        el(app, "applyGridSize").tap()
        XCTAssertTrue(app.staticTexts["3 tiles won't fit"].waitForExistence(timeout: 3))
        dialogButton(app, "Move them to “needs a spot”").tap()
        // HUM-024: they aren't "new" tiles.
        XCTAssertTrue(app.staticTexts["3 tiles need a spot. Drag each one onto the board."].waitForExistence(timeout: 3))
    }

    /// Scenario: no "smaller than 88 points" jargon (HUM-005).
    @MainActor
    func testNoTechnicalSizeWarning() {
        let app = launchHum(["-skipFirstRun", "-startInParent"])
        XCTAssertTrue(el(app, "editTile.hi").waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts.matching(NSPredicate(format: "label CONTAINS 'points'")).firstMatch.exists)
    }
}
