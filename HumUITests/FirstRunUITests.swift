// Copyright 2026 The Hum Authors
// SPDX-License-Identifier: Apache-2.0

import XCTest

/// A parent opening Hum for the first time: Welcome → Voice → Grid size → Start.
final class FirstRunUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    private func goToStartChoice(_ app: XCUIApplication, grid: String? = nil) {
        el(app, "firstRun.start").tap()
        app.buttons["Next"].firstMatch.tap()
        if let grid { app.buttons[grid].firstMatch.tap() }
        app.buttons["Next"].firstMatch.tap()
        XCTAssertTrue(app.staticTexts["How do you want to start?"].waitForExistence(timeout: 3))
    }

    /// Scenario: the parent picks an empty board. They get exactly the grid they chose, with nothing on it,
    /// and land on the child's screen (not the editor).
    @MainActor
    func testEmptyBoardHasTheChosenSize() {
        let app = launchHum()
        goToStartChoice(app, grid: "2 × 2")
        XCTAssertTrue(app.staticTexts["A blank 2 × 2 board to fill with your child's own phrases."].exists,
                      "The empty-board choice should repeat the size picked a step earlier")
        el(app, "firstRun.empty").tap()
        XCTAssertTrue(el(app, "editGate").waitForExistence(timeout: 5), "Setup should end on the child's screen")
        XCTAssertFalse(app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'tile.'")).firstMatch.exists, "An empty board has no tiles")

        openParentMode(app)
        XCTAssertTrue(el(app, "emptySlot.1.1").exists)
        XCTAssertFalse(el(app, "emptySlot.2.0").exists, "2 × 2 has no third row")
        XCTAssertFalse(el(app, "emptySlot.0.2").exists, "2 × 2 has no third column")
    }

    /// Scenario: Back walks through the steps without losing the grid choice.
    @MainActor
    func testBackKeepsTheGridChoice() {
        let app = launchHum()
        goToStartChoice(app, grid: "3 × 4")
        app.buttons["Back"].firstMatch.tap()
        XCTAssertTrue(app.staticTexts["How many tiles on a screen?"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["3 × 4"].firstMatch.isSelected, "The picked size should still be selected")
        app.buttons["Back"].firstMatch.tap()
        XCTAssertTrue(app.staticTexts["Pick a voice"].waitForExistence(timeout: 3))
    }

    /// Scenario: Skip on the voice step goes on to the grid step.
    @MainActor
    func testSkipVoice() {
        let app = launchHum()
        el(app, "firstRun.start").tap()
        app.buttons["Skip"].firstMatch.tap()
        XCTAssertTrue(app.staticTexts["How many tiles on a screen?"].waitForExistence(timeout: 3))
    }

    /// Scenario: a parent picks 2 × 2 ("fewer, bigger tiles"). The starter board keeps its own 5 × 4 size,
    /// and its card says so before they choose it; new folders use 2 × 2 (HUM-003).
    @MainActor
    func testStarterCardSaysItsOwnSize() {
        let app = launchHum()
        goToStartChoice(app, grid: "2 × 2")
        let starter = el(app, "firstRun.starter")
        XCTAssertTrue(starter.waitForExistence(timeout: 3))
        XCTAssertTrue(starter.label.contains("5 × 4"), "The starter card says it's 5 × 4")
        XCTAssertTrue(starter.label.contains("2 × 2"), "…and that new folders use the chosen size")
        starter.tap()
        XCTAssertTrue(el(app, "tile.hi").waitForExistence(timeout: 5))
    }

    /// Scenario: at the largest text size, the last step still shows the start buttons, and the footnote
    /// (how to get back in, what Hum is, privacy) can be scrolled to.
    @MainActor
    func testStartFootnoteAtTheLargestTextSize() {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTesting", "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
        app.launch()
        goToStartChoice(app)
        XCTAssertTrue(el(app, "firstRun.starter").isHittable, "The footnote doesn't push the start buttons away")
        let footnote = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH 'To change things later'")).firstMatch
        scrollTo(app, footnote)
        XCTAssertTrue(footnote.exists)
        XCTAssertTrue(app.links["Privacy policy"].exists || app.buttons["Privacy policy"].exists)
        shot(app, "first run footnote, largest text")
    }

    /// Scenario: "Import a setup", then cancel the file picker. Setup is still open, and nothing was
    /// made behind the parent's back (HUM-004).
    @MainActor
    func testCancellingFirstRunImportKeepsSetupOpen() {
        let app = launchHum()
        goToStartChoice(app, grid: "3 × 3")
        el(app, "firstRun.import").tap()
        let cancel = app.buttons["Cancel"].firstMatch
        if cancel.waitForExistence(timeout: 5) { cancel.tap() }
        XCTAssertTrue(app.staticTexts["How do you want to start?"].waitForExistence(timeout: 5), "Still on the start step")
        XCTAssertFalse(el(app, "editGate").exists, "No board was made")
    }

    /// Scenario: picking a bigger grid than the starter grows Home. Nothing moves, and the
    /// protest tiles stay on Home.
    @MainActor
    func testStarterBoardGrowsToABiggerChoiceWithoutMovingTiles() {
        let app = launchHum(isPad ? [] : ["-phoneLayout"])
        goToStartChoice(app, grid: "4 × 5")
        el(app, "firstRun.starter").tap()
        XCTAssertTrue(el(app, "tile.hi").waitForExistence(timeout: 5))
        for label in ["no thank you", "stop", "all done", "break", "too loud", "help"] {
            XCTAssertTrue(el(app, "tile.\(label)").exists, "“\(label)” must be on Home")
        }
    }

    /// Scenario: the voice step lists voices with a play button each, and choosing one marks it.
    @MainActor
    func testChoosingAVoiceMarksIt() throws {
        let app = launchHum()
        el(app, "firstRun.start").tap()
        let play = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Play '")).firstMatch
        try XCTSkipUnless(play.waitForExistence(timeout: 3), "No voices installed on this simulator")
        let name = String(play.label.dropFirst("Play ".count))
        app.buttons[name].firstMatch.tap()
        XCTAssertTrue(app.images["checkmark.circle.fill"].exists || app.buttons[name].firstMatch.isSelected,
                      "The chosen voice should be marked")
    }
}
